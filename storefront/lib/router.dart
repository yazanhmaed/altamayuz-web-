import 'package:go_router/go_router.dart';

import 'cart/cart_controller.dart';
import 'models/public_product_model.dart';
import 'screens/about_page.dart';
import 'screens/categories_page.dart';
import 'screens/category_products_page.dart';
import 'screens/checkout_page.dart';
import 'screens/contact_page.dart';
import 'screens/product_detail_page.dart';
import 'screens/shipping_policy_page.dart';
import 'screens/store_home_page.dart';

final GoRouter appRouter = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const StoreHomePage(),
    ),
    GoRoute(
      path: '/product/:id',
      builder: (context, state) => ProductDetailPage(
        productId: state.pathParameters['id']!,
        // Already-loaded model from a tap in this session (ProductCard, hero
        // banner, related products) — skips the self-fetch below. Absent on a
        // fresh load (shared link, refresh, browser back/forward), in which
        // case ProductDetailPage fetches by id itself.
        preloadedProduct: state.extra as PublicProductModel?,
      ),
    ),
    GoRoute(
      path: '/category/:name',
      builder: (context, state) => CategoryProductsPage(
        category: state.pathParameters['name']!,
      ),
    ),
    GoRoute(
      path: '/offers',
      builder: (context, state) => const CategoryProductsPage(
        onlyOnSale: true,
        titleOverride: 'عروض خاصة',
      ),
    ),
    GoRoute(
      path: '/categories',
      builder: (context, state) => const CategoriesPage(),
    ),
    GoRoute(
      path: '/checkout',
      builder: (context, state) => CheckoutPage(
        // A CartLine passed via extra means "Buy Now" checkout for that one
        // item; absent (including after a page refresh) falls back to normal
        // cart-based checkout — see CheckoutPage's own doc on buyNowItem.
        buyNowItem: state.extra as CartLine?,
      ),
    ),
    GoRoute(
      path: '/about',
      builder: (context, state) => const AboutPage(),
    ),
    GoRoute(
      path: '/contact',
      builder: (context, state) => const ContactPage(),
    ),
    GoRoute(
      path: '/shipping-policy',
      builder: (context, state) => const ShippingPolicyPage(),
    ),
  ],
);
