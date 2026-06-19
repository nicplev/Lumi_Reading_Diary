import 'package:flutter/material.dart';
import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';

/// Lumi Design System - Teacher Settings Section
///
/// Grouped settings: a muted uppercase label above a paper card of rows.
class TeacherSettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const TeacherSettingsSection({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: LumiType.sectionLabel,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: LumiTokens.paper,
            borderRadius: BorderRadius.circular(LumiTokens.radiusXL),
            border: Border.all(color: LumiTokens.rule),
            boxShadow: LumiTokens.shadowCard,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                items[i],
                if (i < items.length - 1)
                  const Divider(
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                    color: LumiTokens.rule,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
