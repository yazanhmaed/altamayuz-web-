// Shared pricing rule for product-group promotions.
//
// MUST stay identical to `effectivePrice` in
// storefront/lib/pricing/promotion_pricing.dart and
// admin_app/lib/utils/promotion_pricing.dart. The three copies have matching
// unit tests (functions/test/pricing.test.ts, storefront/test/
// promotion_pricing_test.dart, admin_app/test/promotion_pricing_test.dart).
//
// Rule: the customer pays the LOWEST of
//   - product.price,
//   - product.salePrice (only when 0 < salePrice < price),
//   - for every running promotion listing the product:
//       price − amountOff (JOD per unit), skipped when that would leave less
//       than MIN_DISCOUNTED_PRICE; or, for legacy documents that only have
//       `percent`, price × (1 − percent/100) as before.
// Discounts never stack. The result is rounded to 2 decimals (half up).

export interface PromotionLike {
  id: string;
  name: string;
  /** JOD off each unit. The current way to define a promotion. */
  amountOff?: number | null;
  /** Legacy: percentage off, read only when `amountOff` is absent. */
  percent?: number | null;
  productIds: string[];
  startAt: Date;
  endAt: Date;
  isActive: boolean;
}

export interface PricedProduct {
  id: string;
  price: number;
  salePrice?: number | null;
}

export interface EffectivePrice {
  /** Final unit price, rounded to 2 decimals. */
  price: number;
  /** 'none', 'sale', or `promo:<id>`. */
  source: string;
  /** The winning promotion, when `source` is `promo:<id>`. */
  promotion: PromotionLike | null;
  /** round((price − result) / price × 100). */
  discountPercent: number;
  /** price − result (JOD saved per unit), 0 when not discounted. */
  savedAmount: number;
}

/** Legacy percentage promotions only (new ones use `amountOff`). */
export const MIN_PROMO_PERCENT = 1;
export const MAX_PROMO_PERCENT = 90;
export const MAX_PROMO_PRODUCTS = 200;

/** A fixed-amount promotion never takes a product below this price (JOD);
 * when it would, it is not applied to that product. */
export const MIN_DISCOUNTED_PRICE = 0.5;

/** Round half up to 2 decimals, immune to binary noise like 1.005 * 100. */
export function roundMoney(value: number): number {
  const cents = Number((value * 100).toPrecision(12));
  return Math.round(cents) / 100;
}

/** A usable discount: amountOff > 0, or (legacy) percent in 1–90. */
export function hasValidDiscount(p: PromotionLike): boolean {
  const a = p.amountOff;
  if (typeof a === "number") return Number.isFinite(a) && a > 0;
  const pct = p.percent;
  return (
    typeof pct === "number" &&
    Number.isFinite(pct) &&
    pct >= MIN_PROMO_PERCENT &&
    pct <= MAX_PROMO_PERCENT
  );
}

/** True when the promotion is switched on, has a valid discount, and `now`
 * is inside [startAt, endAt). */
export function isPromotionRunning(p: PromotionLike, now: Date): boolean {
  return (
    p.isActive === true &&
    hasValidDiscount(p) &&
    p.startAt.getTime() <= now.getTime() &&
    now.getTime() < p.endAt.getTime()
  );
}

/** This promotion's price for a product priced `price` (dates ignored), or
 * null when it can't apply: invalid discount, or an amount that would leave
 * less than MIN_DISCOUNTED_PRICE. */
export function promotionCandidate(
  p: PromotionLike,
  price: number
): number | null {
  if (!hasValidDiscount(p)) return null;
  const a = p.amountOff;
  if (typeof a === "number") {
    const c = roundMoney(price - a);
    return c < MIN_DISCOUNTED_PRICE ? null : c;
  }
  return roundMoney(price * (1 - (p.percent as number) / 100));
}

export function effectivePrice(
  product: PricedProduct,
  promotions: PromotionLike[],
  now: Date
): EffectivePrice {
  const base = product.price;
  let best = base;
  let source = "none";
  let promotion: PromotionLike | null = null;

  const sale = product.salePrice;
  if (typeof sale === "number" && sale > 0 && sale < base) {
    best = sale;
    source = "sale";
  }

  for (const p of promotions) {
    if (!isPromotionRunning(p, now)) continue;
    if (!Array.isArray(p.productIds) || !p.productIds.includes(product.id)) {
      continue;
    }
    const candidate = promotionCandidate(p, base);
    if (candidate === null) continue; // would go below the minimum price
    // Strictly lower only: on a tie the existing sale price (or the first
    // promotion seen) keeps winning.
    if (candidate < best) {
      best = candidate;
      source = `promo:${p.id}`;
      promotion = p;
    }
  }

  const price = roundMoney(best);
  const discountPercent =
    base > 0 && price < base ? Math.round(((base - price) / base) * 100) : 0;
  const savedAmount = price < base ? roundMoney(base - price) : 0;
  return { price, source, promotion, discountPercent, savedAmount };
}
