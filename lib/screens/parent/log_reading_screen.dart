import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/lumi_mascot.dart';
import '../../data/models/user_model.dart';
import '../../data/models/student_model.dart';
import '../../data/models/allocation_model.dart';
import '../../data/models/reading_log_model.dart';
import '../../services/firebase_service.dart';

class LogReadingScreen extends StatefulWidget {
  final StudentModel student;
  final UserModel parent;
  final AllocationModel? allocation;

  const LogReadingScreen({
    super.key,
    required this.student,
    required this.parent,
    this.allocation,
  });

  @override
  State<LogReadingScreen> createState() => _LogReadingScreenState();
}

class _LogReadingScreenState extends State<LogReadingScreen> {
  final FirebaseService _firebaseService = FirebaseService.instance;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _bookTitleController = TextEditingController();
  final List<String> _bookTitles = [];

  int _selectedMinutes = 20;
  File? _selectedImage;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.allocation?.targetMinutes ?? 20;

    // Pre-populate book titles if allocation has specific titles
    if (widget.allocation != null &&
        widget.allocation!.bookTitles != null &&
        widget.allocation!.bookTitles!.isNotEmpty) {
      _bookTitles.addAll(widget.allocation!.bookTitles!);
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _bookTitleController.dispose();
    super.dispose();
  }

  Future<void> _selectImage() async {
    final ImagePicker picker = ImagePicker();

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.gallery,
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 85,
                  );
                  if (image != null) {
                    setState(() {
                      _selectedImage = File(image.path);
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a Photo'),
                onTap: () async {
                  Navigator.pop(context);
                  final XFile? image = await picker.pickImage(
                    source: ImageSource.camera,
                    maxWidth: 1024,
                    maxHeight: 1024,
                    imageQuality: 85,
                  );
                  if (image != null) {
                    setState(() {
                      _selectedImage = File(image.path);
                    });
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveReadingLog() async {
    if (_bookTitles.isEmpty) {
      setState(() {
        _errorMessage = 'Please add at least one book title';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Create reading log
      final log = ReadingLogModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        studentId: widget.student.id,
        parentId: widget.parent.id,
        schoolId: widget.student.schoolId,
        classId: widget.student.classId,
        date: DateTime.now(),
        minutesRead: _selectedMinutes,
        targetMinutes: widget.allocation?.targetMinutes ?? 20,
        status: LogStatus.completed,
        bookTitles: _bookTitles,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        createdAt: DateTime.now(),
        allocationId: widget.allocation?.id,
      );

      // Save to Firestore using nested structure
      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.parent.schoolId)
          .collection('readingLogs')
          .doc(log.id)
          .set(log.toFirestore());

      // Update student stats
      await _updateStudentStats();

      // Show success animation
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save reading log. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStudentStats() async {
    try {
      final studentRef = _firebaseService.firestore
          .collection('students')
          .doc(widget.student.id);

      await _firebaseService.firestore.runTransaction((transaction) async {
        final studentDoc = await transaction.get(studentRef);

        if (studentDoc.exists) {
          final data = studentDoc.data() as Map<String, dynamic>;
          final stats = data['stats'] as Map<String, dynamic>? ?? {};

          final currentStreak = stats['currentStreak'] ?? 0;
          final longestStreak = stats['longestStreak'] ?? 0;
          final totalMinutesRead = stats['totalMinutesRead'] ?? 0;
          final totalBooksRead = stats['totalBooksRead'] ?? 0;
          final totalReadingDays = stats['totalReadingDays'] ?? 0;

          // Check if this continues a streak
          final lastReadingDate = stats['lastReadingDate'] != null
              ? (stats['lastReadingDate'] as Timestamp).toDate()
              : null;

          int newStreak = 1;
          if (lastReadingDate != null) {
            final daysSinceLastReading =
                DateTime.now().difference(lastReadingDate).inDays;
            if (daysSinceLastReading == 1) {
              newStreak = currentStreak + 1;
            } else if (daysSinceLastReading == 0) {
              // Already logged today, don't update streak
              newStreak = currentStreak;
            }
          }

          transaction.update(studentRef, {
            'stats': {
              'totalMinutesRead': totalMinutesRead + _selectedMinutes,
              'totalBooksRead': totalBooksRead + _bookTitles.length,
              'currentStreak': newStreak,
              'longestStreak':
                  newStreak > longestStreak ? newStreak : longestStreak,
              'lastReadingDate': FieldValue.serverTimestamp(),
              'totalReadingDays': totalReadingDays + 1,
              'averageMinutesPerDay': (totalMinutesRead + _selectedMinutes) /
                  (totalReadingDays + 1),
            },
          });
        }
      });
    } catch (e) {
      debugPrint('Error updating student stats: $e');
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Animate(
                  effects: const [
                    ScaleEffect(duration: Duration(milliseconds: 500)),
                  ],
                  child: const LumiMascot(
                    mood: LumiMood.celebrating,
                    size: 120,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Great Job!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGray,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.student.firstName} completed $_selectedMinutes minutes of reading!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.gray,
                      ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close dialog
                    Navigator.pop(context, true); // Return to home with success
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text('Log Reading - ${widget.student.firstName}'),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Minutes selector
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer, color: AppColors.primaryBlue),
                          const SizedBox(width: 8),
                          Text(
                            'Reading Time',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      Center(
                        child: Column(
                          children: [
                            Text(
                              '$_selectedMinutes',
                              style: Theme.of(context)
                                  .textTheme
                                  .displayLarge
                                  ?.copyWith(
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            Text(
                              'minutes',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: AppColors.gray,
                                  ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Quick select buttons
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [10, 15, 20, 25, 30, 45, 60].map((minutes) {
                          return ChoiceChip(
                            label: Text('$minutes min'),
                            selected: _selectedMinutes == minutes,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _selectedMinutes = minutes;
                                });
                              }
                            },
                            selectedColor: AppColors.primaryBlue,
                            labelStyle: TextStyle(
                              color: _selectedMinutes == minutes
                                  ? AppColors.white
                                  : AppColors.darkGray,
                              fontWeight: _selectedMinutes == minutes
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 12),

                      // Custom slider
                      Slider(
                        value: _selectedMinutes.toDouble(),
                        min: 5,
                        max: 120,
                        divisions: 23,
                        label: '$_selectedMinutes minutes',
                        onChanged: (value) {
                          setState(() {
                            _selectedMinutes = value.round();
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(),

              const SizedBox(height: 16),

              // Books read
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.book,
                              color: AppColors.secondaryPurple),
                          const SizedBox(width: 8),
                          Text(
                            'Books Read',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Note about flexible book system
                      if (widget.allocation == null ||
                          widget.allocation!.type ==
                              AllocationType.freeChoice) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  color: AppColors.info, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Add any books or reading materials',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: AppColors.info,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Book list
                      ..._bookTitles.map((title) => Card(
                            color: AppColors.offWhite,
                            child: ListTile(
                              leading: const Icon(Icons.menu_book,
                                  color: AppColors.secondaryPurple),
                              title: Text(title),
                              trailing: IconButton(
                                icon: const Icon(Icons.close,
                                    color: AppColors.gray),
                                onPressed: () {
                                  setState(() {
                                    _bookTitles.remove(title);
                                  });
                                },
                              ),
                            ),
                          )),

                      const SizedBox(height: 8),

                      // Add book field
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _bookTitleController,
                              decoration: const InputDecoration(
                                hintText: 'Enter book title or material',
                                prefixIcon: Icon(Icons.add),
                              ),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (value) {
                                if (value.isNotEmpty) {
                                  setState(() {
                                    _bookTitles.add(value);
                                    _bookTitleController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              if (_bookTitleController.text.isNotEmpty) {
                                setState(() {
                                  _bookTitles.add(_bookTitleController.text);
                                  _bookTitleController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.add_circle),
                            color: AppColors.primaryBlue,
                            iconSize: 32,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 16),

              // Optional notes
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.note,
                              color: AppColors.secondaryYellow),
                          const SizedBox(width: 8),
                          Text(
                            'Notes (Optional)',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'How did the reading go? Any challenges or achievements?',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 16),

              // Photo attachment
              Card(
                child: InkWell(
                  onTap: _selectImage,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (_selectedImage != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _selectedImage!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedImage = null;
                              });
                            },
                            icon: const Icon(Icons.delete),
                            label: const Text('Remove Photo'),
                          ),
                        ] else ...[
                          const Icon(
                            Icons.add_a_photo,
                            size: 48,
                            color: AppColors.gray,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add a photo (optional)',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.gray,
                                    ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 600.ms),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.error,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Save button
              ElevatedButton(
                onPressed: _isLoading ? null : _saveReadingLog,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.white),
                        ),
                      )
                    : const Text('Complete Reading'),
              ).animate().fadeIn(delay: 800.ms),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
