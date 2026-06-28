import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the device's default browser/app.
///
/// Follows the app's established launch pattern (see
/// `lib/screens/auth/web_not_available_screen.dart`) but surfaces a SnackBar
/// when the link can't be opened, so a failure is never silent. The
/// [ScaffoldMessenger] is captured before the await to avoid using
/// [context] across the async gap.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final uri = Uri.parse(url);
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the link. Please try again later.")),
      );
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open the link. Please try again later.")),
    );
  }
}
