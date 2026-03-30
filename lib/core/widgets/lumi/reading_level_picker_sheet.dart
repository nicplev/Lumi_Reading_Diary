import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/teacher_constants.dart';
import '../../../data/models/reading_level_option.dart';

class ReadingLevelPickerResult {
  const ReadingLevelPickerResult({
    required this.levelValue,
    required this.reason,
  });

  final String? levelValue;
  final String? reason;
}

class ReadingLevelPickerSheet extends StatefulWidget {
  const ReadingLevelPickerSheet({
    super.key,
    required this.studentName,
    required this.levelSystemLabel,
    required this.options,
    required this.currentLevelValue,
    this.currentDisplayLabel,
    this.rawStoredLevel,
  });

  final String studentName;
  final String levelSystemLabel;
  final List<ReadingLevelOption> options;
  final String? currentLevelValue;
  final String? currentDisplayLabel;
  final String? rawStoredLevel;

  static Future<ReadingLevelPickerResult?> show(
    BuildContext context, {
    required String studentName,
    required String levelSystemLabel,
    required List<ReadingLevelOption> options,
    required String? currentLevelValue,
    String? currentDisplayLabel,
    String? rawStoredLevel,
  }) {
    return showModalBottomSheet<ReadingLevelPickerResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReadingLevelPickerSheet(
        studentName: studentName,
        levelSystemLabel: levelSystemLabel,
        options: options,
        currentLevelValue: currentLevelValue,
        currentDisplayLabel: currentDisplayLabel,
        rawStoredLevel: rawStoredLevel,
      ),
    );
  }

  @override
  State<ReadingLevelPickerSheet> createState() =>
      _ReadingLevelPickerSheetState();
}

class _ReadingLevelPickerSheetState extends State<ReadingLevelPickerSheet> {
  late String? _selectedValue;
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _selectedValue = widget.currentLevelValue;
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    return Container(
      height: MediaQuery.of(context).size.height * 0.86,
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.teacherBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Update Reading Level', style: TeacherTypography.h3),
          const SizedBox(height: 6),
          Text(
            widget.studentName,
            style: TeacherTypography.h2,
          ),
          const SizedBox(height: 4),
          Text(
            widget.levelSystemLabel,
            style: TeacherTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (widget.currentDisplayLabel != null) ...[
            const SizedBox(height: 16),
            _InfoCard(
              icon: Icons.flag_outlined,
              message: 'Current level: ${widget.currentDisplayLabel}',
            ),
          ],
          if (_hasLegacyLevelWarning) ...[
            const SizedBox(height: 12),
            _WarningCard(
              message:
                  'Stored level "${widget.rawStoredLevel}" does not match the current school level system. Choose a new level to fix it.',
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _moveToPrevious,
                  icon: const Icon(Icons.keyboard_arrow_down),
                  label: const Text('Move Down'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _moveToNext,
                  icon: const Icon(Icons.keyboard_arrow_up),
                  label: const Text('Move Up'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Select level',
              style: TeacherTypography.bodyLarge
                  .copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.teacherBackground,
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: widget.options.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = widget.options[index];
                  final isSelected = option.value == _selectedValue;

                  final colorHex = option.colorHex;
                  final swatchColor = colorHex != null
                      ? _parseHexColor(colorHex)
                      : null;

                  return ListTile(
                    onTap: () => setState(() => _selectedValue = option.value),
                    selected: isSelected,
                    selectedTileColor:
                        AppColors.teacherPrimaryLight.withValues(alpha: 0.30),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: swatchColor != null
                        ? Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: swatchColor,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
                    title: Text(
                      option.displayLabel,
                      style: TeacherTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.teacherPrimary
                            : AppColors.charcoal,
                      ),
                    ),
                    subtitle: Text(
                      option.shortLabel == option.displayLabel
                          ? 'Canonical value: ${option.value}'
                          : option.shortLabel,
                      style: TeacherTypography.bodySmall,
                    ),
                    trailing: isSelected
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.teacherPrimary,
                          )
                        : const Icon(
                            Icons.circle_outlined,
                            color: AppColors.textSecondary,
                          ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reasonController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'Add context for the level change',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      ReadingLevelPickerResult(
                        levelValue: '',
                        reason: _reasonController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Clear level'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _canSave
                      ? () {
                          Navigator.of(context).pop(
                            ReadingLevelPickerResult(
                              levelValue: _selectedValue,
                              reason: _reasonController.text.trim(),
                            ),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.teacherPrimary,
                    foregroundColor: AppColors.white,
                  ),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _hasLegacyLevelWarning {
    final raw = widget.rawStoredLevel?.trim();
    if (raw == null || raw.isEmpty) return false;
    return widget.currentLevelValue == null;
  }

  bool get _canSave {
    if (_hasLegacyLevelWarning) {
      return _selectedValue != null;
    }
    return _selectedValue != widget.currentLevelValue;
  }

  void _moveToPrevious() {
    final currentIndex = _selectedIndex;
    if (currentIndex == null || currentIndex <= 0) return;
    setState(() => _selectedValue = widget.options[currentIndex - 1].value);
  }

  void _moveToNext() {
    final currentIndex = _selectedIndex;
    if (currentIndex == null || currentIndex >= widget.options.length - 1) {
      return;
    }
    setState(() => _selectedValue = widget.options[currentIndex + 1].value);
  }

  static Color? _parseHexColor(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse('FF$cleaned', radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  int? get _selectedIndex {
    for (int i = 0; i < widget.options.length; i++) {
      if (widget.options[i].value == _selectedValue) {
        return i;
      }
    }
    return null;
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.teacherSurfaceTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.teacherPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TeacherTypography.bodySmall.copyWith(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warmOrange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warmOrange.withValues(alpha: 0.20),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: AppColors.warmOrange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TeacherTypography.bodySmall.copyWith(
                color: AppColors.charcoal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
