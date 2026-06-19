import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../core/widgets/lumi/lumi_buttons.dart';
import '../../../../core/widgets/lumi/lumi_input.dart';
import '../../../../data/models/allocation_model.dart';
import '../../../../data/models/reading_level_option.dart';
import 'allocation_form_common.dart';

/// "Reading Type" card: pick Free Choice / By Level / Specific Books, plus the
/// level-range or book-selection sub-form.
class AllocationReadingTypeCard extends StatelessWidget {
  const AllocationReadingTypeCard({
    super.key,
    required this.allocationType,
    required this.levelsEnabled,
    required this.readingLevelOptions,
    required this.levelRangeStart,
    required this.levelRangeEnd,
    required this.bookTitles,
    required this.libraryBookTitles,
    required this.bookTitleError,
    required this.levelError,
    required this.bookTitlesController,
    required this.onTypeChanged,
    required this.onStartLevelChanged,
    required this.onEndLevelChanged,
    required this.onBrowseLibrary,
    required this.onAddManualTitle,
    required this.onRemoveTitle,
    required this.onManualTextChanged,
  });

  final AllocationType allocationType;
  final bool levelsEnabled;
  final List<ReadingLevelOption> readingLevelOptions;
  final String? levelRangeStart;
  final String? levelRangeEnd;
  final List<String> bookTitles;
  final Set<String> libraryBookTitles;
  final String? bookTitleError;
  final String? levelError;
  final TextEditingController bookTitlesController;
  final ValueChanged<AllocationType> onTypeChanged;
  final ValueChanged<String?> onStartLevelChanged;
  final ValueChanged<String?> onEndLevelChanged;
  final VoidCallback onBrowseLibrary;
  final VoidCallback onAddManualTitle;
  final ValueChanged<String> onRemoveTitle;
  final VoidCallback onManualTextChanged;

  @override
  Widget build(BuildContext context) {
    return AllocationFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AllocationSectionHeader(step: 1, title: 'Reading type'),
          const SizedBox(height: 16),

          // Type chooser — descriptive option rows
          AllocationOptionList(
            cards: [
              AllocationOptionCard(
                icon: Icons.auto_stories_outlined,
                iconColor: LumiTokens.blue,
                title: 'Free choice',
                description: 'Students choose their own book.',
                isSelected: allocationType == AllocationType.freeChoice,
                onTap: () => onTypeChanged(AllocationType.freeChoice),
              ),
              if (levelsEnabled)
                AllocationOptionCard(
                  icon: Icons.bar_chart_rounded,
                  iconColor: LumiTokens.blue,
                  title: 'By level',
                  description: 'Match books to each reading level.',
                  isSelected: allocationType == AllocationType.byLevel,
                  onTap: () => onTypeChanged(AllocationType.byLevel),
                ),
              AllocationOptionCard(
                icon: Icons.menu_book_rounded,
                iconColor: LumiTokens.yellow,
                title: 'Specific books',
                description: 'Assign titles from your library.',
                isSelected: allocationType == AllocationType.byTitle,
                onTap: () => onTypeChanged(AllocationType.byTitle),
              ),
            ],
          ),

          // Level range fields
          if (allocationType == AllocationType.byLevel) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: LumiDropdown<String>(
                    label: 'Start Level',
                    hintText: 'Select level',
                    value: levelRangeStart,
                    items: readingLevelOptions.map((o) => o.value).toList(),
                    itemLabel: (v) {
                      final opt = readingLevelOptions
                          .where((o) => o.value == v)
                          .firstOrNull;
                      return opt?.displayLabel ?? v;
                    },
                    errorText: levelError,
                    onChanged: onStartLevelChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LumiDropdown<String?>(
                    label: 'End Level',
                    hintText: 'Optional',
                    value: levelRangeEnd,
                    items: [
                      null,
                      ...readingLevelOptions.map((o) => o.value),
                    ],
                    itemLabel: (v) {
                      if (v == null) return 'No end level';
                      final opt = readingLevelOptions
                          .where((o) => o.value == v)
                          .firstOrNull;
                      return opt?.displayLabel ?? v;
                    },
                    onChanged: onEndLevelChanged,
                  ),
                ),
              ],
            ),
          ],

          // Book selection fields
          if (allocationType == AllocationType.byTitle) ...[
            const SizedBox(height: 16),

            // Added books
            if (bookTitles.isNotEmpty) ...[
              ...bookTitles.map((title) {
                final hasLibraryData = libraryBookTitles.contains(title);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: LumiTokens.green.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                      border: Border.all(color: LumiTokens.rule),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasLibraryData
                              ? Icons.local_library
                              : Icons.menu_book,
                          color: LumiTokens.green,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: LumiType.body.copyWith(
                              color: LumiTokens.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => onRemoveTitle(title),
                          child: const Icon(Icons.close,
                              color: LumiTokens.muted, size: 18),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],

            // Error text
            if (bookTitleError != null) ...[
              Text(
                bookTitleError!,
                style: LumiType.caption.copyWith(color: LumiTokens.red),
              ),
              const SizedBox(height: 8),
            ],

            // Browse library button
            LumiSecondaryButton(
              onPressed: onBrowseLibrary,
              text: 'Browse School Library',
              icon: Icons.search,
              isFullWidth: true,
              color: LumiTokens.green,
            ),
            const SizedBox(height: 10),

            // Manual entry
            Row(
              children: [
                Expanded(
                  child: LumiInput(
                    controller: bookTitlesController,
                    hintText: 'Or type a title manually',
                    prefixIcon: const Icon(Icons.add, size: 20),
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => onManualTextChanged(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    onPressed: bookTitlesController.text.trim().isNotEmpty
                        ? onAddManualTitle
                        : null,
                    icon: Icon(
                      Icons.add_circle,
                      color: bookTitlesController.text.trim().isNotEmpty
                          ? LumiTokens.green
                          : LumiTokens.muted,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.qr_code_scanner_rounded,
                    size: 14, color: LumiTokens.muted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Books in hand? Use Scan on the Class screen to assign by '
                    'barcode.',
                    style: LumiType.caption,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
