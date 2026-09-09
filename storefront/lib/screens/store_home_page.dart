import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../cart/cart_controller.dart';
import '../models/public_product_model.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';
import '../widgets/cart_discount_banner.dart';
import '../widgets/category_card.dart';
import '../widgets/product_card.dart';
import '../widgets/store_footer.dart';
import '../widgets/ui_helpers.dart';
import '../widgets/cart_sheet.dart';
import '../widgets/whatsapp_fab.dart';
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

  // ---- "كل المنتجات" grid: cursor pagination (independent of the bounded
  // catalog-snapshot stream that powers every other section). One-time get()
  // per page — never a second .snapshots() listener. Only active while the
  // search field is empty; a search query suspends it.
  static const int _pageSize = 20;
  final _scrollCtrl = ScrollController();
  final List<PublicProductModel> _gridItems = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadNextPage(); // first page
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Pagination is suspended during search (grid then shows client-side
    // filtered results from the bounded snapshot, already all in memory).
    if (_query.isNotEmpty || !_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadNextPage();
    }
  }

  Future<void> _loadNextPage() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() {
      _isLoadingMore = true;
      _loadError = null;
    });
    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('products')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(_pageSize);
      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }
      final snap = await query.get();
      final page = snap.docs
          .map((d) => PublicProductModel.fromProductDoc(d.id, d.data()))
          .whereType<PublicProductModel>()
          .toList();
      if (!mounted) return;
      setState(() {
        _gridItems.addAll(page);
        if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
        // Decide from the raw doc count, not `page` — a page of non-sellable
        // docs (all filtered out) still means there may be more.
        if (snap.docs.length < _pageSize) _hasMore = false;
      });
      // If this page didn't fill the viewport (tall window, few columns, or a
      // page that filtered down to nothing), no scroll event will fire — so
      // re-check the threshold after layout and pull the next page if needed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScroll();
      });
    } catch (e, stack) {
      // e.g. [cloud_firestore/failed-precondition] before the composite index
      // finishes building, or any transient network error.
      debugPrint('store_home_page: pagination fetch failed: $e\n$stack');
      if (mounted) {
        setState(() => _loadError = 'تعذر تحميل المزيد من المنتجات');
      }
    } finally {
      // The actual "spins forever" fix: the loading flag is cleared on every
      // path — success, failure, or early return.
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Home-only, same boundary as StoreFooter. Flutter docks the FAB above
      // Scaffold.bottomSheet (the CartBar), so it won't collide with it.
      floatingActionButton: const WhatsAppFab(),
      appBar: AppBar(
        title: Text('التميز للجلود الطبيعية المميزة',
            style: Theme.of(context).textTheme.headlineSmall),
        actions: [
          ValueListenableBuilder<List<CartLine>>(
            valueListenable: cartController,
            builder: (context, cart, _) => Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  onPressed: () => CartSheet.show(context),
                ),
                if (cart.isNotEmpty)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                          color: AppColors.accent, shape: BoxShape.circle),
                      child: Text('${cartController.itemCount}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Firestore reads active on this screen: this one products stream, plus
      // CartDiscountBanner's single one-time settings/cartDiscountTiers get().
      // Everything below — search filter, featured/hero/carousel, on-sale
      // offers, category counts/covers — is derived client-side from this one
      // `all` list, not separate queries.
      //
      // PERF NOTE (not worth fixing at current catalog size): CategoryProducts
      // Page, CategoriesPage and ProductDetailPage's "related products" each
      // open their own identical `products where isActive == true` stream on
      // navigation instead of reusing this already-loaded list — a redundant
      // full re-read. Fine for a small shop; revisit (shared repository /
      // cache) before the catalog grows large.
      body: StreamBuilder<QuerySnapshot>(
        // Bounded "catalog snapshot": powers hero / offers / featured /
        // category cards, and search results. `.limit(300)` is a safety cap
        // against unbounded growth, not a pagination mechanism — the "كل
        // المنتجات" grid has its own cursor pagination (_loadNextPage) for
        // the section whose length actually grows unbounded.
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('isActive', isEqualTo: true)
            .limit(300)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return ResponsiveCenter(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.68,
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
          final searching = _query.isNotEmpty;
          // Search: client-side filter over the bounded snapshot (unchanged).
          // Default browsing: the cursor-paginated list built by _loadNextPage.
          final gridProducts = searching
              ? all
                  .where((p) =>
                      p.name.toLowerCase().contains(_query.toLowerCase()))
                  .toList()
              : _gridItems;
          final featured =
              all.where((p) => p.isFeatured && p.isAvailable).toList();
          final hero = featured.isNotEmpty ? featured.first : null;
          final carousel = featured.length > 1
              ? featured.sublist(1)
              : <PublicProductModel>[];
          final offers = all.where((p) => p.isOnSale && p.isAvailable).toList();
          // One entry per category, with a product count and the first
          // product's image (used as the category card cover).
          final categoryCounts = <String, int>{};
          final categoryImage = <String, String>{};
          for (final p in all) {
            categoryCounts[p.category] = (categoryCounts[p.category] ?? 0) + 1;
            categoryImage.putIfAbsent(p.category, () => p.coverImage);
          }
          final categories = categoryCounts.keys.toList()..sort();

          if (all.isEmpty) {
            return const Center(child: Text('لا توجد منتجات متاحة حاليًا'));
          }

          return ResponsiveCenter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = Responsive.gridColumns(constraints.maxWidth);
                return CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    // Cart-wide quantity-discount promo. Self-hiding: renders
                    // nothing when no tiers are configured (no gap, no flicker).
                    const SliverToBoxAdapter(child: CartDiscountBanner()),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'ابحث عن منتج...',
                            hintStyle: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withOpacity(0.7),
                              fontSize: 14,
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            // زر الإلغاء/المسح يظهر فقط عند كتابة نص
                            suffixIcon: _query.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded,
                                        size: 20),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: AppColors.border.withOpacity(0.6),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (hero != null && _query.isEmpty)
                      SliverToBoxAdapter(child: _HeroBanner(product: hero)),
                    if (offers.isNotEmpty && _query.isEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                              16, 24, 8, 12),
                          child: Row(
                            children: [
                              Text('عروض خاصة',
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const CategoryProductsPage(
                                      onlyOnSale: true,
                                      titleOverride: 'عروض خاصة',
                                    ),
                                  ),
                                ),
                                child: const Text('عرض الكل'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 220,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: offers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) => SizedBox(
                                width: 150,
                                child: ProductCard(product: offers[i])),
                          ),
                        ),
                      ),
                    ],
                    if (carousel.isNotEmpty && _query.isEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                          child: Text('الأكثر تميزًا',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 220,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: carousel.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (context, i) => SizedBox(
                                width: 150,
                                child: ProductCard(product: carousel[i])),
                          ),
                        ),
                      ),
                    ],
                    // Category cards, just above the full product grid. Capped
                    // at 3 rows with a "show all" toggle so the list never
                    // dominates the page.
                    if (_query.isEmpty && categories.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                          child: _CategoryCardsSection(
                            categories: categories,
                            counts: categoryCounts,
                            images: categoryImage,
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                        child: Text(
                          _query.isEmpty ? 'كل المنتجات' : 'نتائج البحث',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (searching && gridProducts.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('ما لقينا نتائج مطابقة')),
                        ),
                      )
                    else if (!searching &&
                        gridProducts.isEmpty &&
                        !_isLoadingMore &&
                        _loadError == null)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                              child: Text('لا توجد منتجات متاحة حاليًا')),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.68,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) =>
                                ProductCard(product: gridProducts[i]),
                            childCount: gridProducts.length,
                          ),
                        ),
                      ),
                    // Trailing state below the grid: a failed fetch shows the
                    // error + retry (never just silently stops); otherwise the
                    // next-page spinner while a fetch is in flight; nothing once
                    // _hasMore is false.
                    if (_loadError != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 24),
                          child: Column(
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() => _loadError = null);
                                  _loadNextPage();
                                },
                                icon: const Icon(Icons.refresh, size: 18),
                                label: const Text('إعادة المحاولة'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_isLoadingMore)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    const SliverToBoxAdapter(child: StoreFooter()),
                  ],
                );
              },
            ),
          );
        },
      ),
      // bottomSheet: const CartBar(),
    );
  }
}

/// Home-screen category browser: a grid of [CategoryCard]s capped at 3 rows.
/// If the categories overflow that, a toggle reveals the rest — every category
/// stays reachable, nothing is dropped.
class _CategoryCardsSection extends StatefulWidget {
  final List<String> categories;
  final Map<String, int> counts;
  final Map<String, String> images;

  const _CategoryCardsSection({
    required this.categories,
    required this.counts,
    required this.images,
  });

  @override
  State<_CategoryCardsSection> createState() => _CategoryCardsSectionState();
}

class _CategoryCardsSectionState extends State<_CategoryCardsSection> {
  static const double _spacing = 10;
  static const double _tileAspect = 1.1; // width / height
  static const int _collapsedRows = 3;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تسوّق حسب الصنف',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 130).floor().clamp(2, 6);
            final tileWidth =
                (constraints.maxWidth - _spacing * (columns - 1)) / columns;
            final tileHeight = tileWidth / _tileAspect;
            final totalRows = (widget.categories.length / columns).ceil();
            final overflows = totalRows > _collapsedRows;
            final collapsedHeight =
                tileHeight * _collapsedRows + _spacing * (_collapsedRows - 1);

            final grid = GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: _spacing,
                crossAxisSpacing: _spacing,
                childAspectRatio: _tileAspect,
              ),
              itemCount: widget.categories.length,
              itemBuilder: (context, i) {
                final name = widget.categories[i];
                return CategoryCard(
                  name: name,
                  count: widget.counts[name] ?? 0,
                  coverImage: widget.images[name] ?? '',
                );
              },
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: (overflows && !_expanded)
                      ? SizedBox(
                          height: collapsedHeight,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: grid,
                            ),
                          ),
                        )
                      : grid,
                ),
                if (overflows)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      label: Text(_expanded ? 'عرض أقل' : 'عرض كل الأصناف'),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  final PublicProductModel product;
  const _HeroBanner({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => ProductDetailPage(product: product))),
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
            // Hero is the largest, most prominent image on the page (full
            // width, 320 tall) — kept at a generous cache size so it stays
            // crisp, still below the ~1600px source.
            StoreImage(url: product.coverImage, cacheWidth: 1200),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65)
                  ],
                  stops: const [0.4, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  PriceDisplay(
                    product: product,
                    fontSize: 16,
                    baseColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('تسوّق الآن',
                        style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700)),
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
