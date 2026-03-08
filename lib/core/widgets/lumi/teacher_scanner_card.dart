import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Lumi Design System - Teacher Scanner Card
///
/// Gradient hero card for ISBN scanner with icon, text, and action button.
/// Per style preview: teacherGradient background, circular icon, pill button.
class TeacherScannerCard extends StatelessWidget {
  final VoidCallback? onPressed;
  final String title;
  final String description;
  final String buttonText;
  final IconData icon;

  const TeacherScannerCard({
    super.key,
    this.onPressed,
    this.title = 'Scan Books',
    this.description = 'Quickly add books by scanning their ISBN barcode',
    this.buttonText = 'Open Scanner',
    this.icon = Icons.qr_code_scanner,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.teacherGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 32,
              color: AppColors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: onPressed,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.teacherPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
