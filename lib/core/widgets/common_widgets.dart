import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Common reusable UI components for consistent design across the app
class CommonWidgets {
  CommonWidgets._(); // Private constructor to prevent instantiation

  /// Standard card with consistent styling
  static Widget buildCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  /// Status badge widget for displaying active/inactive states
  static Widget buildStatusBadge({
    required String label,
    required Color color,
    double fontSize = 10,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  /// Role badge for users
  static Widget buildRoleBadge(String role) {
    Color color;
    String displayText;

    switch (role.toLowerCase()) {
      case 'teacher':
        color = AppColors.teacherColor;
        displayText = 'TEACHER';
        break;
      case 'parent':
        color = AppColors.parentColor;
        displayText = 'PARENT';
        break;
      case 'schooladmin':
        color = AppColors.adminColor;
        displayText = 'ADMIN';
        break;
      default:
        color = AppColors.gray;
        displayText = role.toUpperCase();
    }

    return buildStatusBadge(label: displayText, color: color);
  }

  /// Empty state widget
  static Widget buildEmptyState({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 100,
            color: AppColors.gray.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.gray,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.gray,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    );
  }

  /// Loading widget
  static Widget buildLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.primaryBlue,
      ),
    );
  }

  /// Error widget
  static Widget buildErrorState({
    required String message,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: AppColors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGray,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.gray,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  /// Section header
  static Widget buildSectionHeader({
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkGray,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.gray,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// Stat card for displaying metrics
  static Widget buildStatCard({
    required String label,
    required String value,
    IconData? icon,
    Color? color,
  }) {
    return Column(
      children: [
        if (icon != null)
          Icon(
            icon,
            size: 32,
            color: color ?? AppColors.primaryBlue,
          ),
        if (icon != null) const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.darkGray,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.gray,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Search bar
  static Widget buildSearchBar({
    required ValueChanged<String> onChanged,
    String hintText = 'Search...',
    TextEditingController? controller,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.white,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search, color: AppColors.gray),
          filled: true,
          fillColor: AppColors.offWhite,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// Confirmation dialog
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDangerous = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: isDangerous
                ? TextButton.styleFrom(foregroundColor: AppColors.error)
                : null,
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  /// Success snackbar
  static void showSuccessSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Error snackbar
  static void showErrorSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Info snackbar
  static void showInfoSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.info,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Avatar with initials
  static Widget buildAvatar({
    required String name,
    double size = 40,
    Color? backgroundColor,
    Color? textColor,
  }) {
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .take(2)
            .map((word) => word.isNotEmpty ? word[0].toUpperCase() : '')
            .join()
        : '?';

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: backgroundColor ?? AppColors.primaryBlue.withOpacity(0.2),
      child: Text(
        initials,
        style: TextStyle(
          color: textColor ?? AppColors.primaryBlue,
          fontWeight: FontWeight.bold,
          fontSize: size * 0.4,
        ),
      ),
    );
  }

  /// Icon badge (for roles, etc.)
  static Widget buildIconBadge({
    required IconData icon,
    required Color color,
    double size = 40,
  }) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withOpacity(0.2),
      child: Icon(
        icon,
        color: color,
        size: size * 0.5,
      ),
    );
  }

  /// Divider with text
  static Widget buildDividerWithText(String text) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.gray,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  /// Wrap list with consistent spacing
  static Widget buildWrapList({
    required List<Widget> children,
    double spacing = 8,
    double runSpacing = 8,
  }) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      children: children,
    );
  }
}
