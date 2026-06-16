import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'lumi_tokens.dart';

/// Lumi typography — Nunito ExtraBold for display, Inter (or Helvetica Neue
/// if licensed and bundled) for body. Always use these styles; never
/// construct ad-hoc TextStyles in screens.
class LumiType {
  LumiType._();

  // ─── Display & headings — Nunito ExtraBold (800) ──────────────────
  static TextStyle get displayXL => GoogleFonts.nunito(
    fontSize: 64, fontWeight: FontWeight.w800,
    letterSpacing: -2.56, height: 1.0, color: LumiTokens.ink,
  );

  static TextStyle get displayL => GoogleFonts.nunito(
    fontSize: 44, fontWeight: FontWeight.w800,
    letterSpacing: -0.88, height: 1.05, color: LumiTokens.ink,
  );

  static TextStyle get heading => GoogleFonts.nunito(
    fontSize: 28, fontWeight: FontWeight.w700,
    letterSpacing: -0.28, height: 1.2, color: LumiTokens.ink,
  );

  static TextStyle get subhead => GoogleFonts.nunito(
    fontSize: 20, fontWeight: FontWeight.w700,
    height: 1.3, color: LumiTokens.ink,
  );

  // ─── Body — Inter Light (300) as cross-platform substitute ────────
  // Swap to Helvetica Neue Thin once licensed and bundled.
  static TextStyle get bodyL => GoogleFonts.inter(
    fontSize: 18, fontWeight: FontWeight.w300,
    height: 1.55, color: LumiTokens.ink,
  );

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 16, fontWeight: FontWeight.w300,
    height: 1.55, color: LumiTokens.ink,
  );

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 13, fontWeight: FontWeight.w400,
    height: 1.4, color: LumiTokens.muted,
  );

  // ─── Button text — Nunito 700 ─────────────────────────────────────
  static TextStyle get button => GoogleFonts.nunito(
    fontSize: 16, fontWeight: FontWeight.w700,
    color: LumiTokens.paper,
  );

  // ─── Section labels — uppercase mono ──────────────────────────────
  static TextStyle get sectionLabel => GoogleFonts.jetBrainsMono(
    fontSize: 12, fontWeight: FontWeight.w500,
    letterSpacing: 0.96, color: LumiTokens.muted,
  );

  // ─── Big numbers (streak counter, scores) — Nunito 800 ────────────
  static TextStyle get numberLarge => GoogleFonts.nunito(
    fontSize: 42, fontWeight: FontWeight.w800,
    letterSpacing: -0.84, height: 1.0, color: LumiTokens.ink,
  );
}
