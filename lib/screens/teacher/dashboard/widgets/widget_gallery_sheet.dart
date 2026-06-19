import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../theme/lumi_tokens.dart';
import '../../../../theme/lumi_typography.dart';
import '../models/widget_registry.dart';

/// Modal bottom sheet that lists inactive (available-to-add) dashboard widgets.
class WidgetGallerySheet extends StatelessWidget {
  final List<DashboardWidgetDefinition> availableWidgets;
  final ValueChanged<String> onAddWidget;

  const WidgetGallerySheet({
    super.key,
    required this.availableWidgets,
    required this.onAddWidget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: LumiTokens.rule,
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            ),
          ),
          const SizedBox(height: 20),
          Text('Add Widget',
              style: LumiType.subhead.copyWith(fontSize: 22)),
          const SizedBox(height: 18),
          if (availableWidgets.isEmpty)
            _buildEmptyState()
          else
            ...availableWidgets.map((def) => _GalleryItem(
                  definition: def,
                  onAdd: () => onAddWidget(def.id),
                )),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 28),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: LumiTokens.tintGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                size: 32, color: LumiTokens.green),
          ),
          const SizedBox(height: 16),
          Text(
            "You're using every widget",
            style: LumiType.subhead,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Remove one from your dashboard to add it back here.',
            style: LumiType.body.copyWith(
              color: LumiTokens.muted,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GalleryItem extends StatelessWidget {
  final DashboardWidgetDefinition definition;
  final VoidCallback onAdd;

  const _GalleryItem({required this.definition, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: LumiTokens.cream,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onAdd();
          },
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: LumiTokens.tintBlue,
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                  child: Icon(definition.icon,
                      size: 20, color: LumiTokens.blue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(definition.displayName,
                          style: LumiType.body.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          )),
                      const SizedBox(height: 2),
                      Text(definition.description, style: LumiType.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: LumiTokens.blue,
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 18, color: LumiTokens.paper),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
