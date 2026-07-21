import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import 'persistent_cached_image.dart';
import 'teacher_book_type_badge.dart';

enum TeacherBookCardAction {
  edit,
  swap,
  keepNextCycle,
  remove,
}

/// Lumi Design System - Teacher Book Assignment Card
///
/// Warm, flat bento row for one assigned book. Shared by the student-detail
/// page so populated book states match its first-read/next-read compartments.
class TeacherBookAssignmentCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Color> coverGradient;
  final String? coverImageUrl;
  final String bookType; // 'decodable' or 'library'
  final String status; // 'completed', 'in_progress', 'renewed', 'new'
  final ValueChanged<TeacherBookCardAction>? onActionSelected;
  final VoidCallback? onTap;

  const TeacherBookAssignmentCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverGradient,
    this.coverImageUrl,
    required this.bookType,
    required this.status,
    this.onActionSelected,
    this.onTap,
  });

  Widget _buildStatusBadge() {
    switch (status) {
      case 'completed':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: LumiTokens.tintGreen.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check,
                size: 12,
                color: LumiTokens.green,
              ),
              const SizedBox(width: 4),
              Text(
                'Done',
                style: LumiType.caption.copyWith(
                  color: LumiTokens.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      case 'in_progress':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: LumiTokens.tintBlue.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Text(
            'In progress',
            style: LumiType.caption.copyWith(
              color: LumiTokens.blue,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case 'renewed':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: LumiTokens.tintYellow.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.autorenew_rounded,
                  size: 12, color: LumiTokens.orange),
              const SizedBox(width: 4),
              Text(
                'Renewed',
                style: LumiType.caption.copyWith(
                  color: LumiTokens.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      default:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: LumiTokens.cream,
            borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            border: Border.all(color: LumiTokens.rule),
          ),
          child: Text(
            'New',
            style: LumiType.caption.copyWith(
              color: LumiTokens.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    }
  }

  Widget _buildCover() {
    final hasCover = coverImageUrl != null &&
        coverImageUrl!.isNotEmpty &&
        coverImageUrl!.startsWith('http');

    return ClipRRect(
      borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
      child: Container(
        width: 54,
        height: 74,
        decoration: BoxDecoration(
          color: coverGradient.isNotEmpty
              ? coverGradient.first
              : LumiTokens.tintBlue,
        ),
        child: hasCover
            ? PersistentCachedImage(
                imageUrl: coverImageUrl!,
                fit: BoxFit.cover,
                fallback: const Center(
                  child: Icon(
                    Icons.menu_book,
                    color: Colors.white54,
                    size: 20,
                  ),
                ),
              )
            : const Center(
                child: Icon(Icons.menu_book, color: Colors.white54, size: 20),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = onActionSelected != null;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
            border: Border.all(color: LumiTokens.rule),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: LumiType.body.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (canEdit)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: LumiTokens.muted.withValues(alpha: 0.55),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: LumiType.caption.copyWith(
                        fontSize: 14,
                        color: LumiTokens.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TeacherBookTypeBadge(type: bookType),
                        _buildStatusBadge(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
