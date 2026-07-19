import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Plain info/error card shared by the student-detail sections.
class SectionInfoCard extends StatelessWidget {
  final String message;
  final bool isError;

  const SectionInfoCard(this.message, {super.key, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Text(
        message,
        style: LumiType.body.copyWith(
          color: isError ? AppColors.error : LumiTokens.muted,
        ),
      ),
    );
  }
}
