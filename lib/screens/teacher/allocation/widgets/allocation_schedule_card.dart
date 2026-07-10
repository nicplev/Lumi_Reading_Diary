import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../../../../data/models/allocation_model.dart';
import 'allocation_form_common.dart';

/// "Schedule" card: cadence, minutes target, and the start/end date window.
class AllocationScheduleCard extends StatelessWidget {
  const AllocationScheduleCard({
    super.key,
    required this.cadence,
    required this.cadenceLabel,
    required this.minutesController,
    required this.startDate,
    required this.endDate,
    required this.onCadenceTap,
    required this.onStartDateTap,
    required this.onEndDateTap,
  });

  final AllocationCadence cadence;
  final String cadenceLabel;
  final TextEditingController minutesController;
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onCadenceTap;
  final VoidCallback onStartDateTap;
  final VoidCallback onEndDateTap;

  String get _minutesLabel {
    switch (cadence) {
      case AllocationCadence.daily:
        return 'Minutes / day';
      case AllocationCadence.weekly:
        return 'Minutes / week';
      case AllocationCadence.fortnightly:
        return 'Minutes / fortnight';
      case AllocationCadence.custom:
        return 'Minutes target';
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = endDate.difference(startDate).inDays;

    return AllocationFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AllocationSectionHeader(step: 2, title: 'Schedule'),
          const SizedBox(height: 16),

          // Cadence + minutes row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PickerField(
                  label: 'Frequency',
                  value: cadenceLabel,
                  onTap: onCadenceTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MinutesField(
                  label: _minutesLabel,
                  controller: minutesController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Date range row
          Row(
            children: [
              Expanded(
                child: _PickerField(
                  label: 'Start date',
                  value: DateFormat('MMM dd, yyyy').format(startDate),
                  trailingIcon: Icons.calendar_today_outlined,
                  onTap: onStartDateTap,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PickerField(
                  label: 'End date',
                  value: DateFormat('MMM dd, yyyy').format(endDate),
                  trailingIcon: Icons.calendar_today_outlined,
                  onTap: onEndDateTap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 14, color: LumiTokens.muted),
              const SizedBox(width: 6),
              Text(
                'Reading window · ${days == 1 ? '1 day' : '$days days'}',
                style: LumiType.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MinutesField extends StatefulWidget {
  const _MinutesField({
    required this.label,
    required this.controller,
  });

  final String label;
  final TextEditingController controller;

  @override
  State<_MinutesField> createState() => _MinutesFieldState();
}

class _MinutesFieldState extends State<_MinutesField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasFocus = _focusNode.hasFocus;
    final focusColor = LumiTokens.green;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: LumiType.caption.copyWith(
            color: LumiTokens.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          height: 52,
          decoration: BoxDecoration(
            color: hasFocus
                ? LumiTokens.tintGreen.withValues(alpha: 0.18)
                : LumiTokens.cream,
            borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
            border: Border.all(
              color: hasFocus ? focusColor : LumiTokens.rule,
              width: hasFocus ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  cursorColor: focusColor,
                  style: LumiType.body.copyWith(color: LumiTokens.ink),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                  ),
                ),
              ),
              Text('min', style: LumiType.caption),
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled, tappable field that looks like a dropdown (used for the cadence
/// and date pickers).
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.trailingIcon = Icons.keyboard_arrow_down,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: LumiType.caption.copyWith(
              color: LumiTokens.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: LumiTokens.cream,
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              border: Border.all(color: LumiTokens.rule, width: 1.2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: LumiType.body.copyWith(color: LumiTokens.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(trailingIcon, size: 16, color: LumiTokens.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
