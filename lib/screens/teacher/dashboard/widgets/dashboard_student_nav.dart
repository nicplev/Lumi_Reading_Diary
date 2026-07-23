import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../data/models/class_model.dart';
import '../../../../data/models/student_model.dart';
import '../../../../data/models/user_model.dart';
import '../../../../theme/lumi_tokens.dart';

/// Routes to a student's detail page from a dashboard card. Every dashboard card
/// that lists students uses this so the behaviour and payload stay identical
/// (matching Recent Reading and Needs Attention).
void pushStudentDetail(
  BuildContext context, {
  required UserModel teacher,
  required StudentModel student,
  required ClassModel classModel,
}) {
  context.push(
    '/teacher/student-detail/${student.id}',
    extra: {
      'teacher': teacher,
      'student': student,
      'classModel': classModel,
    },
  );
}

/// The standard "row is tappable" affordance for dashboard cards: a subtle
/// muted chevron, placed as the final trailing element of a row.
class DashboardRowChevron extends StatelessWidget {
  const DashboardRowChevron({super.key});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: LumiTokens.muted.withValues(alpha: 0.5),
    );
  }
}
