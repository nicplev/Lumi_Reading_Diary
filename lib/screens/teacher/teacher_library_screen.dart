import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_filter_chip.dart';
import '../../core/widgets/lumi/teacher_tier_section.dart';
import '../../core/widgets/lumi/teacher_book_grid_item.dart';
import '../../data/providers/teacher_stub_data.dart';

/// Teacher Library Screen (Tab 3)
///
/// Book library browser with search, filter chips, and tiered book grid.
/// Per spec: search bar, horizontal filter chips, 3-column grid by tier.
/// Uses stub data — backend integration to come later.
class TeacherLibraryScreen extends StatefulWidget {
  const TeacherLibraryScreen({super.key});

  @override
  State<TeacherLibraryScreen> createState() => _TeacherLibraryScreenState();
}

class _TeacherLibraryScreenState extends State<TeacherLibraryScreen> {
  String _activeFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const List<String> _filters = ['All', 'Decodable', 'Library', 'Recently Added'];

  List<Map<String, dynamic>> get _filteredBooks {
    var books = TeacherStubData.getStubBooks();

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      books = books
          .where((b) => (b['title'] as String)
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Apply type filter
    switch (_activeFilter) {
      case 'Decodable':
        books = books.where((b) => b['type'] == 'decodable').toList();
        break;
      case 'Library':
        books = books.where((b) => b['type'] == 'library').toList();
        break;
      case 'Recently Added':
        // Stub: just show first 6 books
        books = books.take(6).toList();
        break;
    }

    return books;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = _filteredBooks;
    final decodableCount = TeacherStubData.getStubBooks()
        .where((b) => b['type'] == 'decodable')
        .length;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Book Library', style: TeacherTypography.h1),
                  const SizedBox(height: 4),
                  Text(
                    '$decodableCount Decodable Books Available',
                    style: TeacherTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: InputDecoration(
                  hintText: 'Search books...',
                  hintStyle: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: TeacherTypography.bodyMedium,
              ),
            ),
          ),

          // Filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 0, 16),
              child: SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _filters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  padding: const EdgeInsets.only(right: 20),
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    return TeacherFilterChip(
                      label: filter,
                      isActive: _activeFilter == filter,
                      onTap: () => setState(() => _activeFilter = filter),
                    );
                  },
                ),
              ),
            ),
          ),

          // Book content
          if (_activeFilter == 'All' || _activeFilter == 'Decodable')
            ..._buildTierSections(books)
          else
            _buildFlatGrid(books),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  List<Widget> _buildTierSections(List<Map<String, dynamic>> books) {
    final widgets = <Widget>[];

    for (final tier in decodableTiers) {
      final tierBooks = books
          .where((b) => b['tierLevel'] == tier.level && b['type'] == 'decodable')
          .toList();

      if (tierBooks.isEmpty) continue;

      widgets.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: TeacherTierSection(
              level: tier.level,
              name: tier.name,
              color: tier.color,
              bookCount: tierBooks.length,
              bookItems: tierBooks.map((book) {
                return TeacherBookGridItem(
                  title: book['title'] as String,
                  coverGradient: (book['coverGradient'] as List<Color>),
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Selected: ${book['title']}')),
                    );
                  },
                );
              }).toList(),
            ),
          ),
        ),
      );
    }

    // Library books section
    final libraryBooks = books.where((b) => b['type'] == 'library').toList();
    if (libraryBooks.isNotEmpty && _activeFilter == 'All') {
      widgets.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: AppColors.libraryGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Library Books',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.charcoal,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${libraryBooks.length} books)',
                      style: TeacherTypography.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                  children: libraryBooks.map((book) {
                    return TeacherBookGridItem(
                      title: book['title'] as String,
                      coverGradient: (book['coverGradient'] as List<Color>),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Selected: ${book['title']}')),
                        );
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildFlatGrid(List<Map<String, dynamic>> books) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final book = books[index];
            return TeacherBookGridItem(
              title: book['title'] as String,
              coverGradient: (book['coverGradient'] as List<Color>),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Selected: ${book['title']}')),
                );
              },
            );
          },
          childCount: books.length,
        ),
      ),
    );
  }
}
