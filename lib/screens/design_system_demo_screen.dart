import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/lumi_text_styles.dart';
import '../core/theme/lumi_spacing.dart';
import '../core/theme/lumi_borders.dart';
import '../core/widgets/lumi/lumi_buttons.dart';
import '../core/widgets/lumi/lumi_card.dart';
import '../core/widgets/lumi/lumi_input.dart';

/// Lumi Design System Demo Screen
///
/// Showcases all design system components and patterns
/// Use this as a reference for implementing the design system
class DesignSystemDemoScreen extends StatefulWidget {
  const DesignSystemDemoScreen({super.key});

  @override
  State<DesignSystemDemoScreen> createState() => _DesignSystemDemoScreenState();
}

class _DesignSystemDemoScreenState extends State<DesignSystemDemoScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();
  String? _selectedCategory = 'Fiction';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: AppBar(
        title: Text(
          'Lumi Design System',
          style: LumiTextStyles.h3(),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.charcoal),
      ),
      body: ListView(
        padding: LumiPadding.screen,
        children: [
          // Typography Section
          _buildSection(
            'Typography',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Display Text', style: LumiTextStyles.display()),
                LumiGap.xs,
                Text('Display Medium', style: LumiTextStyles.displayMedium()),
                LumiGap.xs,
                Text('Heading 1', style: LumiTextStyles.h1()),
                LumiGap.xs,
                Text('Heading 2', style: LumiTextStyles.h2()),
                LumiGap.xs,
                Text('Heading 3', style: LumiTextStyles.h3()),
                LumiGap.xs,
                Text('Body Large - The quick brown fox jumps over the lazy dog',
                  style: LumiTextStyles.bodyLarge()),
                LumiGap.xs,
                Text('Body - The quick brown fox jumps over the lazy dog',
                  style: LumiTextStyles.body()),
                LumiGap.xs,
                Text('Body Small - The quick brown fox jumps over the lazy dog',
                  style: LumiTextStyles.bodySmall()),
                LumiGap.xs,
                Text('Caption text for timestamps and hints',
                  style: LumiTextStyles.caption()),
                LumiGap.xs,
                Text('Label Text', style: LumiTextStyles.label()),
              ],
            ),
          ),

          LumiGap.l,

          // Colors Section
          _buildSection(
            'Colors',
            Column(
              children: [
                _buildColorRow('Rose Pink (Primary)', AppColors.rosePink),
                LumiGap.xs,
                _buildColorRow('Mint Green (Success)', AppColors.mintGreen),
                LumiGap.xs,
                _buildColorRow('Soft Yellow (Warning)', AppColors.softYellow),
                LumiGap.xs,
                _buildColorRow('Warm Orange (Accent)', AppColors.warmOrange),
                LumiGap.xs,
                _buildColorRow('Sky Blue (Info)', AppColors.skyBlue),
                LumiGap.xs,
                _buildColorRow('Charcoal (Text)', AppColors.charcoal),
                LumiGap.xs,
                _buildColorRow('White (Background)', AppColors.white,
                  border: true),
              ],
            ),
          ),

          LumiGap.l,

          // Buttons Section
          _buildSection(
            'Buttons',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LumiPrimaryButton(
                  onPressed: () => _showSnackBar('Primary button pressed'),
                  text: 'Primary Button',
                ),
                LumiGap.xs,
                LumiPrimaryButton(
                  onPressed: () => _showSnackBar('Button with icon'),
                  text: 'With Icon',
                  icon: Icons.favorite,
                ),
                LumiGap.xs,
                const LumiPrimaryButton(
                  onPressed: null,
                  text: 'Disabled',
                ),
                LumiGap.xs,
                const LumiPrimaryButton(
                  onPressed: null,
                  text: 'Loading',
                  isLoading: true,
                ),
                LumiGap.m,
                LumiSecondaryButton(
                  onPressed: () => _showSnackBar('Secondary button pressed'),
                  text: 'Secondary Button',
                ),
                LumiGap.xs,
                LumiSecondaryButton(
                  onPressed: () => _showSnackBar('Button with icon'),
                  text: 'With Icon',
                  icon: Icons.edit,
                ),
                LumiGap.m,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LumiTextButton(
                      onPressed: () => _showSnackBar('Text button pressed'),
                      text: 'Text Button',
                    ),
                    LumiGap.horizontalS,
                    LumiTextButton(
                      onPressed: () => _showSnackBar('Button with icon'),
                      text: 'With Icon',
                      icon: Icons.arrow_forward,
                    ),
                  ],
                ),
                LumiGap.m,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LumiIconButton(
                      onPressed: () => _showSnackBar('Back'),
                      icon: Icons.arrow_back,
                    ),
                    LumiGap.horizontalS,
                    LumiIconButton(
                      onPressed: () => _showSnackBar('Favorite'),
                      icon: Icons.favorite_border,
                      iconColor: AppColors.rosePink,
                    ),
                    LumiGap.horizontalS,
                    LumiIconButton(
                      onPressed: () => _showSnackBar('Settings'),
                      icon: Icons.settings,
                      backgroundColor: AppColors.skyBlue,
                    ),
                  ],
                ),
              ],
            ),
          ),

          LumiGap.l,

          // Cards Section
          _buildSection(
            'Cards',
            Column(
              children: [
                LumiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Standard Card', style: LumiTextStyles.h3()),
                      LumiGap.xs,
                      Text(
                        'This is a standard card with 20pt padding, 16pt radius, and subtle shadow.',
                        style: LumiTextStyles.body(),
                      ),
                    ],
                  ),
                ),
                LumiGap.s,
                LumiCard(
                  onTap: () => _showSnackBar('Card tapped'),
                  child: Row(
                    children: [
                      const Icon(Icons.touch_app, color: AppColors.rosePink),
                      LumiGap.horizontalXS,
                      Expanded(
                        child: Text(
                          'Tappable card with animation',
                          style: LumiTextStyles.bodyMedium(),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 16),
                    ],
                  ),
                ),
                LumiGap.s,
                LumiCard(
                  isHighlighted: true,
                  child: Text(
                    'Highlighted card with sky blue background',
                    style: LumiTextStyles.body(),
                  ),
                ),
                LumiGap.s,
                LumiCompactCard(
                  child: Row(
                    children: [
                      const Icon(Icons.list, size: 20),
                      LumiGap.horizontalXS,
                      Text(
                        'Compact card for list items',
                        style: LumiTextStyles.body(),
                      ),
                    ],
                  ),
                ),
                LumiGap.m,
                const LumiInfoCard(
                  type: LumiInfoCardType.success,
                  title: 'Success',
                  message: 'Your action was completed successfully!',
                ),
                LumiGap.xs,
                const LumiInfoCard(
                  type: LumiInfoCardType.warning,
                  message: 'Please review this important information.',
                ),
                LumiGap.xs,
                const LumiInfoCard(
                  type: LumiInfoCardType.error,
                  title: 'Error',
                  message: 'Something went wrong. Please try again.',
                ),
                LumiGap.xs,
                LumiInfoCard(
                  type: LumiInfoCardType.info,
                  message: 'This is helpful information for you.',
                  onDismiss: () => _showSnackBar('Info dismissed'),
                ),
                LumiGap.m,
                LumiEmptyCard(
                  icon: Icons.book_outlined,
                  title: 'No Books Yet',
                  message: 'Start your reading journey by adding your first book',
                  actionText: 'Add Book',
                  onAction: () => _showSnackBar('Add book tapped'),
                ),
              ],
            ),
          ),

          LumiGap.l,

          // Input Fields Section
          _buildSection(
            'Input Fields',
            Column(
              children: [
                LumiInput(
                  label: 'Email',
                  hintText: 'Enter your email',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: const Icon(Icons.email_outlined),
                  helperText: 'We\'ll never share your email',
                ),
                LumiGap.s,
                LumiInput(
                  label: 'Username',
                  hintText: 'Enter username',
                  errorText: 'Username is required',
                ),
                LumiGap.s,
                LumiPasswordInput(
                  label: 'Password',
                  hintText: 'Enter your password',
                  controller: _passwordController,
                  helperText: 'Must be at least 8 characters',
                ),
                LumiGap.s,
                LumiSearchInput(
                  hintText: 'Search books...',
                  controller: _searchController,
                  onChanged: (value) => debugPrint('Searching: $value'),
                ),
                LumiGap.s,
                LumiTextarea(
                  label: 'Notes',
                  hintText: 'Write your notes here...',
                  maxLines: 4,
                  helperText: 'Maximum 500 characters',
                ),
                LumiGap.s,
                LumiDropdown<String>(
                  label: 'Category',
                  hintText: 'Select a category',
                  value: _selectedCategory,
                  items: const ['Fiction', 'Non-Fiction', 'Poetry', 'Biography'],
                  onChanged: (value) => setState(() => _selectedCategory = value),
                  helperText: 'Choose the book category',
                ),
                LumiGap.s,
                const LumiInput(
                  label: 'Disabled Input',
                  hintText: 'This field is disabled',
                  enabled: false,
                ),
              ],
            ),
          ),

          LumiGap.l,

          // Spacing Section
          _buildSection(
            'Spacing (8pt Grid)',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSpacingExample('XXS', LumiSpacing.xxs, '4pt'),
                _buildSpacingExample('XS', LumiSpacing.xs, '8pt'),
                _buildSpacingExample('S', LumiSpacing.s, '16pt'),
                _buildSpacingExample('M', LumiSpacing.m, '24pt'),
                _buildSpacingExample('L', LumiSpacing.l, '32pt'),
                _buildSpacingExample('XL', LumiSpacing.xl, '48pt'),
                _buildSpacingExample('XXL', LumiSpacing.xxl, '64pt'),
              ],
            ),
          ),

          LumiGap.l,

          // Border Radius Section
          _buildSection(
            'Border Radius',
            Column(
              children: [
                _buildBorderExample('Small (8pt)', LumiBorders.small),
                LumiGap.xs,
                _buildBorderExample('Medium (12pt)', LumiBorders.medium),
                LumiGap.xs,
                _buildBorderExample('Large (16pt)', LumiBorders.large),
                LumiGap.xs,
                _buildBorderExample('X-Large (24pt)', LumiBorders.xLarge),
                LumiGap.xs,
                Container(
                  padding: LumiPadding.allS,
                  decoration: BoxDecoration(
                    color: AppColors.rosePink,
                    borderRadius: LumiBorders.circular,
                  ),
                  child: Text(
                    'Circular (9999pt)',
                    style: LumiTextStyles.body(color: AppColors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

          LumiGap.xxl,
        ],
      ),
      floatingActionButton: LumiFab(
        onPressed: () => _showSnackBar('FAB pressed'),
        icon: Icons.add,
        label: 'Add Item',
        isExtended: true,
      ),
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: LumiTextStyles.h2(),
        ),
        LumiGap.s,
        child,
      ],
    );
  }

  Widget _buildColorRow(String name, Color color, {bool border = false}) {
    return Row(
      children: [
        Container(
          width: 60,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: LumiBorders.small,
            border: border
                ? Border.all(color: AppColors.charcoal.withOpacity(0.2))
                : null,
          ),
        ),
        LumiGap.horizontalS,
        Expanded(
          child: Text(
            name,
            style: LumiTextStyles.body(),
          ),
        ),
        Text(
          color.value.toRadixString(16).toUpperCase().padLeft(8, '0'),
          style: LumiTextStyles.caption(),
        ),
      ],
    );
  }

  Widget _buildSpacingExample(String name, double size, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LumiSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              name,
              style: LumiTextStyles.bodyMedium(),
            ),
          ),
          Container(
            width: size,
            height: 24,
            color: AppColors.rosePink,
          ),
          LumiGap.horizontalS,
          Text(
            value,
            style: LumiTextStyles.caption(),
          ),
        ],
      ),
    );
  }

  Widget _buildBorderExample(String label, BorderRadius radius) {
    return Container(
      padding: LumiPadding.allS,
      decoration: BoxDecoration(
        color: AppColors.skyBlue,
        borderRadius: radius,
      ),
      child: Text(
        label,
        style: LumiTextStyles.body(),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.charcoal,
      ),
    );
  }
}
