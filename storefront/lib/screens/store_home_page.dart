import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/cart_sheet.dart';
import 'checkout_page.dart';
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
        stream: FirebaseFirestore.instance.collection('products_public').snapshots(),
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
              .map((d) => PublicProductModel.fromMap(d.data() as Map<String, dynamic>))
              .toList();
          final filtered = _query.isEmpty
              ? all
              : all.where((p) => p.name.toLowerCase().contains(_query.toLowerCase())).toList();
          final featured = all.where((p) => p.isFeatured && p.isAvailable).toList();
          final hero = featured.isNotEmpty ? featured.first : null;
          final carousel = featured.length > 1 ? featured.sublist(1) : <PublicProductModel>[];

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
                                SizedBox(width: 150, child: _ProductCard(product: carousel[i])),
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
                            (context, i) => _ProductCard(product: filtered[i]),
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
      bottomSheet: const _CartBar(),
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          image: DecorationImage(image: NetworkImage(product.coverImage), fit: BoxFit.cover),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black.withValues(alpha: 0.65)],
              stops: const [0.4, 1],
            ),
          ),
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final PublicProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final isAvailable = product.isAvailable;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(product.coverImage, fit: BoxFit.cover),
                  if (!isAvailable)
                    Container(
                      color: Colors.black.withValues(alpha: 0.45),
                      alignment: Alignment.center,
                      child: const Text('غير متوفر حاليًا', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Text('${product.price.toStringAsFixed(0)} د.أ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.accent)),
                  const Spacer(),
                  ...product.variants.take(4).map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.border),
                          image: DecorationImage(image: NetworkImage(v.imageUrl), fit: BoxFit.cover),
                        ),
                      ),
                    ),
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

class _CartBar extends StatelessWidget {
  const _CartBar();
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CartLine>>(
      valueListenable: cartController,
      builder: (context, cart, _) {
        if (cart.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
          child: ResponsiveCenter(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${cartController.itemCount} قطعة', style: Theme.of(context).textTheme.bodySmall),
                      Text('${cartController.total.toStringAsFixed(0)} د.أ', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutPage())),
                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: Text('إتمام الطلب')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
