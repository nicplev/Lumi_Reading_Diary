# Plan: Restrict ISBN scanning to the green reticle (batch + single)

## Context

A teacher reported that the ISBN/barcode scanner detects codes **anywhere in the
full camera view**, not just inside the on-screen green reticle — causing "heaps
of accidental ISBN scans." This affects both teacher scanning flows:

- **Batch scanner** (`isbn_scanner_screen.dart`) — the screenshot. It draws a
  260×180 corner-bracket reticle, but that reticle is **purely cosmetic**: the
  `MobileScanner` has no `scanWindow` and `_onDetect` does no positional check,
  so every barcode in frame is accepted.
- **Single / cover scanner** (`cover_scanner_screen.dart`) — the add-a-book flow.
  It has **no reticle at all** and no `scanWindow`; detection is full-frame.

The **kiosk camera sheet already solves this correctly** and is our reference:
it passes a native `scanWindow` (`mobile_scanner` 7.2.0) computed from a
`LayoutBuilder`, and draws a reticle of the matching size at the same position —
so the ML detector only looks inside the box. We apply that proven pattern to the
two unconstrained scanners.

Intended outcome: on both scanners, only a barcode framed **inside the green
reticle** is scanned; anything elsewhere in the camera view is ignored.

## Approach

Use `mobile_scanner`'s **native `scanWindow`** (platform/ML-enforced), not manual
`barcode.corners` filtering. Rationale: it's the in-repo proven pattern (kiosk),
it restricts detection at the source (efficient, zero out-of-window hits), and it
avoids re-deriving the `BoxFit.cover` widget→texture coordinate math that
`scanWindow` already does internally. The pinned version (`mobile_scanner: 7.2.0`,
`pubspec.lock`) fully supports it (`MobileScanner.scanWindow`,
`MobileScannerController.updateScanWindow`).

Key correctness rule (from the reference): the reticle rectangle and the
`scanWindow` must be **the same rect, computed from the `LayoutBuilder`'s
`constraints.biggest`** (the box the `MobileScanner` fills). The kiosk shares one
size const between its reticle and `kioskCameraScanWindowFor`; we do the same so
the drawn box and the detection window can never drift apart.

## Changes

### 1. Shared reticle widget (extract, don't duplicate)
Move the batch scanner's private `_ReticleOverlay` + `_ReticlePainter`
(`isbn_scanner_screen.dart:1277-1402` — corner brackets + green flash on scan)
into a new shared widget, e.g. **`lib/core/widgets/lumi/scan_reticle.dart`**:
`ScanReticle({required Size size, int flashTick = 0})`. The batch scanner imports
it (identical visual, no change to appearance); the cover scanner reuses it so we
don't copy the painter. Leave the kiosk's own rounded-border reticle
(`_KioskCameraReticle`) as-is — it's visually distinct and already works.

### 2. Batch scanner — `lib/screens/teacher/isbn_scanner_screen.dart`
- Wrap the camera `Stack` (`:672`, inside `Expanded(flex:13)`) in a
  `LayoutBuilder` to get the preview surface size.
- Add a local helper mirroring the kiosk's, but **offset** to match the existing
  `Align(Alignment(0, -0.12))` 260×180 reticle:
  ```
  Rect _isbnScanWindowFor(Size s) => Rect.fromLTWH(
      ((s.width  - 260) / 2).clamp(0, ...),
      (0.44 * (s.height - 180)).clamp(0, ...),   // Alignment.y -0.12 → (1-0.12)/2 = 0.44
      260, 180);
  ```
  (Guard against a surface shorter than the reticle.)
- Pass `scanWindow: rect` to `MobileScanner` (`:675`).
- Replace the two `Align(Alignment(0,-0.12))` overlays (reticle `:690-693`,
  success tick `:694-697`) with `Positioned.fromRect(rect: rect, …)` using that
  **same rect** — single-sourced, so reticle and scan window coincide exactly.
- Update the on-camera hint (`:712`) from *"scan several in one frame"* to
  **"Hold each barcode inside the frame"** (matches the new one-at-a-time
  behaviour; mirrors the kiosk's "Place each book barcode inside the green box").
- **No change to `_onDetect`** (`:174`) — out-of-window barcodes are never
  delivered; existing `normalizeIsbn` validation + dedup are untouched.

### 3. Single / cover scanner — `lib/screens/teacher/cover_scanner_screen.dart`
In `_buildIsbnScanView` (`:1813-1904`):
- Wrap the `Stack` in a `LayoutBuilder`.
- Compute a **centered** rect (no offset needed here):
  `Rect.fromCenter(center: surface.center, width: 260, height: 180)`.
- Pass `scanWindow: rect` to `MobileScanner` (`:1818`).
- Add a `ScanReticle(size: Size(260,180))` positioned at that rect (via
  `Positioned.fromRect`) so the user has a visible target — today there is none.
- Tweak the existing bottom hint (`:1876`) to reference the frame, e.g.
  "Line up the barcode inside the frame."
- **No change to `_onBarcodeDetected`** (`:781`).

### Reuse (no change)
- `IsbnAssignmentService.normalizeIsbn` (`lib/services/isbn_assignment_service.dart:122`)
  — ISBN-10/13 + 978/979 validation, already called by all scanners.
- Reference pattern: `kioskCameraScanWindowFor` +
  `MobileScanner(scanWindow:)` (`kiosk_scan_session_screen.dart:24-29, 987-995`).

### Note on reticle size
Keep 260×180 (what the tester already sees). A hard scan window makes framing
stricter by design — if device testing shows it's too tight for book barcodes, the
size is a one-line tune in the shared helper.

## Verification (physical iOS device — the report is an iPhone)
1. **Batch**: teacher → class → batch scan. A barcode held **outside** the green
   reticle must **not** scan; **inside** must scan (checkmark + haptic + added to
   the list). Probe near all four reticle edges and a busy shelf with several
   spines visible — only the framed one should register.
2. **Single**: teacher → Library → Add book (cover scanner). Confirm the new
   reticle renders and only an in-reticle barcode advances to the metadata step.
3. **Regression**: kiosk camera scan still behaves unchanged.
4. **Test**: add a unit test for `_isbnScanWindowFor` (mirror
   `test/screens/teacher/kiosk_scan_session_screen_test.dart:21`, but assert the
   **offset** rect + size + clamping for a sample surface). Run `flutter analyze`
   and the existing scanner tests clean.
