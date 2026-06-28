import 'package:flutter/material.dart';

import '../../../theme/lumi_tokens.dart';
import '../../../theme/lumi_typography.dart';
import '../../constants/legal_links.dart';
import '../../utils/external_link.dart';

/// The Privacy Policy · Terms of Use · Support links shown in the "About Lumi"
/// dialogs (parent + teacher). Centralised so both surfaces stay in sync and
/// open the same hosted pages. [accent] tints the links to match the host
/// surface — green on the parent dialog, red on the teacher dialog.
class LegalLinksRow extends StatelessWidget {
  final Color accent;

  const LegalLinksRow({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: LumiTokens.space4,
      runSpacing: LumiTokens.space2,
      children: [
        _link(context, 'Privacy Policy', LegalLinks.privacyPolicy),
        _link(context, 'Terms of Use', LegalLinks.termsOfUse),
        _link(context, 'Support', LegalLinks.support),
      ],
    );
  }

  Widget _link(BuildContext context, String label, String url) {
    return GestureDetector(
      onTap: () => openExternalUrl(context, url),
      child: Text(
        label,
        style: LumiType.caption.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
