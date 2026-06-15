import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/teacher_constants.dart';
import '../../../core/widgets/lumi/lumi_input.dart';
import '../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../data/models/book_model.dart';
import '../../../services/school_library_service.dart';

/// Bottom sheet that lets teachers browse the school library and select
/// multiple books for an allocation. Stays open until the teacher taps "Done".
class LibraryPickerSheet extends StatefulWidget {
  const LibraryPickerSheet({
    super.key,
    required this.schoolId,
    required this.alreadyAdded,
    required this.onBooksSelected,
  });

  final String schoolId;
  final List<String> alreadyAdded;
  final ValueChanged<List<BookModel>> onBooksSelected;

  @override
  State<LibraryPickerSheet> createState() => _LibraryPickerSheetState();
}

class _LibraryPickerSheetState extends State<LibraryPickerSheet> {
  final _searchController = TextEditingController();
  final _libraryService = SchoolLibraryService();
  String _query = '';
  final List<BookModel> _sessionSelected = [];

  final List<BookModel> _books = [];
  bool _loading = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _loadAllBooks();
  }

  // SchoolLibraryService paginates (50/page) since the legacy /books stream was
  // dropped. The picker needs the whole list so search covers every book, so
  // page through to the end once when the sheet opens.
  Future<void> _loadAllBooks() async {
    final schoolId = widget.schoolId.trim();
    if (schoolId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      String? cursor;
      var hasMore = true;
      while (hasMore) {
        final page = await _libraryService.fetchBooksPage(
          schoolId,
          startAfterDocId: cursor,
        );
        _books.addAll(page.books);
        cursor = page.lastDocId ?? cursor;
        hasMore = page.hasMore;
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleBook(BookModel book) {
    setState(() {
      final idx = _sessionSelected.indexWhere((b) => b.title == book.title);
      if (idx >= 0) {
        _sessionSelected.removeAt(idx);
      } else if (!widget.alreadyAdded.contains(book.title)) {
        _sessionSelected.add(book);
      }
    });
  }

  void _done() {
    widget.onBooksSelected(_sessionSelected);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(TeacherDimensions.radiusXL)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Browse School Library', style: TeacherTypography.h2),
                    const SizedBox(height: 10),
                    LumiSearchInput(
                      controller: _searchController,
                      hintText: 'Search by title, author or ISBN...',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (_loading) {
                      return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.teacherPrimary),
                      );
                    }
                    if (_loadError != null && _books.isEmpty) {
                      return Center(
                        child: Text(
                          'Could not load the library. Please try again.',
                          style: TeacherTypography.bodyMedium
                              .copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final books = SchoolLibraryService.applyFilter(
                      books: _books,
                      filter: 'All',
                      searchQuery: _query,
                    );
                    if (books.isEmpty) {
                      return Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No books in library yet.\nScan ISBNs to add books.'
                              : 'No books match "$_query".',
                          style: TeacherTypography.bodyMedium
                              .copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      itemCount: books.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final book = books[i];
                        final wasAlreadyAdded =
                            widget.alreadyAdded.contains(book.title);
                        final isSessionSelected =
                            _sessionSelected.any((b) => b.title == book.title);
                        final isSelected = wasAlreadyAdded || isSessionSelected;

                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 4),
                          onTap: wasAlreadyAdded ? null : () => _toggleBook(book),
                          leading: SizedBox(
                            width: 36,
                            height: 50,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: book.coverImageUrl?.startsWith('http') ==
                                      true
                                  ? Image.network(
                                      book.coverImageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _bookIcon(book),
                                    )
                                  : _bookIcon(book),
                            ),
                          ),
                          title: Text(
                            book.title,
                            style: TeacherTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: book.author?.isNotEmpty == true
                              ? Text(
                                  book.author!,
                                  style: TeacherTypography.caption
                                      .copyWith(color: AppColors.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: wasAlreadyAdded
                                      ? AppColors.textSecondary
                                      : AppColors.teacherPrimary,
                                  size: 22,
                                )
                              : Icon(
                                  Icons.add_circle_outline,
                                  color: AppColors.teacherPrimary,
                                  size: 22,
                                ),
                        );
                      },
                    );
                  },
                ),
              ),
              // Done button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  border: Border(
                    top: BorderSide(color: AppColors.teacherBorder),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: LumiPrimaryButton(
                    onPressed: _done,
                    text: _sessionSelected.isEmpty
                        ? 'Done'
                        : 'Done (${_sessionSelected.length} selected)',
                    isFullWidth: true,
                    color: AppColors.teacherPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bookIcon(BookModel book) {
    final color = SchoolLibraryService.isDecodable(book)
        ? Color(SchoolLibraryService.stageColor(book.readingLevel ?? ''))
        : AppColors.libraryGreen;
    return Container(
      color: color.withValues(alpha: 0.15),
      child: Icon(Icons.menu_book, color: color, size: 18),
    );
  }
}
