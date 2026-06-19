import 'package:flutter/material.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import 'allocation_form_common.dart';

/// Bottom sheet wrapping a [CalendarDatePicker] themed to the green accent.
class AllocationDatePickerSheet extends StatefulWidget {
  const AllocationDatePickerSheet({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  static Future<DateTime?> show(
    BuildContext context, {
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    final clamped = initialDate.isBefore(firstDate) ? firstDate : initialDate;
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AllocationDatePickerSheet(
        initialDate: clamped,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    );
  }

  @override
  State<AllocationDatePickerSheet> createState() =>
      _AllocationDatePickerSheetState();
}

class _AllocationDatePickerSheetState extends State<AllocationDatePickerSheet> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
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
        children: [
          const Center(child: AllocationSheetGrabber()),
          const SizedBox(height: 18),
          Text('Select Date', style: LumiType.subhead),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: LumiTokens.green,
                    onPrimary: LumiTokens.paper,
                    surface: LumiTokens.paper,
                  ),
            ),
            child: CalendarDatePicker(
              initialDate: _selectedDate,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              onDateChanged: (date) {
                setState(() => _selectedDate = date);
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text(
                    'Cancel',
                    style: LumiType.button.copyWith(color: LumiTokens.muted),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selectedDate),
                  style: FilledButton.styleFrom(
                    backgroundColor: LumiTokens.green,
                    foregroundColor: LumiTokens.paper,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                    ),
                  ),
                  child: Text('Confirm', style: LumiType.button),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
