import '../services/dev_access_service.dart';

/// Synchronous check for whether the signed-in user currently has dev access.
///
/// Delegates to [DevAccessService], which maintains an in-memory cache updated
/// on every auth state change. Returns false on a cold start before the first
/// Firestore lookup resolves; callers should treat a `false` result as "not
/// yet known" for the very first frame after sign-in, which in practice is
/// indistinguishable from "not a dev" for the DEV-only surfaces that consume
/// this flag.
///
/// The [email] parameter is accepted for backwards compatibility but is
/// ignored — the service always checks the currently signed-in user.
bool hasDevAccess([String? email]) => DevAccessService.instance.hasAccess;
