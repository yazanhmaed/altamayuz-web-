import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

interface CartItem {
  productId: string;
  color: string;
  size: string;
  quantity: number;
}

interface RequestData {
  customerName: string;
  customerPhone: string;
  address: string;
  area: string;
  street: string;
  items: CartItem[];
}

interface CartDiscountTier {
  minQuantity: number;
  type: "percentage" | "fixed";
  value: number;
}

// Defensive sanitization of the `settings/cartDiscountTiers` document. The
// server assumes NO upstream source has validated this — not the admin app,
// not a manual Firestore Console edit. Discard: minQuantity < 2; percentage
// value outside 0–100; fixed value <= 0. Then sort by minQuantity ascending
// ourselves rather than trusting the stored order.
function sanitizeTiers(raw: unknown): CartDiscountTier[] {
  const list = Array.isArray(raw) ? raw : [];
  const clean: CartDiscountTier[] = [];
  for (const t of list) {
    if (!t || typeof t !== "object") continue;
    const minQuantity = Number((t as any).minQuantity);
    const type = (t as any).type;
    const value = Number((t as any).value);
    if (!Number.isFinite(minQuantity) || minQuantity < 2) continue;
    if (!Number.isFinite(value)) continue;
    if (type === "percentage") {
      if (value < 0 || value > 100) continue;
    } else if (type === "fixed") {
      if (value <= 0) continue;
    } else {
      continue;
    }
    clean.push({ minQuantity, type, value });
  }
  clean.sort((a, b) => a.minQuantity - b.minQuantity);
  return clean;
}

// Same tier-selection + clamp math as the storefront's computeCartDiscount:
// exactly one tier applies (highest minQuantity the cart's total quantity
// meets), tiers never stack, and a `fixed` discount larger than the subtotal
// is clamped down to exactly the subtotal (net total floors at 0, never
// negative). Returns the discount amount and the applied tier's minQuantity
// (or null).
function computeCartDiscount(
  tiers: CartDiscountTier[],
  totalQuantity: number,
  subtotal: number
): { amount: number; tierMinQuantity: number | null } {
  const applicable = tiers
    .filter((t) => totalQuantity >= t.minQuantity)
    .sort((a, b) => a.minQuantity - b.minQuantity);
  if (applicable.length === 0) return { amount: 0, tierMinQuantity: null };
  const tier = applicable[applicable.length - 1];
  const rawAmount =
    tier.type === "percentage" ? subtotal * (tier.value / 100) : tier.value;
  const amount = Math.min(Math.max(rawAmount, 0), subtotal);
  return { amount, tierMinQuantity: tier.minQuantity };
}

// App Check is intentionally not enforced: the owner reviews every order
// before dispatch, so client tampering is caught manually. Server-side price
// derivation and the per-phone rate limit below are kept — they cost nothing
// operationally.
export const submitPublicOrder = onCall<RequestData>(async (request) => {
  const { customerName, customerPhone, address, area, street, items } =
    request.data;

  if (!customerName || !customerPhone || !address || !area || !items?.length) {
    throw new HttpsError("invalid-argument", "بيانات الطلب ناقصة.");
  }
  for (const it of items) {
    if (!it.productId || !it.color || !it.size || it.quantity <= 0) {
      throw new HttpsError("invalid-argument", "عنصر غير صالح في السلة.");
    }
  }

  const db = getFirestore();

  // rate limit: one order per phone per 2 minutes.
  // `createdAt` is stored as a Firestore Timestamp (see tx.set below and the
  // admin app), so the bound must be a Timestamp too — comparing a Timestamp
  // field against a raw JS Date matches nothing.
  const twoMinAgo = Timestamp.fromDate(new Date(Date.now() - 2 * 60 * 1000));
  const recentOrders = await db
    .collection("orders")
    .where("customerPhone", "==", customerPhone)
    .where("createdAt", ">=", twoMinAgo)
    .limit(1)
    .get();

  if (!recentOrders.empty) {
    throw new HttpsError(
      "resource-exhausted",
      "تم استلام طلب منك مؤخرًا، الرجاء الانتظار قليلًا قبل إرسال طلب آخر."
    );
  }

  // Cart-wide quantity-discount tiers. This is config, not part of the
  // inventory-consistency invariant the transaction protects, so a plain
  // read outside the transaction is fine. A missing document / missing
  // `tiers` field just means "no discount".
  const tiersSnap = await db
    .collection("settings")
    .doc("cartDiscountTiers")
    .get();
  const cartDiscountTiers = sanitizeTiers(tiersSnap.data()?.tiers);

  const orderRef = db.collection("orders").doc();

  await db.runTransaction(async (tx) => {
    const need: Record<string, Record<string, Record<string, number>>> = {};
    for (const it of items) {
      need[it.productId] ??= {};
      need[it.productId][it.color] ??= {};
      need[it.productId][it.color][it.size] =
        (need[it.productId][it.color][it.size] ?? 0) + it.quantity;
    }

    const productDocs: Record<string, FirebaseFirestore.DocumentData> = {};
    for (const productId of Object.keys(need)) {
      const ref = db.collection("products").doc(productId);
      const snap = await tx.get(ref);
      if (!snap.exists) {
        throw new HttpsError("not-found", `المنتج (${productId}) غير موجود.`);
      }
      const data = snap.data()!;
      if (!data.isActive || !data.price) {
        throw new HttpsError(
          "failed-precondition",
          `المنتج (${data.name}) غير متاح للبيع حاليًا.`
        );
      }
      productDocs[productId] = data;
    }

    const orderItems: any[] = [];
    for (const [productId, colors] of Object.entries(need)) {
      const data = productDocs[productId];
      const stock = { ...data.stock };
      const price: number =
        data.salePrice && data.salePrice > 0 && data.salePrice < data.price
          ? data.salePrice
          : data.price;

      for (const [color, sizes] of Object.entries(colors)) {
        const colorStock = { ...(stock[color] ?? {}) };
        for (const [size, qty] of Object.entries(sizes)) {
          const current = colorStock[size] ?? 0;
          if (current < qty) {
            throw new HttpsError(
              "failed-precondition",
              `الكمية غير كافية: ${data.name} (${color} - ${size}).`
            );
          }
          colorStock[size] = current - qty;
          orderItems.push({
            itemId: db.collection("_").doc().id,
            productId,
            productName: data.name,
            color,
            size,
            quantity: qty,
            sku: `${productId}-${color}-${size}`,
            unitPrice: price,
            isPrimary: true,
            status: "pending",
          });
        }
        stock[color] = colorStock;
      }

      tx.update(db.collection("products").doc(productId), {
        stock,
        updatedAt: new Date().toISOString(),
      });
    }

    // Pre-discount sum of the order lines (each unitPrice is already the
    // server-derived salePrice/price, so per-product discounts are baked in).
    const subtotal = orderItems.reduce(
      (sum, it) => sum + it.unitPrice * it.quantity,
      0
    );

    // Cart-wide quantity discount, recomputed from scratch server-side — the
    // client never sends a discount or total. Operates on the already-
    // discounted subtotal; a product on sale and this discount can both apply.
    const totalQuantity = orderItems.reduce(
      (sum, it) => sum + it.quantity,
      0
    );
    const { amount: cartDiscountAmount, tierMinQuantity } = computeCartDiscount(
      cartDiscountTiers,
      totalQuantity,
      subtotal
    );

    // `total` now means the NET amount owed (subtotal minus the cart discount)
    // — the only figure that matters for payment/delivery.
    const total = subtotal - cartDiscountAmount;

    tx.set(orderRef, {
      id: orderRef.id,
      customerName,
      customerPhone,
      address,
      area,
      street,
      destination: "",
      items: orderItems,
      qrCode: [],
      subtotal,
      cartDiscountAmount,
      cartDiscountTierMinQuantity: tierMinQuantity,
      total,
      status: "pending",
      source: "storefront",
      paymentMethod: "cod",
      createdAt: FieldValue.serverTimestamp(),
      deliveryDate: "",
    });
  });

  return { orderId: orderRef.id };
});
