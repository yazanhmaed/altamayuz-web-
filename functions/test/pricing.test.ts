// Same cases as storefront/test/promotion_pricing_test.dart and
// admin_app/test/promotion_pricing_test.dart. Run: npm test
import { test } from "node:test";
import assert from "node:assert/strict";

import { effectivePrice, PromotionLike, roundMoney } from "../src/pricing";

const now = new Date("2026-11-11T12:00:00Z");
const hours = (h: number) => new Date(now.getTime() + h * 3600 * 1000);

function promo(over: Partial<PromotionLike> = {}): PromotionLike {
  return {
    id: "p1",
    name: "Promo",
    amountOff: 5,
    productIds: ["shoe"],
    startAt: hours(-1),
    endAt: hours(1),
    isActive: true,
    ...over,
  };
}

function price(
  promos: PromotionLike[],
  opts: { base?: number; sale?: number | null } = {}
) {
  return effectivePrice(
    { id: "shoe", price: opts.base ?? 50, salePrice: opts.sale ?? null },
    promos,
    now
  );
}

test("no promo", () => {
  const r = price([]);
  assert.equal(r.price, 50);
  assert.equal(r.source, "none");
  assert.equal(r.discountPercent, 0);
  assert.equal(r.savedAmount, 0);
  assert.equal(r.promotion, null);
});

test("sale only", () => {
  const r = price([], { sale: 45 });
  assert.equal(r.price, 45);
  assert.equal(r.source, "sale");
  assert.equal(r.discountPercent, 10);
  assert.equal(r.savedAmount, 5);
});

test("invalid sale price is ignored", () => {
  assert.equal(price([], { sale: 60 }).source, "none");
  assert.equal(price([], { sale: 0 }).source, "none");
});

test("amount below price", () => {
  const r = price([promo()]);
  assert.equal(r.price, 45);
  assert.equal(r.source, "promo:p1");
  assert.equal(r.discountPercent, 10);
  assert.equal(r.savedAmount, 5);
  assert.equal(r.promotion?.id, "p1");
});

test("same amount on different prices, derived percent", () => {
  const p = [promo({ amountOff: 3 })];
  const a = price(p, { base: 20 });
  assert.equal(a.price, 17);
  assert.equal(a.discountPercent, 15);
  const b = price(p, { base: 12.5 });
  assert.equal(b.price, 9.5);
  assert.equal(b.discountPercent, 24);
  const c = price(p, { base: 33.99 });
  assert.equal(c.price, 30.99);
  assert.equal(c.discountPercent, 9);
});

test("amount equal to price is skipped", () => {
  const r = price([promo({ amountOff: 50 })]);
  assert.equal(r.price, 50);
  assert.equal(r.source, "none");
});

test("amount greater than price is skipped", () => {
  assert.equal(price([promo({ amountOff: 60 })]).source, "none");
});

test("amount leaving less than the minimum price is skipped", () => {
  const r = price([promo({ amountOff: 3 })], { base: 3.2 });
  assert.equal(r.price, 3.2);
  assert.equal(r.source, "none");
});

test("amount leaving exactly the minimum price applies", () => {
  assert.equal(price([promo({ amountOff: 3 })], { base: 3.5 }).price, 0.5);
  // 1.2 − 0.7 is 0.4999… in binary; the rounded value is compared.
  assert.equal(price([promo({ amountOff: 0.7 })], { base: 1.2 }).price, 0.5);
});

test("better sale price wins", () => {
  const r = price([promo()], { sale: 40 });
  assert.equal(r.price, 40);
  assert.equal(r.source, "sale");
});

test("worse sale price loses to the promotion", () => {
  const r = price([promo()], { sale: 48 });
  assert.equal(r.price, 45);
  assert.equal(r.source, "promo:p1");
});

test("two promos: best wins, no stacking", () => {
  const r = price([promo(), promo({ id: "p2", amountOff: 8 })]);
  assert.equal(r.price, 42);
  assert.equal(r.source, "promo:p2");
  assert.equal(r.savedAmount, 8);
});

test("legacy percent doc still works", () => {
  const r = price([promo({ amountOff: null, percent: 20 })]);
  assert.equal(r.price, 40);
  assert.equal(r.source, "promo:p1");
  assert.equal(r.discountPercent, 20);
});

test("legacy percent vs amount promo: best wins", () => {
  const r = price([
    promo({ amountOff: 5 }),
    promo({ id: "old", amountOff: null, percent: 20 }),
  ]);
  assert.equal(r.price, 40);
  assert.equal(r.source, "promo:old");
});

test("amountOff takes precedence over a leftover percent", () => {
  assert.equal(price([promo({ amountOff: 5, percent: 50 })]).price, 45);
});

test("expired promo is ignored", () => {
  const r = price([promo({ startAt: hours(-3), endAt: hours(-1) })]);
  assert.equal(r.source, "none");
});

test("promo ending exactly now is ignored", () => {
  assert.equal(price([promo({ endAt: now })]).source, "none");
});

test("scheduled promo is ignored", () => {
  assert.equal(
    price([promo({ startAt: hours(1), endAt: hours(3) })]).source,
    "none"
  );
});

test("promo starting exactly now applies", () => {
  assert.equal(price([promo({ startAt: now })]).source, "promo:p1");
});

test("inactive promo is ignored", () => {
  assert.equal(price([promo({ isActive: false })]).source, "none");
});

test("product not in list", () => {
  assert.equal(price([promo({ productIds: ["other"] })]).source, "none");
});

test("rounding half up to 2 decimals", () => {
  assert.equal(price([promo({ amountOff: 2.5 })], { base: 19.99 }).price, 17.49);
  // legacy: 12.35 × 0.9 = 11.115 → 11.12 (half up)
  assert.equal(
    price([promo({ amountOff: null, percent: 10 })], { base: 12.35 }).price,
    11.12
  );
  assert.equal(roundMoney(1.005), 1.01);
});
