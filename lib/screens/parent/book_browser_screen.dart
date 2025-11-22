import 'package:flutter/material.dart';
import '../../data/models/student_model.dart';
import '../../data/models/book_model.dart';
import '../../services/book_recommendation_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/theme/lumi_borders.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';

/// Screen for browsing and discovering books
/// Shows personalized recommendations and popular books
class BookBrowserScreen extends StatefulWidget {
  final StudentModel student;

  const BookBrowserScreen({
    super.key,
    required this.student,
  });

  @override
  State<BookBrowserScreen> createState() => _BookBrowserScreenState();
}

class _BookBrowserScreenState extends State<BookBrowserScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _bookService = BookRecommendationService();

  bool _isLoading = true;
  List<BookModel> _recommendations = [];
  List<BookModel> _currentlyReading = [];
  List<BookModel> _completed = [];
  List<BookModel> _popular = [];
  List<String> _genres = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text('Discover Books', style: LumiTextStyles.h3()),
        backgroundColor: AppColors.white,
        elevation: 0,
        actions: [
          LumiIconButton(
            icon: Icons.search,
            onPressed: _showSearch,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: AppColors.rosePink,
          unselectedLabelColor: AppColors.charcoal.withValues(alpha: 0.6),
          indicatorColor: AppColors.rosePink,
          tabs: const [
            Tab(text: 'For You'),
            Tab(text: 'Reading'),
            Tab(text: 'Completed'),
            Tab(text: 'Popular'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildRecommendationsTab(),
                _buildCurrentlyReadingTab(),
                _buildCompletedTab(),
                _buildPopularTab(),
              ],
            ),
    );
  }

  Widget _buildRecommendationsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(),
            LumiGap.m,
            if (_recommendations.isNotEmpty) ...[
              _buildSectionHeader(
                'Recommended for ${widget.student.firstName}',
                'Based on reading level and interests',
              ),
              LumiGap.s,
              _buildBookGrid(_recommendations),
              LumiGap.m,
            ],
            if (_genres.isNotEmpty) ...[
              _buildSectionHeader('Browse by Genre', 'Explore different categories'),
              LumiGap.s,
              _buildGenreChips(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentlyReadingTab() {
    if (_currentlyReading.isEmpty) {
      return _buildEmptyState(
        icon: Icons.menu_book,
        title: 'No books in progress',
        message: 'Start reading a book from recommendations!',
        actionLabel: 'Browse Books',
        onAction: () => _tabController.animateTo(0),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Currently Reading (${_currentlyReading.length})',
              'Keep up the great work!',
            ),
            LumiGap.s,
            _buildBookGrid(_currentlyReading),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedTab() {
    if (_completed.isEmpty) {
      return _buildEmptyState(
        icon: Icons.check_circle_outline,
        title: 'No completed books yet',
        message: 'Finish reading a book to see it here!',
        actionLabel: 'Start Reading',
        onAction: () => _tabController.animateTo(0),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Completed Books (${_completed.length})',
              'Great job finishing these books!',
            ),
            LumiGap.s,
            _buildBookGrid(_completed),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: LumiPadding.allS,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Popular at Your Level',
              widget.student.currentReadingLevel != null
                  ? 'Level ${widget.student.currentReadingLevel}'
                  : 'All levels',
            ),
            LumiGap.s,
            _buildBookGrid(_popular),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return LumiCard(
      isHighlighted: true,
      child: Row(
        children: [
          Icon(Icons.auto_stories, size: 48, color: AppColors.rosePink),
          LumiGap.horizontalS,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find Your Next Book!',
                  style: LumiTextStyles.h3(),
                ),
                LumiGap.xxs,
                Text(
                  'Discover books perfect for your reading level',
                  style: LumiTextStyles.bodySmall(
                    color: AppColors.charcoal.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: LumiTextStyles.h2(),
        ),
        LumiGap.xxs,
        Text(
          subtitle,
          style: LumiTextStyles.bodySmall(
            color: AppColors.charcoal.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _buildBookGrid(List<BookModel> books) {
    if (books.isEmpty) {
      return Center(
        child: Padding(
          padding: LumiPadding.allL,
          child: Text(
            'No books found',
            style: LumiTextStyles.body(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: LumiSpacing.listItemSpacing,
        mainAxisSpacing: LumiSpacing.listItemSpacing,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        return _buildBookCard(books[index]);
      },
    );
  }

  Widget _buildBookCard(BookModel book) {
    return LumiCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showBookDetails(book),
        borderRadius: LumiBorders.medium,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.skyBlue.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.only(
                    topLeft: LumiBorders.medium.topLeft,
                    topRight: LumiBorders.medium.topRight,
                  ),
                ),
                child: book.coverImageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.only(
                          topLeft: LumiBorders.medium.topLeft,
                          topRight: LumiBorders.medium.topRight,
                        ),
                        child: Image.network(
                          book.coverImageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildBookPlaceholder(book);
                          },
                        ),
                      )
                    : _buildBookPlaceholder(book),
              ),
            ),
            Padding(
              padding: LumiPadding.allXS,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: LumiTextStyles.label().copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null) ...[
                    LumiGap.xxs,
                    Text(
                      book.author!,
                      style: LumiTextStyles.caption(
                        color: AppColors.charcoal.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (book.averageRating != null) ...[
                    LumiGap.xxs,
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: AppColors.warmOrange,
                        ),
                        LumiGap.horizontalXXS,
                        Text(
                          book.averageRating!.toStringAsFixed(1),
                          style: LumiTextStyles.caption(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBookPlaceholder(BookModel book) {
    return Container(
      color: AppColors.rosePink.withValues(alpha: 0.1),
      child: Center(
        child: Padding(
          padding: LumiPadding.allS,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book,
                size: 48,
                color: AppColors.rosePink.withValues(alpha: 0.5),
              ),
              LumiGap.xs,
              Text(
                book.title,
                style: LumiTextStyles.bodySmall(
                  color: AppColors.rosePink,
                ).copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenreChips() {
    return Wrap(
      spacing: LumiSpacing.xs,
      runSpacing: LumiSpacing.xs,
      children: _genres.map((genre) {
        return ActionChip(
          label: Text(genre, style: LumiTextStyles.label()),
          onPressed: () => _browseGenre(genre),
          backgroundColor: AppColors.rosePink.withValues(alpha: 0.1),
          side: BorderSide(color: AppColors.rosePink.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(borderRadius: LumiBorders.medium),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: LumiPadding.allL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 64,
              color: AppColors.charcoal.withValues(alpha: 0.4),
            ),
            LumiGap.s,
            Text(
              title,
              style: LumiTextStyles.h2(
                color: AppColors.charcoal.withValues(alpha: 0.7),
              ),
            ),
            LumiGap.xs,
            Text(
              message,
              style: LumiTextStyles.body(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              LumiGap.m,
              LumiPrimaryButton(
                onPressed: onAction,
                text: actionLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _bookService.getRecommendationsForStudent(widget.student),
        _bookService.getCurrentlyReading(widget.student.id),
        _bookService.getCompletedBooks(widget.student.id),
        _bookService.getPopularBooksByLevel(
          widget.student.currentReadingLevel ?? '',
        ),
        _bookService.getAllGenres(),
      ]);

      setState(() {
        _recommendations = results[0] as List<BookModel>;
        _currentlyReading = results[1] as List<BookModel>;
        _completed = results[2] as List<BookModel>;
        _popular = results[3] as List<BookModel>;
        _genres = (results[4] as List<String>).take(10).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading books: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showBookDetails(BookModel book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: LumiPadding.allM,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.charcoal.withValues(alpha: 0.3),
                      borderRadius: LumiBorders.small,
                    ),
                  ),
                ),
                LumiGap.m,
                Text(
                  book.title,
                  style: LumiTextStyles.h2(),
                ),
                if (book.author != null) ...[
                  LumiGap.xs,
                  Text(
                    'by ${book.author}',
                    style: LumiTextStyles.h3(
                      color: AppColors.charcoal.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                LumiGap.s,
                Wrap(
                  spacing: LumiSpacing.xs,
                  runSpacing: LumiSpacing.xs,
                  children: [
                    if (book.readingLevel != null)
                      Chip(
                        label: Text(
                          'Level ${book.readingLevel}',
                          style: LumiTextStyles.label(),
                        ),
                        avatar: const Icon(Icons.school, size: 16),
                        backgroundColor: AppColors.skyBlue.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: LumiBorders.medium),
                      ),
                    if (book.averageRating != null)
                      Chip(
                        label: Text(
                          '${book.averageRating!.toStringAsFixed(1)} ⭐',
                          style: LumiTextStyles.label(),
                        ),
                        avatar: const Icon(Icons.star, size: 16),
                        backgroundColor: AppColors.skyBlue.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: LumiBorders.medium),
                      ),
                    if (book.pageCount != null)
                      Chip(
                        label: Text(
                          '${book.pageCount} pages',
                          style: LumiTextStyles.label(),
                        ),
                        avatar: const Icon(Icons.chrome_reader_mode, size: 16),
                        backgroundColor: AppColors.skyBlue.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: LumiBorders.medium),
                      ),
                  ],
                ),
                if (book.description != null) ...[
                  LumiGap.s,
                  Text(
                    'About this book',
                    style: LumiTextStyles.h3(),
                  ),
                  LumiGap.xs,
                  Text(
                    book.description!,
                    style: LumiTextStyles.body(),
                  ),
                ],
                if (book.genres.isNotEmpty) ...[
                  LumiGap.s,
                  Text(
                    'Genres',
                    style: LumiTextStyles.h3(),
                  ),
                  LumiGap.xs,
                  Wrap(
                    spacing: LumiSpacing.xs,
                    runSpacing: LumiSpacing.xs,
                    children: book.genres.map((genre) {
                      return Chip(
                        label: Text(genre, style: LumiTextStyles.label()),
                        backgroundColor: AppColors.skyBlue.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(borderRadius: LumiBorders.medium),
                      );
                    }).toList(),
                  ),
                ],
                LumiGap.m,
                SizedBox(
                  width: double.infinity,
                  child: LumiPrimaryButton(
                    onPressed: () => Navigator.of(context).pop('start'),
                    text: 'Start Reading',
                    icon: Icons.play_arrow,
                  ),
                ),
                LumiGap.s,
                SizedBox(
                  width: double.infinity,
                  child: LumiSecondaryButton(
                    onPressed: () => Navigator.of(context).pop('similar'),
                    text: 'Find Similar Books',
                    icon: Icons.more_horiz,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (action == 'start') {
      await _startReading(book);
    } else if (action == 'similar') {
      await _showSimilarBooks(book);
    }
  }

  Future<void> _startReading(BookModel book) async {
    try {
      await _bookService.recordBookStart(widget.student.id, book.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Started reading "${book.title}"!'),
          backgroundColor: AppColors.success,
        ),
      );

      _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting book: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _showSimilarBooks(BookModel book) async {
    // Show similar books (simplified - would navigate to a new screen in production)
    try {
      final similar = await _bookService.getSimilarBooks(book);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: LumiBorders.shapeLarge,
          title: Text(
            'Books similar to ${book.title}',
            style: LumiTextStyles.h3(),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: similar.length,
              itemBuilder: (context, index) {
                final similarBook = similar[index];
                return ListTile(
                  title: Text(
                    similarBook.title,
                    style: LumiTextStyles.body(),
                  ),
                  subtitle: Text(
                    similarBook.author ?? 'Unknown',
                    style: LumiTextStyles.bodySmall(
                      color: AppColors.charcoal.withValues(alpha: 0.6),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showBookDetails(similarBook);
                  },
                );
              },
            ),
          ),
          actions: [
            LumiTextButton(
              onPressed: () => Navigator.of(context).pop(),
              text: 'Close',
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading similar books: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showSearch() {
    // Implement search functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Search feature coming soon!'),
      ),
    );
  }

  Future<void> _browseGenre(String genre) async {
    try {
      final books = await _bookService.getBooksByGenre(
        genre,
        readingLevel: widget.student.currentReadingLevel,
      );

      if (!mounted) return;

      // Show genre books (simplified)
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: LumiBorders.shapeLarge,
          title: Text(
            '$genre Books',
            style: LumiTextStyles.h3(),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: books.isEmpty
                ? Text(
                    'No books found in this genre',
                    style: LumiTextStyles.body(
                      color: AppColors.charcoal.withValues(alpha: 0.6),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        title: Text(
                          book.title,
                          style: LumiTextStyles.body(),
                        ),
                        subtitle: Text(
                          book.author ?? 'Unknown',
                          style: LumiTextStyles.bodySmall(
                            color: AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showBookDetails(book);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            LumiTextButton(
              onPressed: () => Navigator.of(context).pop(),
              text: 'Close',
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading books: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}
