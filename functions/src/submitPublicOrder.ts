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
      const price = data.price as number;

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

    const total = orderItems.reduce(
      (sum, it) => sum + it.unitPrice * it.quantity,
      0
    );

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
