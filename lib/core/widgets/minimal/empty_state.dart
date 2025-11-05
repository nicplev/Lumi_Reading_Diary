import 'package:flutter/material.dart';
import '../../theme/minimal_theme.dart';
import 'pill_button.dart';

/// Empty state widget with icon, message, and optional CTA
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? buttonText;
  final VoidCallback? onButtonPressed;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.buttonText,
    this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MinimalTheme.spaceXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: MinimalTheme.lightPurple.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: MinimalTheme.primaryPurple,
              ),
            ),
            const SizedBox(height: MinimalTheme.spaceL),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: MinimalTheme.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: MinimalTheme.spaceS),
            Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: MinimalTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (buttonText != null && onButtonPressed != null) ...[
              const SizedBox(height: MinimalTheme.spaceL),
              SizedBox(
                width: 200,
                child: PillButton(
                  text: buttonText!,
                  onPressed: onButtonPressed,
                  fullWidth: false,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
