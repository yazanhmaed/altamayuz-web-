import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

export const notifyNewOrder = onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const order = event.data?.data();
    if (!order || order.source !== "storefront") return;

    const db = getFirestore();
    const ownerDoc = await db.collection("settings").doc("owner").get();
    const token = ownerDoc.data()?.fcmToken;
    if (!token) return;

    await getMessaging().send({
      token,
      notification: {
        title: "طلب جديد من المتجر",
        body: `${order.customerName} — ${order.items.length} قطعة`,
      },
      data: { orderId: event.params.orderId },
    });
  }
);
