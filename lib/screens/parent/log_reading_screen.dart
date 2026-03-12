import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_text_styles.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../core/widgets/lumi/lumi_card.dart';
import '../../core/widgets/lumi/blob_selector.dart';
import '../../core/widgets/lumi/comment_chips.dart';
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
  final PageController _pageController = PageController();
  final TextEditingController _bookTitleController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  int _currentStep = 0;
  static const _totalSteps = 4;

  // Step 1: Book selection
  final List<String> _assignedBookTitles = [];
  final Set<String> _selectedBookTitles = {};
  final List<String> _customBookTitles = [];
  int _selectedMinutes = 20;

  // Step 2: Child feeling
  ReadingFeeling? _selectedFeeling;

  // Step 3: Parent comment
  List<String> _selectedComments = [];

  // Step 4: Confirmation
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedMinutes = widget.allocation?.targetMinutes ?? 20;

    if (widget.allocation != null &&
        widget.allocation!.bookTitles != null &&
        widget.allocation!.bookTitles!.isNotEmpty) {
      _assignedBookTitles.addAll(widget.allocation!.bookTitles!);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _bookTitleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep == 0 &&
        _selectedBookTitles.isEmpty &&
        _customBookTitles.isEmpty) {
      setState(() => _errorMessage = 'Please select or enter a book');
      return;
    }
    setState(() => _errorMessage = null);

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  List<String> get _finalBookTitles {
    return [..._selectedBookTitles, ..._customBookTitles];
  }

  String get _parentCommentText {
    final chips = _selectedComments.join('. ');
    final notes = _notesController.text.trim();
    if (chips.isNotEmpty && notes.isNotEmpty) {
      return '$chips. $notes';
    }
    return chips.isNotEmpty ? chips : notes;
  }

  Future<void> _saveReadingLog() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();
      final log = ReadingLogModel(
        id: now.millisecondsSinceEpoch.toString(),
        studentId: widget.student.id,
        parentId: widget.parent.id,
        schoolId: widget.student.schoolId,
        classId: widget.student.classId,
        date: now,
        minutesRead: _selectedMinutes,
        targetMinutes: widget.allocation?.targetMinutes ?? 20,
        status: LogStatus.completed,
        bookTitles: _finalBookTitles,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        childFeeling: _selectedFeeling,
        parentComment:
            _parentCommentText.isNotEmpty ? _parentCommentText : null,
        parentCommentSelections: List<String>.from(_selectedComments),
        parentCommentFreeText: _notesController.text.trim().isNotEmpty
            ? _notesController.text.trim()
            : null,
        createdAt: now,
        allocationId: widget.allocation?.id,
      );

      final logData = log.toFirestore();
      // Use server timestamp for audit trail (teachers can see exact submission time)
      logData['createdAt'] = FieldValue.serverTimestamp();

      await _firebaseService.firestore
          .collection('schools')
          .doc(widget.parent.schoolId)
          .collection('readingLogs')
          .doc(log.id)
          .set(logData);

      final updatedStats = await _updateStudentStats();

      if (mounted) {
        context.go('/parent/reading-success', extra: {
          'student': widget.student,
          'parent': widget.parent,
          'readingLog': log,
          'updatedStats': updatedStats,
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save reading log. Please try again.';
        _isLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _updateStudentStats() async {
    try {
      final studentRef = _firebaseService.firestore
          .collection('schools')
          .doc(widget.parent.schoolId)
          .collection('students')
          .doc(widget.student.id);

      Map<String, dynamic>? newStats;

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

          final lastReadingDate = stats['lastReadingDate'] != null
              ? (stats['lastReadingDate'] as Timestamp).toDate().toLocal()
              : null;

          int newStreak = 1;
          bool isNewDay = true;
          if (lastReadingDate != null) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final lastDay = DateTime(
              lastReadingDate.year,
              lastReadingDate.month,
              lastReadingDate.day,
            );
            final calendarDaysDiff = today.difference(lastDay).inDays;

            if (calendarDaysDiff == 1) {
              newStreak = currentStreak + 1;
            } else if (calendarDaysDiff == 0) {
              newStreak = currentStreak;
              isNewDay = false; // Same day — don't double-count
            }
            // calendarDaysDiff > 1 means streak is broken, newStreak stays 1
          }

          final newTotalDays =
              isNewDay ? totalReadingDays + 1 : totalReadingDays;

          newStats = {
            'totalMinutesRead': totalMinutesRead + _selectedMinutes,
            'totalBooksRead': totalBooksRead + _finalBookTitles.length,
            'currentStreak': newStreak,
            'longestStreak':
                newStreak > longestStreak ? newStreak : longestStreak,
            'lastReadingDate': FieldValue.serverTimestamp(),
            'totalReadingDays': newTotalDays,
            'averageMinutesPerDay': (totalMinutesRead + _selectedMinutes) /
                (newTotalDays > 0 ? newTotalDays : 1),
          };

          transaction.update(studentRef, {'stats': newStats});
        }
      });

      return newStats;
    } catch (e) {
      debugPrint('Error updating student stats: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        title: Text(
          'Log Reading - ${widget.student.firstName}',
          style: LumiTextStyles.h3(),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Step indicator
            _buildStepIndicator(),

            // Page content
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1BookSelection(),
                  _buildStep2ChildAssessment(),
                  _buildStep3ParentComment(),
                  _buildStep4Confirmation(),
                ],
              ),
            ),

            // Error message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
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
                              LumiTextStyles.bodySmall(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Navigation buttons
            _buildNavigationButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: List.generate(_totalSteps, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: index < _totalSteps - 1 ? 8 : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 4,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.rosePink
                      : isActive
                          ? AppColors.rosePink.withValues(alpha: 0.6)
                          : AppColors.charcoal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Step 1: Book Selection ──────────────────────────────

  Widget _buildStep1BookSelection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What did you read?', style: LumiTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            'Select a book or add your own',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Assigned books as checkbox list
          if (_assignedBookTitles.isNotEmpty) ...[
            LumiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Assigned Books', style: LumiTextStyles.label()),
                  const SizedBox(height: 12),
                  ..._assignedBookTitles.map((title) => CheckboxListTile(
                        title: Text(title, style: LumiTextStyles.body()),
                        value: _selectedBookTitles.contains(title),
                        activeColor: AppColors.rosePink,
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedBookTitles.add(title);
                            } else {
                              _selectedBookTitles.remove(title);
                            }
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      )),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Manual entry
          LumiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _assignedBookTitles.isNotEmpty
                      ? 'Or add a book'
                      : 'Add a book',
                  style: LumiTextStyles.label(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _bookTitleController,
                        decoration: const InputDecoration(
                          hintText: 'Enter book title',
                          prefixIcon: Icon(Icons.add),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) {
                          if (value.isNotEmpty &&
                              !_customBookTitles.contains(value)) {
                            setState(() {
                              _customBookTitles.add(value);
                              _bookTitleController.clear();
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () {
                        final value = _bookTitleController.text.trim();
                        if (value.isNotEmpty &&
                            !_customBookTitles.contains(value)) {
                          setState(() {
                            _customBookTitles.add(value);
                            _bookTitleController.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add_circle),
                      color: AppColors.rosePink,
                      iconSize: 32,
                    ),
                  ],
                ),
                if (_customBookTitles.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _customBookTitles
                          .map((title) => Chip(
                                label: Text(title),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () {
                                  setState(
                                      () => _customBookTitles.remove(title));
                                },
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Minutes selector
          LumiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer, color: AppColors.rosePink),
                    const SizedBox(width: 8),
                    Text('Reading Time', style: LumiTextStyles.label()),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '$_selectedMinutes min',
                    style: LumiTextStyles.display(color: AppColors.rosePink),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [10, 15, 20, 25, 30].map((minutes) {
                    return ChoiceChip(
                      label: Text('$minutes'),
                      selected: _selectedMinutes == minutes,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _selectedMinutes = minutes);
                        }
                      },
                      selectedColor: AppColors.rosePink,
                      labelStyle: TextStyle(
                        color: _selectedMinutes == minutes
                            ? AppColors.white
                            : AppColors.charcoal,
                        fontWeight: _selectedMinutes == minutes
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ─── Step 2: Child Assessment ────────────────────────────

  Widget _buildStep2ChildAssessment() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: BlobSelector(
          selectedFeeling: _selectedFeeling,
          onFeelingSelected: (feeling) {
            setState(() => _selectedFeeling = feeling);
          },
        ),
      ),
    ).animate().fadeIn();
  }

  // ─── Step 3: Parent Comment ──────────────────────────────

  Widget _buildStep3ParentComment() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentChips(
            selectedComments: _selectedComments,
            onCommentsChanged: (comments) {
              setState(() => _selectedComments = comments);
            },
          ),
          const SizedBox(height: 24),
          Text('Additional notes', style: LumiTextStyles.label()),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Anything else to add? (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  // ─── Step 4: Confirmation ────────────────────────────────

  Widget _buildStep4Confirmation() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text('Confirm Reading', style: LumiTextStyles.h2()),
          const SizedBox(height: 8),
          Text(
            'Review and confirm tonight\'s reading',
            style: LumiTextStyles.bodySmall(
              color: AppColors.charcoal.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),

          // Summary card
          LumiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSummaryRow(
                  Icons.menu_book,
                  _finalBookTitles.length == 1 ? 'Book' : 'Books',
                  _finalBookTitles.isNotEmpty
                      ? _finalBookTitles.join(', ')
                      : 'Not selected',
                ),
                const Divider(height: 24),
                _buildSummaryRow(
                  Icons.timer,
                  'Duration',
                  '$_selectedMinutes minutes',
                ),
                if (_selectedFeeling != null) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.emoji_emotions,
                    'How it felt',
                    _selectedFeeling!.name[0].toUpperCase() +
                        _selectedFeeling!.name.substring(1),
                  ),
                ],
                if (_selectedComments.isNotEmpty) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.chat_bubble_outline,
                    'Comments',
                    _selectedComments.join(', '),
                  ),
                ],
                if (_notesController.text.isNotEmpty) ...[
                  const Divider(height: 24),
                  _buildSummaryRow(
                    Icons.note,
                    'Notes',
                    _notesController.text,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Confirmation button with green gradient
          SizedBox(
            width: double.infinity,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _saveReadingLog,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppColors.white),
                        ),
                      )
                    : const Icon(Icons.check, color: AppColors.white),
                label: Text(
                  'I read with my child tonight',
                  style: LumiTextStyles.button(),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn();
  }

  Widget _buildSummaryRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.rosePink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: LumiTextStyles.caption(
                  color: AppColors.charcoal.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(value, style: LumiTextStyles.body()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: LumiSecondaryButton(
                onPressed: _previousStep,
                text: 'Back',
                icon: Icons.arrow_back,
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          if (_currentStep < _totalSteps - 1)
            Expanded(
              child: LumiPrimaryButton(
                onPressed: _nextStep,
                text: _currentStep == 0
                    ? 'Next'
                    : _currentStep == 1
                        ? (_selectedFeeling != null ? 'Next' : 'Skip')
                        : 'Review',
                isFullWidth: true,
              ),
            ),
        ],
      ),
    );
  }
}
