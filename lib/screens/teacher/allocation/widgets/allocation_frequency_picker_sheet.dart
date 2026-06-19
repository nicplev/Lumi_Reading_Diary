import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../data/models/allocation_model.dart';
import 'allocation_form_common.dart';

/// Bottom sheet for choosing the allocation cadence (daily/weekly/etc).
class AllocationFrequencyPickerSheet extends StatelessWidget {
  const AllocationFrequencyPickerSheet({
    super.key,
    required this.currentCadence,
    required this.getCadenceLabel,
  });

  final AllocationCadence currentCadence;
  final String Function(AllocationCadence) getCadenceLabel;

  static Future<AllocationCadence?> show(
    BuildContext context, {
    required AllocationCadence currentCadence,
    required String Function(AllocationCadence) getCadenceLabel,
  }) {
    return showModalBottomSheet<AllocationCadence>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AllocationFrequencyPickerSheet(
        currentCadence: currentCadence,
        getCadenceLabel: getCadenceLabel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: LumiTokens.paper,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(LumiTokens.radiusXL)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(child: AllocationSheetGrabber()),
          const SizedBox(height: 18),
          Text('Frequency', style: LumiType.subhead),
          const SizedBox(height: 4),
          ...AllocationCadence.values.map((cadence) {
            final isSelected = cadence == currentCadence;
            return InkWell(
              onTap: () => Navigator.of(context).pop(cadence),
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        getCadenceLabel(cadence),
                        style: LumiType.body.copyWith(
                          color:
                              isSelected ? LumiTokens.green : LumiTokens.ink,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check,
                          size: 18, color: LumiTokens.green),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
