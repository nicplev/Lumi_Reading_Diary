import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/teacher_constants.dart';
import '../../core/widgets/lumi/teacher_reading_level_pill.dart';
import '../../data/models/school_model.dart';
import '../../data/models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../services/reading_level_service.dart';

class ReadingLevelSettingsScreen extends StatefulWidget {
  final UserModel adminUser;

  const ReadingLevelSettingsScreen({
    super.key,
    required this.adminUser,
  });

  @override
  State<ReadingLevelSettingsScreen> createState() =>
      _ReadingLevelSettingsScreenState();
}

class _ReadingLevelSettingsScreenState
    extends State<ReadingLevelSettingsScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final ReadingLevelService _readingLevelService = ReadingLevelService();

  bool _isLoading = true;
  bool _isSaving = false;
  SchoolModel? _school;

  // Editable state
  bool _levelsEnabled = true;
  ReadingLevelSchema _selectedSchema = ReadingLevelSchema.aToZ;
  List<String> _customLevels = [];
  Map<String, String> _levelColors = {};
  final TextEditingController _newLevelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSchool();
  }

  @override
  void dispose() {
    _newLevelController.dispose();
    super.dispose();
  }

  Future<void> _loadSchool() async {
    final schoolId = widget.adminUser.schoolId;
    if (schoolId == null || schoolId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final doc = await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .get();

      if (doc.exists) {
        final school = SchoolModel.fromFirestore(doc);
        setState(() {
          _school = school;
          _levelsEnabled = school.hasReadingLevels;
          _selectedSchema = school.levelSchema == ReadingLevelSchema.none
              ? ReadingLevelSchema.aToZ
              : school.levelSchema;
          _customLevels = List<String>.from(school.customLevels ?? []);
          _levelColors = Map<String, String>.from(school.levelColors ?? {});
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading school: $e');
      setState(() => _isLoading = false);
    }
  }

  bool get _needsCustomLevels =>
      _selectedSchema == ReadingLevelSchema.custom ||
      _selectedSchema == ReadingLevelSchema.namedLevels ||
      _selectedSchema == ReadingLevelSchema.colouredLevels;

  Future<void> _save() async {
    final schoolId = widget.adminUser.schoolId;
    if (schoolId == null || schoolId.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final effectiveSchema =
          _levelsEnabled ? _selectedSchema : ReadingLevelSchema.none;

      final updates = <String, dynamic>{
        'levelSchema': effectiveSchema.toString().split('.').last,
        'customLevels': _levelsEnabled && _needsCustomLevels
            ? _customLevels
            : null,
        'levelColors': _levelsEnabled &&
                _selectedSchema == ReadingLevelSchema.colouredLevels
            ? _levelColors
            : null,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firebaseService.firestore
          .collection('schools')
          .doc(schoolId)
          .update(updates);

      // Invalidate the reading level service cache
      await _readingLevelService.loadSchoolLevels(
        schoolId,
        forceRefresh: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reading level settings saved'),
          backgroundColor: AppColors.success,
        ),
      );

      // Reload school to reflect changes
      await _loadSchool();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _addLevel() {
    final name = _newLevelController.text.trim();
    if (name.isEmpty || _customLevels.contains(name)) return;
    setState(() {
      _customLevels.add(name);
      _newLevelController.clear();
    });
  }

  void _removeLevel(int index) {
    setState(() {
      final removed = _customLevels.removeAt(index);
      _levelColors.remove(removed);
    });
  }

  void _reorderLevel(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _customLevels.removeAt(oldIndex);
      _customLevels.insert(newIndex, item);
    });
  }

  void _pickColor(String levelName) {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pick colour for "$levelName"'),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: colors.map((color) {
              final hex =
                  '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              final isSelected = _levelColors[levelName] == hex;
              return GestureDetector(
                onTap: () {
                  setState(() => _levelColors[levelName] = hex);
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: AppColors.charcoal, width: 3)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse('FF$cleaned', radix: 16);
    if (value == null) return null;
    return Color(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Reading Level Settings'),
          backgroundColor: AppColors.teacherPrimary,
          foregroundColor: AppColors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Reading Level Settings',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.teacherPrimary,
        foregroundColor: AppColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toggle
            _buildToggleCard(),
            const SizedBox(height: 20),

            // Schema selector (only when enabled)
            if (_levelsEnabled) ...[
              _buildSchemaSelector(),
              const SizedBox(height: 20),
            ],

            // Level editor (for custom/named/coloured schemas)
            if (_levelsEnabled && _needsCustomLevels) ...[
              _buildLevelEditor(),
              const SizedBox(height: 20),
            ],

            // Preview
            if (_levelsEnabled) ...[
              _buildPreview(),
              const SizedBox(height: 24),
            ],

            // Save button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.teacherPrimary,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : Text('Save Changes',
                        style: TeacherTypography.buttonText),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleCard() {
    return _card(
      child: SwitchListTile(
        title: Text('Enable Reading Levels', style: TeacherTypography.h3),
        subtitle: Text(
          _levelsEnabled
              ? 'Students can be assigned reading levels'
              : 'Reading levels are hidden across the app',
          style: TeacherTypography.bodySmall,
        ),
        value: _levelsEnabled,
        activeTrackColor: AppColors.teacherPrimary.withValues(alpha: 0.4),
        activeThumbColor: AppColors.teacherPrimary,
        contentPadding: EdgeInsets.zero,
        onChanged: (value) => setState(() => _levelsEnabled = value),
      ),
    );
  }

  Widget _buildSchemaSelector() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Level System', style: TeacherTypography.h3),
          const SizedBox(height: 12),
          _schemaRadio(
            ReadingLevelSchema.aToZ,
            'A-Z Levels',
            'Traditional A through Z',
          ),
          _schemaRadio(
            ReadingLevelSchema.pmBenchmark,
            'PM Benchmark',
            'Levels 1-30',
          ),
          _schemaRadio(
            ReadingLevelSchema.lexile,
            'Lexile',
            'BR to 1400L',
          ),
          _schemaRadio(
            ReadingLevelSchema.numbered,
            'Numbered 1-100',
            'Simple numbered levels',
          ),
          _schemaRadio(
            ReadingLevelSchema.namedLevels,
            'Named Levels',
            'Define your own level names',
          ),
          _schemaRadio(
            ReadingLevelSchema.colouredLevels,
            'Colour Levels',
            'Named levels with custom colours',
          ),
          _schemaRadio(
            ReadingLevelSchema.custom,
            'Custom',
            'Define your own levels',
          ),
        ],
      ),
    );
  }

  Widget _schemaRadio(
    ReadingLevelSchema schema,
    String title,
    String subtitle,
  ) {
    final isSelected = _selectedSchema == schema;
    return InkWell(
      onTap: () => setState(() => _selectedSchema = schema),
      borderRadius: BorderRadius.circular(TeacherDimensions.radiusM),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected
                  ? AppColors.teacherPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TeacherTypography.bodyMedium),
                  Text(subtitle, style: TeacherTypography.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelEditor() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Level Names', style: TeacherTypography.h3),
          const SizedBox(height: 12),

          // Add level input
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newLevelController,
                  decoration: InputDecoration(
                    hintText: 'Add a level name',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(TeacherDimensions.radiusM),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: TeacherTypography.bodyMedium,
                  onSubmitted: (_) => _addLevel(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _addLevel,
                icon: const Icon(Icons.add_circle),
                color: AppColors.teacherPrimary,
                iconSize: 32,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Reorderable level list
          if (_customLevels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'No levels added yet',
                  style: TeacherTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _customLevels.length,
              onReorder: _reorderLevel,
              itemBuilder: (context, index) {
                final level = _customLevels[index];
                final colorHex = _levelColors[level];
                final color = _parseHexColor(colorHex);

                return Container(
                  key: ValueKey('level_$index'),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius:
                        BorderRadius.circular(TeacherDimensions.radiusM),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.drag_handle,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      if (_selectedSchema ==
                          ReadingLevelSchema.colouredLevels) ...[
                        GestureDetector(
                          onTap: () => _pickColor(level),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color ?? AppColors.textSecondary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.divider,
                                width: 2,
                              ),
                            ),
                            child: color == null
                                ? const Icon(Icons.palette,
                                    size: 14, color: AppColors.white)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          level,
                          style: TeacherTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: AppColors.textSecondary,
                        onPressed: () => _removeLevel(index),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    // Build preview options based on current selection
    final SchoolModel previewSchool;
    if (_school != null) {
      previewSchool = SchoolModel(
        id: _school!.id,
        name: _school!.name,
        levelSchema: _selectedSchema,
        customLevels: _needsCustomLevels ? _customLevels : null,
        levelColors: _selectedSchema == ReadingLevelSchema.colouredLevels
            ? _levelColors
            : null,
        termDates: _school!.termDates,
        quietHours: _school!.quietHours,
        timezone: _school!.timezone,
        createdAt: _school!.createdAt,
        createdBy: _school!.createdBy,
      );
    } else {
      return const SizedBox.shrink();
    }

    final levels = previewSchool.readingLevels;
    final previewLevels = levels.take(10).toList();

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preview', style: TeacherTypography.h3),
          const SizedBox(height: 4),
          Text(
            '${levels.length} level${levels.length == 1 ? '' : 's'} total',
            style: TeacherTypography.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: previewLevels.map((level) {
              final colorHex = _selectedSchema ==
                      ReadingLevelSchema.colouredLevels
                  ? _levelColors[level]
                  : null;
              final color = _parseHexColor(colorHex);

              return TeacherReadingLevelPill(
                label: level,
                levelColor: color,
              );
            }).toList(),
          ),
          if (levels.length > 10) ...[
            const SizedBox(height: 8),
            Text(
              '... and ${levels.length - 10} more',
              style: TeacherTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(TeacherDimensions.radiusL),
        boxShadow: TeacherDimensions.cardShadow,
      ),
      child: child,
    );
  }
}
