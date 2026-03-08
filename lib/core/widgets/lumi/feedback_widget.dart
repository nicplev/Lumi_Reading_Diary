import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../../theme/lumi_spacing.dart';
import '../../theme/lumi_borders.dart';
import '../lumi/lumi_buttons.dart';
import '../../../services/firebase_service.dart';
import '../../../services/analytics_service.dart';

/// Feedback categories for beta users
enum FeedbackCategory { bug, featureRequest, general }

extension FeedbackCategoryLabel on FeedbackCategory {
  String get label {
    switch (this) {
      case FeedbackCategory.bug:
        return 'Bug Report';
      case FeedbackCategory.featureRequest:
        return 'Feature Request';
      case FeedbackCategory.general:
        return 'General Feedback';
    }
  }

  IconData get icon {
    switch (this) {
      case FeedbackCategory.bug:
        return Icons.bug_report_outlined;
      case FeedbackCategory.featureRequest:
        return Icons.lightbulb_outline;
      case FeedbackCategory.general:
        return Icons.chat_bubble_outline;
    }
  }
}

/// Shows a bottom sheet for submitting beta feedback.
/// Saves to Firestore `feedback` collection.
Future<void> showFeedbackSheet(BuildContext context, {required String userId, required String userRole}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _FeedbackSheet(userId: userId, userRole: userRole),
  );
}

class _FeedbackSheet extends StatefulWidget {
  final String userId;
  final String userRole;

  const _FeedbackSheet({required this.userId, required this.userRole});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  FeedbackCategory _category = FeedbackCategory.general;
  final _descriptionController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a description')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      await FirebaseService.instance.firestore.collection('feedback').add({
        'userId': widget.userId,
        'userRole': widget.userRole,
        'category': _category.name,
        'description': description,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'new',
      });

      AnalyticsService.instance.logFeedbackSubmitted(category: _category.name);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thank you for your feedback!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit feedback')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: LumiSpacing.m),

            Text('Send Feedback', style: LumiTextStyles.h2()),
            const SizedBox(height: LumiSpacing.xs),
            Text(
              'Help us improve Lumi for you and your family',
              style: LumiTextStyles.bodySmall(
                color: AppColors.charcoal.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: LumiSpacing.m),

            // Category selector
            Text('Category', style: LumiTextStyles.label()),
            const SizedBox(height: LumiSpacing.xs),
            Row(
              children: FeedbackCategory.values.map((cat) {
                final isSelected = _category == cat;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _category = cat),
                    child: Container(
                      margin: EdgeInsets.only(
                        right: cat != FeedbackCategory.general ? 8 : 0,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.rosePink.withValues(alpha: 0.1)
                            : AppColors.background,
                        borderRadius: LumiBorders.medium,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.rosePink
                              : AppColors.divider,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            cat.icon,
                            size: 20,
                            color: isSelected
                                ? AppColors.rosePink
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cat.label,
                            style: LumiTextStyles.caption(
                              color: isSelected
                                  ? AppColors.rosePink
                                  : AppColors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: LumiSpacing.m),

            // Description field
            Text('Description', style: LumiTextStyles.label()),
            const SizedBox(height: LumiSpacing.xs),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Tell us what happened or what you\'d like to see...',
                hintStyle: LumiTextStyles.bodySmall(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                  borderSide: BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: LumiBorders.medium,
                  borderSide: const BorderSide(color: AppColors.rosePink),
                ),
              ),
            ),
            const SizedBox(height: LumiSpacing.m),

            // Submit button
            LumiPrimaryButton(
              onPressed: _isSubmitting ? null : _submit,
              text: _isSubmitting ? 'Submitting...' : 'Submit Feedback',
              icon: Icons.send,
              isFullWidth: true,
            ),
            const SizedBox(height: LumiSpacing.s),
          ],
        ),
      ),
    );
  }
}
