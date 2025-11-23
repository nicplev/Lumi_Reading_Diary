import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/lumi_text_styles.dart';
import '../../theme/lumi_spacing.dart';
import '../../theme/lumi_borders.dart';

/// Lumi Design System - Text Input
///
/// Standard text input with design system styling
/// 12pt vertical, 16pt horizontal padding
/// 12pt border radius, with focus states
///
/// Usage:
/// ```dart
/// LumiInput(
///   label: 'Email',
///   hintText: 'Enter your email',
///   controller: emailController,
/// )
/// ```
class LumiInput extends StatefulWidget {
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int? maxLines;
  final int? maxLength;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final FormFieldValidator<String>? validator;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final bool autofocus;

  const LumiInput({
    super.key,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.controller,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
    this.onTap,
    this.validator,
    this.inputFormatters,
    this.textInputAction,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<LumiInput> createState() => _LumiInputState();
}

class _LumiInputState extends State<LumiInput> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _focusNode.dispose();
    } else {
      _focusNode.removeListener(_onFocusChange);
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  Color get _borderColor {
    if (widget.errorText != null) {
      return AppColors.error;
    }
    if (_isFocused) {
      return AppColors.rosePink;
    }
    return AppColors.charcoal.withOpacity(0.2);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: LumiTextStyles.label(),
          ),
          const SizedBox(height: LumiSpacing.elementSpacing),
        ],
        TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: widget.keyboardType,
          obscureText: widget.obscureText,
          enabled: widget.enabled,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          onChanged: widget.onChanged,
          onTap: widget.onTap,
          validator: widget.validator,
          inputFormatters: widget.inputFormatters,
          textInputAction: widget.textInputAction,
          autofocus: widget.autofocus,
          style: LumiTextStyles.body(),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: LumiTextStyles.body(
              color: AppColors.charcoal.withOpacity(0.5),
            ),
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.suffixIcon,
            filled: true,
            fillColor: widget.enabled
                ? AppColors.white
                : AppColors.charcoal.withOpacity(0.05),
            contentPadding: LumiPadding.input,
            border: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: BorderSide(
                color: AppColors.charcoal.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: BorderSide(
                color: AppColors.charcoal.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: const BorderSide(
                color: AppColors.rosePink,
                width: 2.0,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 2.0,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: BorderSide(
                color: AppColors.charcoal.withOpacity(0.1),
                width: 1.5,
              ),
            ),
            errorText: widget.errorText,
            errorStyle: LumiTextStyles.error(),
          ),
        ),
        if (widget.helperText != null && widget.errorText == null) ...[
          const SizedBox(height: LumiSpacing.xxs),
          Text(
            widget.helperText!,
            style: LumiTextStyles.caption(),
          ),
        ],
      ],
    );
  }
}

/// Lumi Design System - Search Input
///
/// Search input with search icon and clear button
///
/// Usage:
/// ```dart
/// LumiSearchInput(
///   hintText: 'Search books...',
///   onChanged: (value) => performSearch(value),
/// )
/// ```
class LumiSearchInput extends StatefulWidget {
  final String? hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const LumiSearchInput({
    super.key,
    this.hintText,
    this.controller,
    this.onChanged,
    this.onClear,
  });

  @override
  State<LumiSearchInput> createState() => _LumiSearchInputState();
}

class _LumiSearchInputState extends State<LumiSearchInput> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _controller.addListener(_onTextChanged);
    _hasText = _controller.text.isNotEmpty;
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    } else {
      _controller.removeListener(_onTextChanged);
    }
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _hasText = _controller.text.isNotEmpty;
    });
  }

  void _clearText() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    return LumiInput(
      controller: _controller,
      hintText: widget.hintText ?? 'Search...',
      onChanged: widget.onChanged,
      prefixIcon: Icon(
        Icons.search,
        color: AppColors.charcoal.withOpacity(0.5),
      ),
      suffixIcon: _hasText
          ? IconButton(
              icon: Icon(
                Icons.close,
                color: AppColors.charcoal.withOpacity(0.5),
              ),
              onPressed: _clearText,
            )
          : null,
    );
  }
}

/// Lumi Design System - Password Input
///
/// Password input with visibility toggle
///
/// Usage:
/// ```dart
/// LumiPasswordInput(
///   label: 'Password',
///   controller: passwordController,
/// )
/// ```
class LumiPasswordInput extends StatefulWidget {
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  const LumiPasswordInput({
    super.key,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.controller,
    this.onChanged,
    this.validator,
  });

  @override
  State<LumiPasswordInput> createState() => _LumiPasswordInputState();
}

class _LumiPasswordInputState extends State<LumiPasswordInput> {
  bool _obscureText = true;

  void _toggleVisibility() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LumiInput(
      label: widget.label,
      hintText: widget.hintText,
      helperText: widget.helperText,
      errorText: widget.errorText,
      controller: widget.controller,
      obscureText: _obscureText,
      onChanged: widget.onChanged,
      validator: widget.validator,
      keyboardType: TextInputType.visiblePassword,
      suffixIcon: IconButton(
        icon: Icon(
          _obscureText ? Icons.visibility : Icons.visibility_off,
          color: AppColors.charcoal.withOpacity(0.5),
        ),
        onPressed: _toggleVisibility,
      ),
    );
  }
}

/// Lumi Design System - Textarea
///
/// Multi-line text input for longer content
///
/// Usage:
/// ```dart
/// LumiTextarea(
///   label: 'Notes',
///   hintText: 'Write your notes here...',
///   maxLines: 5,
/// )
/// ```
class LumiTextarea extends StatelessWidget {
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextEditingController? controller;
  final int maxLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  const LumiTextarea({
    super.key,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.controller,
    this.maxLines = 5,
    this.maxLength,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return LumiInput(
      label: label,
      hintText: hintText,
      helperText: helperText,
      errorText: errorText,
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      onChanged: onChanged,
      validator: validator,
      keyboardType: TextInputType.multiline,
    );
  }
}

/// Lumi Design System - Dropdown Input
///
/// Dropdown selector with design system styling
///
/// Usage:
/// ```dart
/// LumiDropdown<String>(
///   label: 'Category',
///   value: selectedCategory,
///   items: ['Fiction', 'Non-Fiction', 'Poetry'],
///   onChanged: (value) => setState(() => selectedCategory = value),
/// )
/// ```
class LumiDropdown<T> extends StatelessWidget {
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final T? value;
  final List<T> items;
  final ValueChanged<T?>? onChanged;
  final String Function(T)? itemLabel;
  final bool enabled;

  const LumiDropdown({
    super.key,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabel,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: LumiTextStyles.label(),
          ),
          const SizedBox(height: LumiSpacing.elementSpacing),
        ],
        DropdownButtonFormField<T>(
          initialValue: value,
          onChanged: enabled ? onChanged : null,
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Text(
                itemLabel?.call(item) ?? item.toString(),
                style: LumiTextStyles.body(),
              ),
            );
          }).toList(),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: LumiTextStyles.body(
              color: AppColors.charcoal.withOpacity(0.5),
            ),
            filled: true,
            fillColor: enabled
                ? AppColors.white
                : AppColors.charcoal.withOpacity(0.05),
            contentPadding: LumiPadding.input,
            border: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: BorderSide(
                color: AppColors.charcoal.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: BorderSide(
                color: AppColors.charcoal.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: const BorderSide(
                color: AppColors.rosePink,
                width: 2.0,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 1.5,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: const BorderSide(
                color: AppColors.error,
                width: 2.0,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: LumiBorders.medium,
              borderSide: BorderSide(
                color: AppColors.charcoal.withOpacity(0.1),
                width: 1.5,
              ),
            ),
            errorText: errorText,
            errorStyle: LumiTextStyles.error(),
          ),
          style: LumiTextStyles.body(),
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.charcoal.withOpacity(0.5),
          ),
          dropdownColor: AppColors.white,
        ),
        if (helperText != null && errorText == null) ...[
          const SizedBox(height: LumiSpacing.xxs),
          Text(
            helperText!,
            style: LumiTextStyles.caption(),
          ),
        ],
      ],
    );
  }
}
