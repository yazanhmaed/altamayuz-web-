import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getFirestore } from "firebase-admin/firestore";

export const syncPublicProduct = onDocumentWritten(
  "products/{productId}",
  async (event) => {
    const db = getFirestore();
    const productId = event.params.productId;
    const after = event.data?.after.data();
    const publicRef = db.collection("products_public").doc(productId);

    if (!after || !after.isActive || !after.price) {
      await publicRef.delete().catch(() => {});
      return;
    }

    const colors: string[] = after.colors ?? [];
    const stock: Record<string, Record<string, number>> = after.stock ?? {};
    const imageUrls: Record<string, string> = after.imageUrls ?? {};

    const variants = colors.map((color) => ({
      color,
      imageUrl: imageUrls[color] ?? "",
      sizes: stock[color] ?? {},
    }));

    await publicRef.set({
      id: productId,
      name: after.name,
      price: after.price,
      isFeatured: after.isFeatured ?? false,
      variants,
      updatedAt: new Date().toISOString(),
    });
  }
);
