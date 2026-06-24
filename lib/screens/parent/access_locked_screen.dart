import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/lumi_spacing.dart';
import '../../core/widgets/lumi/lumi_buttons.dart';
import '../../data/models/student_model.dart';
import '../../data/providers/access_provider.dart';

/// Fail-closed gate shown when a child's access has lapsed or the whole school
/// is suspended. Reached from the `/parent/log-reading` route guard (the
/// security rules are the hard backstop; this is the friendly explanation).
///
/// The message is resolved live from [schoolByIdProvider] so a whole-school
/// suspension reads "contact Lumi" while a per-child lapse reads "contact your
/// school" — pointing the family at whoever can actually restore access.
class AccessLockedScreen extends ConsumerWidget {
  final StudentModel student;

  const AccessLockedScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final school = ref.watch(schoolByIdProvider(student.schoolId)).value;
    final reason = gateReasonFor(student, school);

    final bool schoolSuspended =
        reason == AccessGateReason.schoolSuspended;

    final String title = schoolSuspended
        ? 'Reading is paused for your school'
        : "${student.firstName}'s access has lapsed";

    final String body = schoolSuspended
        ? "Your school's Lumi subscription is currently inactive, so reading "
            'logs are paused for everyone. Please contact Lumi to restore '
            'access.'
        : "${student.firstName} isn't set up for the current school year yet. "
            'Reading logs are paused until your school renews their place. '
            'Please contact your school office.';

    return Scaffold(
      backgroundColor: AppColors.offWhite,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          color: AppColors.charcoal,
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/parent/home'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(LumiSpacing.l),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    schoolSuspended
                        ? Icons.lock_clock_outlined
                        : Icons.lock_outline,
                    size: 72,
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: LumiSpacing.l),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(
                          color: AppColors.charcoal,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: LumiSpacing.m),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                  ),
                  const SizedBox(height: LumiSpacing.xl),
                  LumiPrimaryButton(
                    text: 'Back to home',
                    isFullWidth: true,
                    onPressed: () => context.go('/parent/home'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
