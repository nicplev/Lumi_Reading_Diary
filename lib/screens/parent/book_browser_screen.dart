import 'package:flutter/material.dart';
import '../../data/models/student_model.dart';
import '../../data/models/book_model.dart';
import '../../services/book_recommendation_service.dart';
import '../../core/theme/app_colors.dart';

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
      appBar: AppBar(
        title: const Text('Discover Books'),
        backgroundColor: AppColors.primaryBlue,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearch,
            tooltip: 'Search Books',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 24),
            if (_recommendations.isNotEmpty) ...[
              _buildSectionHeader(
                'Recommended for ${widget.student.firstName}',
                'Based on reading level and interests',
              ),
              const SizedBox(height: 12),
              _buildBookGrid(_recommendations),
              const SizedBox(height: 24),
            ],
            if (_genres.isNotEmpty) ...[
              _buildSectionHeader('Browse by Genre', 'Explore different categories'),
              const SizedBox(height: 12),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Currently Reading (${_currentlyReading.length})',
              'Keep up the great work!',
            ),
            const SizedBox(height: 12),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Completed Books (${_completed.length})',
              'Great job finishing these books!',
            ),
            const SizedBox(height: 12),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              'Popular at Your Level',
              widget.student.currentReadingLevel != null
                  ? 'Level ${widget.student.currentReadingLevel}'
                  : 'All levels',
            ),
            const SizedBox(height: 12),
            _buildBookGrid(_popular),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 2,
      color: AppColors.primaryBlue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.auto_stories, size: 48, color: AppColors.primaryBlue),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Find Your Next Book!',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Discover books perfect for your reading level',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
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

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  Widget _buildBookGrid(List<BookModel> books) {
    if (books.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No books found'),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        return _buildBookCard(books[index]);
      },
    );
  }

  Widget _buildBookCard(BookModel book) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showBookDetails(book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey[200],
                child: book.coverImageUrl != null
                    ? Image.network(
                        book.coverImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildBookPlaceholder(book);
                        },
                      )
                    : _buildBookPlaceholder(book),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      book.author!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (book.averageRating != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          size: 14,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          book.averageRating!.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11),
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
      color: AppColors.primaryBlue.withOpacity(0.1),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book,
                size: 48,
                color: AppColors.primaryBlue.withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryBlue,
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
      spacing: 8,
      runSpacing: 8,
      children: _genres.map((genre) {
        return ActionChip(
          label: Text(genre),
          onPressed: () => _browseGenre(genre),
          backgroundColor: AppColors.primaryBlue.withOpacity(0.1),
          side: BorderSide(color: AppColors.primaryBlue.withOpacity(0.3)),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.grey[700],
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel),
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
          backgroundColor: Colors.red,
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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  book.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (book.author != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'by ${book.author}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (book.readingLevel != null)
                      Chip(
                        label: Text('Level ${book.readingLevel}'),
                        avatar: const Icon(Icons.school, size: 16),
                      ),
                    if (book.averageRating != null)
                      Chip(
                        label: Text('${book.averageRating!.toStringAsFixed(1)} ⭐'),
                        avatar: const Icon(Icons.star, size: 16),
                      ),
                    if (book.pageCount != null)
                      Chip(
                        label: Text('${book.pageCount} pages'),
                        avatar: const Icon(Icons.chrome_reader_mode, size: 16),
                      ),
                  ],
                ),
                if (book.description != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    'About this book',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.description!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (book.genres.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Genres',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: book.genres.map((genre) {
                      return Chip(label: Text(genre));
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop('start'),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Reading'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop('similar'),
                    icon: const Icon(Icons.more_horiz),
                    label: const Text('Find Similar Books'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
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
          backgroundColor: Colors.green,
        ),
      );

      _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error starting book: $e'),
          backgroundColor: Colors.red,
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
          title: Text('Books similar to ${book.title}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: similar.length,
              itemBuilder: (context, index) {
                final similarBook = similar[index];
                return ListTile(
                  title: Text(similarBook.title),
                  subtitle: Text(similarBook.author ?? 'Unknown'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _showBookDetails(similarBook);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading similar books: $e'),
          backgroundColor: Colors.red,
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
          title: Text('$genre Books'),
          content: SizedBox(
            width: double.maxFinite,
            child: books.isEmpty
                ? const Text('No books found in this genre')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        title: Text(book.title),
                        subtitle: Text(book.author ?? 'Unknown'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showBookDetails(book);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading books: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
