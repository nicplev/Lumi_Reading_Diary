import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/firebase_service.dart';
import '../../services/parent_linking_service.dart';
import '../models/student_model.dart';
import '../models/user_model.dart';
import 'user_provider.dart';

/// Parent-side multi-child state.
///
/// A parent can be linked to several children. These providers expose:
///  - [parentChildrenProvider]   — the live list of the parent's children
///  - [activeChildIdProvider]    — which child is "active" (persisted)
///  - [activeChildProvider]      — the resolved active [StudentModel]
///
/// Exactly one child is active at a time; switching it via
/// [ActiveChildController.select] reactively re-scopes every parent screen
/// that watches [activeChildProvider].

/// The [ParentLinkingService], resolved through Riverpod so screens and tests
/// share a single instance (and can override it).
final parentLinkingServiceProvider = Provider<ParentLinkingService>((ref) {
  return ParentLinkingService();
});

/// The app's [FirebaseFirestore], behind a provider so tests can inject a
/// fake. Defaults to the real instance from [firebaseServiceProvider].
final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return ref.watch(firebaseServiceProvider).firestore;
});

/// Streams the signed-in parent's linked children.
///
/// Streams the parent's Firestore document so `linkedChildren` changes — a new
/// in-app link or an unlink — push through live, then loads the matching
/// student docs. [userProvider] alone cannot drive this: it emits once per
/// session and would not see a freshly linked child.
final parentChildrenProvider = StreamProvider<List<StudentModel>>((ref) {
  final userAsync = ref.watch(userProvider);
  final user = userAsync.value;

  // While auth/user is still resolving, stay loading rather than briefly
  // reporting "no children".
  if (user == null) {
    if (userAsync.isLoading) {
      return const Stream<List<StudentModel>>.empty();
    }
    return Stream.value(const <StudentModel>[]);
  }

  final schoolId = user.schoolId;
  if (schoolId == null || user.role != UserRole.parent) {
    return Stream.value(const <StudentModel>[]);
  }

  final schoolRef =
      ref.watch(firestoreProvider).collection('schools').doc(schoolId);

  return schoolRef.collection('parents').doc(user.id).snapshots().asyncMap(
    (parentDoc) async {
      final ids = parentDoc.exists
          ? List<String>.from(
              (parentDoc.data()?['linkedChildren'] as List?) ?? const [])
          : const <String>[];
      if (ids.isEmpty) return const <StudentModel>[];

      final docs = await Future.wait(
        ids.map((id) => schoolRef.collection('students').doc(id).get()),
      );
      final byId = <String, StudentModel>{
        for (final doc in docs)
          if (doc.exists) doc.id: StudentModel.fromFirestore(doc),
      };
      // Preserve linkedChildren order; drop ids whose student doc is missing.
      return [
        for (final id in ids)
          if (byId.containsKey(id)) byId[id]!,
      ];
    },
  );
});

/// Holds the id of the parent's currently-active child.
///
/// Seeded from [SharedPreferences] so the choice survives app restarts, and
/// persisted on every [select]. This holds the raw stored id only — validating
/// it against the live child list is [activeChildProvider]'s job.
class ActiveChildController extends Notifier<String?> {
  /// SharedPreferences key for the persisted active-child id.
  static const prefsKey = 'parent_active_child_id';

  @override
  String? build() {
    _restore();
    return null;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(prefsKey);
    // Only seed when the user has not already made an explicit choice this
    // session — never clobber a tap that happened before prefs resolved.
    if (stored != null && stored.isNotEmpty && state == null) {
      state = stored;
    }
  }

  /// Sets [childId] as the active child and persists the choice.
  Future<void> select(String childId) async {
    if (childId == state) return;
    state = childId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, childId);
  }
}

/// The raw active-child id (or null until restored / first selected).
final activeChildIdProvider =
    NotifierProvider<ActiveChildController, String?>(ActiveChildController.new);

/// The un-logged child ids carried in from a tapped reading reminder, so the
/// app can walk a multi-child parent through logging each one in turn.
///
/// In-memory only: it just needs to survive the log → success → next-child
/// round trip within a session. A cold start (or no reminder tap) leaves it
/// empty, and the home screen's per-child "tonight" card is the standing
/// fallback for seeing who still needs logging.
class PendingReminderChildrenController extends Notifier<List<String>> {
  @override
  List<String> build() => const <String>[];

  /// Seed the queue from a tapped reminder's child ids.
  void setAll(List<String> ids) => state = List.unmodifiable(ids);

  /// Drop a child once it's been logged.
  void remove(String childId) =>
      state = List.unmodifiable(state.where((id) => id != childId));

  void clear() => state = const <String>[];
}

/// Queue of children still to log from a tapped reading reminder. Empty unless
/// a reminder was just tapped. See [PendingReminderChildrenController].
final pendingReminderChildIdsProvider =
    NotifierProvider<PendingReminderChildrenController, List<String>>(
  PendingReminderChildrenController.new,
);

/// The resolved active child, reconciling the stored id against the live list.
///
/// Falls back to the first child when the stored id is missing or no longer
/// linked, so the rest of the app always has a coherent active child. Resolves
/// to null only when the parent has no children. Mirrors the loading/error
/// state of [parentChildrenProvider].
final activeChildProvider = Provider<AsyncValue<StudentModel?>>((ref) {
  final selectedId = ref.watch(activeChildIdProvider);
  return ref.watch(parentChildrenProvider).whenData((children) {
    if (children.isEmpty) return null;
    for (final child in children) {
      if (child.id == selectedId) return child;
    }
    return children.first;
  });
});
