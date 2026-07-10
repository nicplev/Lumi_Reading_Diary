import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/lumi/lumi_toast.dart';

/// Opens [url] in the device's default browser/app.
///
/// Follows the app's established launch pattern (see
/// `lib/screens/auth/web_not_available_screen.dart`) but surfaces a toast
/// when the link can't be opened, so a failure is never silent.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final uri = Uri.parse(url);
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      showLumiToast(
        message: "Couldn't open the link. Please try again later.",
        type: LumiToastType.error,
      );
    }
  } catch (_) {
    showLumiToast(
      message: "Couldn't open the link. Please try again later.",
      type: LumiToastType.error,
    );
  }
}
