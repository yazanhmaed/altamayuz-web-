import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/cart_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/cart_sheet.dart';
import 'category_products_page.dart';
import 'product_detail_page.dart';

class StoreHomePage extends StatefulWidget {
  const StoreHomePage({super.key});
  @override
  State<StoreHomePage> createState() => _StoreHomePageState();
}

class _StoreHomePageState extends State<StoreHomePage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('المتجر', style: Theme.of(context).textTheme.headlineSmall),
        actions: [
          ValueListenableBuilder<List<CartLine>>(
            valueListenable: cartController,
            builder: (context, cart, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const CartSheet(),
                  ),
                ),
                if (cart.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                      child: Text('${cartController.itemCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return ResponsiveCenter(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.68,
                ),
                itemCount: 6,
                itemBuilder: (_, __) => const ProductCardSkeleton(),
              ),
            );
          }

          final all = snapshot.data!.docs
              .map((d) => PublicProductModel.fromProductDoc(
                    d.id,
                    d.data() as Map<String, dynamic>,
                  ))
              .whereType<PublicProductModel>()
              .toList();
          final filtered = _query.isEmpty
              ? all
              : all.where((p) => p.name.toLowerCase().contains(_query.toLowerCase())).toList();
          final featured = all.where((p) => p.isFeatured && p.isAvailable).toList();
          final hero = featured.isNotEmpty ? featured.first : null;
          final carousel = featured.length > 1 ? featured.sublist(1) : <PublicProductModel>[];
          final categories = {for (final p in all) p.category}.toList()..sort();

          if (all.isEmpty) return const Center(child: Text('لا توجد منتجات متاحة حاليًا'));

          return ResponsiveCenter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = Responsive.gridColumns(constraints.maxWidth);
                return CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'ابحث عن منتج...',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: AppColors.border),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_query.isEmpty)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: categories.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) => ActionChip(
                              label: Text(categories[i]),
                              backgroundColor: AppColors.surface,
                              side: const BorderSide(color: AppColors.border),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CategoryProductsPage(category: categories[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (hero != null && _query.isEmpty)
                      SliverToBoxAdapter(child: _HeroBanner(product: hero)),
                    if (carousel.isNotEmpty && _query.isEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Text('الأكثر تميزًا', style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 220,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: carousel.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (context, i) =>
                                SizedBox(width: 150, child: ProductCard(product: carousel[i])),
                          ),
                        ),
                      ),
                    ],
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Text(
                          _query.isEmpty ? 'كل المنتجات' : 'نتائج البحث',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (filtered.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('ما لقينا نتائج مطابقة')),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 0.68,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => ProductCard(product: filtered[i]),
                            childCount: filtered.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
      bottomSheet: const CartBar(),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final PublicProductModel product;
  const _HeroBanner({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 320,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: AppColors.border,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            StoreImage(url: product.coverImage),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
                  stops: const [0.4, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(product.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${product.price.toStringAsFixed(0)} د.أ', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: const Text('تسوّق الآن', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
