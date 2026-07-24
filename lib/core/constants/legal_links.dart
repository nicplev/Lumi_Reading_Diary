/// Canonical public URLs for Lumi's legal + support pages.
///
/// Single source of truth so every in-app surface (the parent and teacher
/// "About Lumi" dialogs today, anything else later) links to the same hosted
/// pages.
///
/// The pages live on the marketing site (lumi-reading.com), which is static
/// Firebase Hosting with no auth in front of it. They previously lived on the
/// school portal, where the auth middleware sent any near-miss path to the
/// admin login. The old portal URLs 308-redirect here permanently — see
/// `school-admin-web/src/middleware.ts` — because builds already on devices
/// have the old origin compiled in.
class LegalLinks {
  const LegalLinks._();

  static const String _base = 'https://lumi-reading.com';

  static const String privacyPolicy = '$_base/legal/privacy';
  static const String termsOfUse = '$_base/legal/terms';
  static const String support = '$_base/support';
}
