import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../characters/lumi_character.dart';
import '../../core/utils/image_decode.dart';

enum LumiTourRole { parent, teacher }

typedef LumiTourStepChanged = FutureOr<void> Function(LumiTourStep step);

class LumiTourStep {
  const LumiTourStep({
    required this.id,
    required this.targetId,
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    this.tip,
    this.tabIndex,
    this.spotlightTarget = true,
    this.iosOnly = false,
  });

  final String id;
  final String targetId;
  final String title;
  final String body;
  final String? tip;
  final IconData icon;
  final Color accent;
  final int? tabIndex;
  final bool spotlightTarget;
  final bool iosOnly;
}

class LumiTourDefinition {
  const LumiTourDefinition({
    required this.id,
    required this.role,
    required this.version,
    required this.steps,
  });

  final String id;
  final LumiTourRole role;
  final int version;
  final List<LumiTourStep> steps;
}

@visibleForTesting
List<LumiTourStep> availableLumiTourSteps(
  LumiTourDefinition definition, {
  bool? isWeb,
  TargetPlatform? platform,
}) {
  final effectiveIsWeb = isWeb ?? kIsWeb;
  final effectivePlatform = platform ?? defaultTargetPlatform;
  return definition.steps
      .where(
        (step) =>
            !step.iosOnly ||
            (!effectiveIsWeb && effectivePlatform == TargetPlatform.iOS),
      )
      .toList(growable: false);
}

class LumiTourDefinitions {
  LumiTourDefinitions._();

  static const parent = LumiTourDefinition(
    id: 'parent_core',
    role: LumiTourRole.parent,
    version: 1,
    steps: [
      LumiTourStep(
        id: 'logging',
        targetId: 'parent.readingCard',
        tabIndex: 0,
        title: 'Log Reading',
        body:
            'For one-child accounts, this card is your daily reading hub. Tap Log reading to add books, minutes, comments, and how reading felt.',
        tip:
            'If your school allows Quick log, you may also see a smaller shortcut for target-minutes-only days. Once logged, this card opens reading history.',
        icon: Icons.edit_note_rounded,
        accent: LumiTokens.red,
      ),
      LumiTourStep(
        id: 'progress',
        targetId: 'parent.progressCard',
        tabIndex: 0,
        title: 'Progress',
        body:
            'This card shows the current streak, week rhythm, and the next badge for the selected child.',
        tip:
            'Short, steady reading streaks are the habit Lumi is designed to protect.',
        icon: Icons.local_fire_department_rounded,
        accent: LumiTokens.orange,
      ),
      LumiTourStep(
        id: 'library',
        targetId: 'parent.nav.library',
        tabIndex: 1,
        title: 'Library',
        body:
            'The library keeps reading history and book activity in one place, so you can look back without digging through logs.',
        icon: Icons.auto_stories_outlined,
        accent: LumiTokens.yellow,
      ),
      LumiTourStep(
        id: 'settings',
        targetId: 'parent.nav.settings',
        tabIndex: 2,
        title: 'Settings',
        body:
            'Manage children, reminders, account recovery, and replay this tour any time from Settings.',
        tip: 'Reminders work best when they match your family reading routine.',
        icon: Icons.settings_outlined,
        accent: LumiTokens.green,
      ),
      LumiTourStep(
        id: 'link_child',
        targetId: 'parent.settings.linkChild',
        tabIndex: 2,
        title: 'Add Another Child',
        body:
            'If you receive invite codes for more than one child, keep using this same parent account. Add each extra code here to link every child in one place.',
        tip:
            'You only need one Lumi parent account for your family, even when each child has their own invite email.',
        icon: Icons.person_add_alt_1_rounded,
        accent: LumiTokens.green,
      ),
      // Appended without bumping `version`, so only new users (who haven't
      // completed v1 yet) see it — existing parents aren't re-onboarded.
      LumiTourStep(
        id: 'widget',
        targetId: 'parent.home',
        // End on the home tab (the widget is a home-screen concept), not
        // whatever tab the previous step left selected.
        tabIndex: 0,
        title: 'Home Screen Widget',
        body:
            "Add the Lumi widget to your phone's home screen to see your child's reading streak and progress at a glance — without opening the app.",
        tip:
            'Long-press your home screen, tap the + button, then search for "Lumi" to add it.',
        icon: Icons.widgets_rounded,
        accent: LumiTokens.blue,
        spotlightTarget: false,
        iosOnly: true,
      ),
    ],
  );

  static const teacher = LumiTourDefinition(
    id: 'teacher_core',
    role: LumiTourRole.teacher,
    version: 2,
    steps: [
      LumiTourStep(
        id: 'dashboard',
        targetId: 'teacher.dashboard',
        tabIndex: 0,
        title: 'Dashboard',
        body:
            'Start here for the class snapshot: reading activity, patterns, and which students may need attention.',
        icon: Icons.dashboard_outlined,
        accent: LumiTokens.blue,
        spotlightTarget: false,
      ),
      LumiTourStep(
        id: 'dashboard_customize',
        targetId: 'teacher.dashboard.customizeButton',
        tabIndex: 0,
        title: 'Customise Dashboard',
        body:
            'Choose the widgets you want at a glance, remove what you do not need, and drag cards into the order that matches your day.',
        tip:
            'Tap Customize dashboard at the bottom of the dashboard, or long-press the dashboard to start editing.',
        icon: Icons.dashboard_customize_rounded,
        accent: LumiTokens.blue,
      ),
      LumiTourStep(
        id: 'class',
        targetId: 'teacher.nav.class',
        tabIndex: 1,
        title: 'Class',
        body:
            'The class screen is the daily workspace for students, reading levels, groups, and book workflows.',
        icon: Icons.groups_outlined,
        accent: LumiTokens.green,
      ),
      LumiTourStep(
        id: 'assign_books',
        targetId: 'teacher.class.assignBooks',
        tabIndex: 1,
        title: 'Manual Assign',
        body:
            'Use Assign books when you want to choose titles for the whole class, groups, or specific students by hand.',
        tip: 'Manual assigning is best for planned weekly take-home books.',
        icon: Icons.auto_awesome_rounded,
        accent: LumiTokens.green,
      ),
      LumiTourStep(
        id: 'teacher_scan',
        targetId: 'teacher.class.scanBooks',
        tabIndex: 1,
        title: 'Teacher Scan',
        body:
            'Tap Scan when you want to scan ISBNs yourself and assign books to students as you go.',
        tip: 'This is the fastest teacher-led workflow during book changeover.',
        icon: Icons.qr_code_scanner_rounded,
        accent: LumiTokens.green,
      ),
      LumiTourStep(
        id: 'class_scan_in',
        targetId: 'teacher.class.kioskScanIn',
        tabIndex: 1,
        title: 'Class Scan-In',
        body:
            'Class scan-in opens a student-friendly kiosk so children can scan their own books on a shared device.',
        tip: 'Use Guided Access or app pinning before handing over the device.',
        icon: Icons.tablet_mac_rounded,
        accent: LumiTokens.green,
      ),
      LumiTourStep(
        id: 'library',
        targetId: 'teacher.nav.library',
        tabIndex: 2,
        title: 'Library',
        body:
            'The library is the shared book catalogue for your school, including covers, ISBNs, and assignment visibility.',
        icon: Icons.book_outlined,
        accent: LumiTokens.yellow,
      ),
      LumiTourStep(
        id: 'add_book',
        targetId: 'teacher.library.addBook',
        tabIndex: 2,
        title: 'Add Book',
        body:
            'Tap Add book to scan an ISBN and add a new title only when it is not already available.',
        tip: 'Scanning first avoids duplicate books and saves time.',
        icon: Icons.document_scanner_rounded,
        accent: LumiTokens.yellow,
      ),
      LumiTourStep(
        id: 'settings',
        targetId: 'teacher.nav.settings',
        tabIndex: 3,
        title: 'Settings',
        body:
            'Use Settings for Reading Groups, Awards, and Parent/Guardian Notifications. Build groups, adjust award tools, then choose which families receive each update.',
        tip:
            'Notifications can be customised by audience and message before sending.',
        icon: Icons.settings_outlined,
        accent: LumiTokens.red,
      ),
      // Appended without bumping `version`, so only new users (who haven't
      // completed v2 yet) see it — existing teachers aren't re-onboarded.
      LumiTourStep(
        id: 'widget',
        targetId: 'teacher.home',
        // Return to the dashboard for the final card — the widget content is a
        // dashboard concept, and the tour should end on the dashboard, not the
        // Settings tab the previous step left us on.
        tabIndex: 0,
        title: 'Home Screen Widgets',
        body:
            "Add Lumi widgets to your device's home screen for an at-a-glance view — today's reading, top readers, and the class calendar — without opening the app.",
        tip:
            'Long-press your home screen, tap the + button, then search for "Lumi" to add a widget.',
        icon: Icons.widgets_rounded,
        accent: LumiTokens.blue,
        spotlightTarget: false,
        iosOnly: true,
      ),
    ],
  );
}

class LumiTourService {
  const LumiTourService();

  Future<bool> isCompleted({
    required LumiTourDefinition definition,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(definition: definition, userId: userId)) ?? false;
  }

  Future<void> markCompleted({
    required LumiTourDefinition definition,
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(definition: definition, userId: userId), true);
  }

  String _key({
    required LumiTourDefinition definition,
    required String userId,
  }) {
    return 'lumi_tour_${definition.role.name}_${definition.id}_v${definition.version}_$userId';
  }
}

class LumiTourController extends ChangeNotifier {
  LumiTourController({LumiTourService service = const LumiTourService()})
      : _service = service;

  final LumiTourService _service;
  final Map<String, GlobalKey> _targets = {};

  LumiTourDefinition? _definition;
  List<LumiTourStep> _activeSteps = const [];
  String? _userId;
  LumiTourStepChanged? _onStepChanged;
  int _currentIndex = 0;
  bool _isActive = false;
  bool _isTransitioning = false;

  bool get isActive => _isActive;
  bool get isTransitioning => _isTransitioning;
  int get currentIndex => _currentIndex;

  LumiTourDefinition? get definition => _definition;

  LumiTourStep? get currentStep {
    final definition = _definition;
    if (definition == null || _currentIndex >= _activeSteps.length) {
      return null;
    }
    return _activeSteps[_currentIndex];
  }

  int get totalSteps => _activeSteps.length;
  bool get isFirstStep => _currentIndex == 0;
  bool get isLastStep => _currentIndex == totalSteps - 1;

  Future<void> start({
    required LumiTourDefinition definition,
    required String userId,
    bool force = false,
    LumiTourStepChanged? onStepChanged,
  }) async {
    if (_isActive) return;
    if (!force) {
      final completed = await _service.isCompleted(
        definition: definition,
        userId: userId,
      );
      if (completed) return;
    }

    _definition = definition;
    _activeSteps = availableLumiTourSteps(definition);
    _userId = userId;
    _onStepChanged = onStepChanged;
    _currentIndex = 0;
    _isActive = true;
    notifyListeners();
    await _prepareCurrentStep();
  }

  Future<void> next() async {
    if (_isTransitioning || !_isActive) return;
    if (isLastStep) {
      await complete();
      return;
    }
    _currentIndex++;
    notifyListeners();
    await _prepareCurrentStep();
  }

  Future<void> previous() async {
    if (_isTransitioning || !_isActive || isFirstStep) return;
    _currentIndex--;
    notifyListeners();
    await _prepareCurrentStep();
  }

  Future<void> complete() async {
    final definition = _definition;
    final userId = _userId;
    if (definition != null && userId != null) {
      await _service.markCompleted(definition: definition, userId: userId);
    }
    _definition = null;
    _activeSteps = const [];
    _userId = null;
    _onStepChanged = null;
    _currentIndex = 0;
    _isActive = false;
    _isTransitioning = false;
    notifyListeners();
  }

  Rect? targetRect(BuildContext overlayContext) {
    final step = currentStep;
    if (step == null) return null;

    final key = _targets[step.targetId];
    final targetContext = key?.currentContext;
    final overlayObject = overlayContext.findRenderObject();
    final targetObject = targetContext?.findRenderObject();
    if (overlayObject is! RenderBox ||
        targetObject is! RenderBox ||
        !overlayObject.attached ||
        !targetObject.attached ||
        targetObject.size.isEmpty) {
      return null;
    }

    final topLeft = targetObject.localToGlobal(
      Offset.zero,
      ancestor: overlayObject,
    );
    return topLeft & targetObject.size;
  }

  void registerTarget(String id, GlobalKey key) {
    _targets[id] = key;
    _notifyWhenCurrentTargetChanges(id);
  }

  void unregisterTarget(String id, GlobalKey key) {
    if (identical(_targets[id], key)) {
      _targets.remove(id);
      _notifyWhenCurrentTargetChanges(id);
    }
  }

  void _notifyWhenCurrentTargetChanges(String id) {
    if (!_isActive || currentStep?.targetId != id) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isActive && currentStep?.targetId == id) notifyListeners();
    });
  }

  Future<void> _prepareCurrentStep() async {
    final step = currentStep;
    if (step == null) return;
    _isTransitioning = true;
    notifyListeners();
    await Future<void>.sync(() => _onStepChanged?.call(step));
    await Future<void>.delayed(const Duration(milliseconds: 140));
    _isTransitioning = false;
    notifyListeners();
    _scheduleSettleRemeasure(step);
  }

  /// Some targets scroll or animate into place *after* their step activates —
  /// e.g. the teacher dashboard auto-scrolls (~420ms) to the "Customise
  /// dashboard" button, which sits off-screen at the bottom of the list. The
  /// overlay only re-measures the target rect when the controller notifies, so
  /// without this the spotlight freezes at a mid-scroll (or off-screen) rect
  /// and only corrects itself once the user steps away and back. Re-notify a
  /// few times over the following ~0.75s so the overlay re-measures once the
  /// layout has settled.
  void _scheduleSettleRemeasure(LumiTourStep step) {
    if (!step.spotlightTarget) return;
    const delaysMs = [150, 300, 500, 750];
    for (final ms in delaysMs) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (_isActive && identical(currentStep, step)) {
          notifyListeners();
        }
      });
    }
  }
}

class LumiTourScope extends InheritedNotifier<LumiTourController> {
  const LumiTourScope({
    super.key,
    required LumiTourController controller,
    required super.child,
  }) : super(notifier: controller);

  static LumiTourController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<LumiTourScope>()
        ?.notifier;
  }
}

class LumiTourTarget extends StatefulWidget {
  const LumiTourTarget({
    super.key,
    required this.id,
    required this.child,
  });

  final String id;
  final Widget child;

  @override
  State<LumiTourTarget> createState() => _LumiTourTargetState();
}

class _LumiTourTargetState extends State<LumiTourTarget> {
  final GlobalKey _targetKey = GlobalKey();
  LumiTourController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = LumiTourScope.maybeOf(context);
    if (!identical(nextController, _controller)) {
      _controller?.unregisterTarget(widget.id, _targetKey);
      _controller = nextController;
      _controller?.registerTarget(widget.id, _targetKey);
    }
  }

  @override
  void didUpdateWidget(covariant LumiTourTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _controller?.unregisterTarget(oldWidget.id, _targetKey);
      _controller?.registerTarget(widget.id, _targetKey);
    }
  }

  @override
  void dispose() {
    _controller?.unregisterTarget(widget.id, _targetKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _targetKey,
      child: widget.child,
    );
  }
}

class LumiTourOverlay extends StatelessWidget {
  const LumiTourOverlay({
    super.key,
    required this.controller,
  });

  final LumiTourController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isActive || controller.currentStep == null) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: _LumiTourOverlayContent(controller: controller),
        );
      },
    );
  }
}

class _LumiTourOverlayContent extends StatelessWidget {
  const _LumiTourOverlayContent({required this.controller});

  final LumiTourController controller;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final step = controller.currentStep!;
    final rawTarget =
        step.spotlightTarget ? controller.targetRect(context) : null;
    final fullRect = Offset.zero & media.size;
    final target = _useTargetSpotlight(rawTarget, media.size)
        ? rawTarget!.inflate(8).intersect(fullRect)
        : null;
    // Place the card in whichever gap (above vs below the spotlight) is larger,
    // rather than off the target's centre — a tall target whose centre sits just
    // above the midpoint would otherwise send the card to the bottom and overlap
    // the target's lower half.
    final placeCardAtTop = target != null &&
        target.top > (media.size.height - target.bottom);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _TourScrimPainter(targetRect: target),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Align(
                alignment: placeCardAtTop
                    ? Alignment.topCenter
                    : Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(media.size.width - 32, 420),
                  ),
                  child: _TourCard(
                    step: step,
                    controller: controller,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _useTargetSpotlight(Rect? target, Size screenSize) {
    if (target == null || target.isEmpty || screenSize.isEmpty) return false;
    final screenArea = screenSize.width * screenSize.height;
    final targetArea = target.width * target.height;
    final coversMostWidth = target.width > screenSize.width * 0.86;
    final coversMostHeight = target.height > screenSize.height * 0.46;
    return targetArea / screenArea < 0.42 &&
        !(coversMostWidth && coversMostHeight);
  }
}

class _TourScrimPainter extends CustomPainter {
  const _TourScrimPainter({required this.targetRect});

  final Rect? targetRect;

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(fullRect);

    final target = targetRect;
    if (target != null && !target.isEmpty) {
      path.addRRect(
        RRect.fromRectAndRadius(target, const Radius.circular(22)),
      );
    }

    canvas.drawPath(
      path,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    if (target != null && !target.isEmpty) {
      final rrect = RRect.fromRectAndRadius(
        target,
        const Radius.circular(22),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = LumiTokens.paper.withValues(alpha: 0.75),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TourScrimPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect;
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.controller,
  });

  final LumiTourStep step;
  final LumiTourController controller;

  @override
  Widget build(BuildContext context) {
    final character = _characterForIndex(controller.currentIndex);
    final isBusy = controller.isTransitioning;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: LumiTokens.paper,
        borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        border: Border.all(color: LumiTokens.rule),
        boxShadow: LumiTokens.shadowCard,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Image.asset(
                    character.assetPath,
                    fit: BoxFit.contain,
                    cacheWidth: decodeCacheSize(context, 62),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(step.icon, size: 18, color: step.accent),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              step.title,
                              style: LumiType.subhead,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        step.body,
                        style: LumiType.body.copyWith(
                          color: LumiTokens.ink.withValues(alpha: 0.82),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (step.tip != null) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: step.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_outlined,
                        size: 17, color: step.accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.tip!,
                        style: LumiType.caption.copyWith(
                          color: LumiTokens.ink.withValues(alpha: 0.78),
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                _ProgressDots(
                  count: controller.totalSteps,
                  activeIndex: controller.currentIndex,
                  color: step.accent,
                ),
                const Spacer(),
                Text(
                  '${controller.currentIndex + 1}/${controller.totalSteps}',
                  style: LumiType.caption.copyWith(
                    color: LumiTokens.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                TextButton(
                  onPressed: isBusy ? null : () => _confirmSkip(context),
                  child: Text(
                    'Skip',
                    style: LumiType.body.copyWith(color: LumiTokens.muted),
                  ),
                ),
                const Spacer(),
                if (!controller.isFirstStep) ...[
                  OutlinedButton(
                    onPressed:
                        isBusy ? null : () => unawaited(controller.previous()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                      side: const BorderSide(color: LumiTokens.rule),
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                      ),
                    ),
                    child: Text(
                      'Back',
                      style: LumiType.button.copyWith(color: LumiTokens.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton(
                  onPressed: isBusy ? null : () => unawaited(controller.next()),
                  style: FilledButton.styleFrom(
                    backgroundColor: step.accent,
                    foregroundColor: step.accent == LumiTokens.yellow
                        ? LumiTokens.ink
                        : LumiTokens.paper,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(LumiTokens.radiusMedium),
                    ),
                  ),
                  child: Text(
                    controller.isLastStep ? 'Done' : 'Next',
                    style: LumiType.button.copyWith(
                      color: step.accent == LumiTokens.yellow
                          ? LumiTokens.ink
                          : LumiTokens.paper,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSkip(BuildContext context) async {
    final shouldSkip = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: LumiTokens.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Skip tour?', style: LumiType.subhead),
        content: Text(
          'This will mark the tour as complete. You can replay it from Settings any time.',
          style: LumiType.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Keep going',
              style: LumiType.body.copyWith(color: LumiTokens.muted),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: LumiTokens.red,
              foregroundColor: LumiTokens.paper,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              ),
            ),
            child: Text(
              'Skip',
              style: LumiType.button.copyWith(color: LumiTokens.paper),
            ),
          ),
        ],
      ),
    );

    if (shouldSkip == true) {
      await controller.complete();
    }
  }

  LumiCharacter _characterForIndex(int index) {
    const characters = LumiCharacters.all;
    return characters[(index * 7) % characters.length];
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({
    required this.count,
    required this.activeIndex,
    required this.color,
  });

  final int count;
  final int activeIndex;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: i == activeIndex ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: i == activeIndex
                  ? color
                  : LumiTokens.rule.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
            ),
          ),
      ],
    );
  }
}
