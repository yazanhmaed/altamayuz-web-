import { initializeApp } from "firebase-admin/app";

initializeApp();

export { syncPublicProduct } from "./syncPublicProduct";
export { submitPublicOrder } from "./submitPublicOrder";
export { notifyNewOrder } from "./notifyNewOrder";
