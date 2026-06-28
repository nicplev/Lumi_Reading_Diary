/// Canonical public URLs for Lumi's legal + support pages.
///
/// Single source of truth so every in-app surface (the parent and teacher
/// "About Lumi" dialogs today, anything else later) links to the same hosted
/// pages. The pages live on the school portal (Firebase Hosting). If a custom
/// domain (e.g. lumi-reading.com) is pointed at them later, update only the
/// [_base] below.
class LegalLinks {
  const LegalLinks._();

  static const String _base = 'https://lumi-school-admin-au.web.app';

  static const String privacyPolicy = '$_base/legal/privacy';
  static const String termsOfUse = '$_base/legal/terms';
  static const String support = '$_base/support';
}
