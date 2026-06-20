import 'dart:async';
import 'dart:io';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart' show compute, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/models/decodable_grading.dart';
import '../../core/theme/app_theme.dart';
import '../../theme/lumi_tokens.dart';
import '../../theme/lumi_typography.dart';
import '../../data/models/user_model.dart';
import '../../services/book_lookup_service.dart';
import '../../services/community_book_service.dart';
import '../../services/isbn_assignment_service.dart';

class CoverCaptureFailure {
  const CoverCaptureFailure({
    required this.message,
    this.allowRetry = false,
    this.allowOpenSettings = false,
    this.allowCameraFallback = false,
    this.allowGalleryFallback = false,
  });

  final String message;
  final bool allowRetry;
  final bool allowOpenSettings;
  final bool allowCameraFallback;
  final bool allowGalleryFallback;
}

const MethodChannel _singlePageScannerChannel =
    MethodChannel('lumi/single_page_document_scanner');

const CoverCaptureFailure _coverSelectionCancelledFailure = CoverCaptureFailure(
  message:
      'No cover image was selected. You can try the document scanner again, take a standard photo, or choose one from your library.',
  allowRetry: true,
  allowCameraFallback: true,
  allowGalleryFallback: true,
);

@visibleForTesting
bool useDirectIosDocumentScanner(TargetPlatform platform) {
  return platform == TargetPlatform.iOS;
}

@visibleForTesting
CoverCaptureFailure coverCaptureFailureFor({
  required Object error,
  required PermissionStatus cameraStatus,
}) {
  if (cameraStatus == PermissionStatus.permanentlyDenied ||
      cameraStatus == PermissionStatus.restricted) {
    return const CoverCaptureFailure(
      message:
          'Lumi could not confirm camera access for the cover scanner. If Camera is already enabled in Settings, use Take Photo Instead or choose one from your library.',
      allowOpenSettings: true,
      allowCameraFallback: true,
      allowGalleryFallback: true,
    );
  }

  final errorText = error.toString().toLowerCase();
  if (errorText.contains('permission not granted')) {
    return const CoverCaptureFailure(
      message:
          'Camera access is needed to scan a book cover. Allow camera access and try again, or choose one from your library instead.',
      allowRetry: true,
      allowGalleryFallback: true,
    );
  }

  if (error is TimeoutException) {
    return const CoverCaptureFailure(
      message:
          'The document scanner took too long to open. You can try again, take a standard photo, or choose one from your library.',
      allowRetry: true,
      allowCameraFallback: true,
      allowGalleryFallback: true,
    );
  }

  if (error is PlatformException && error.code == 'UNAVAILABLE') {
    return const CoverCaptureFailure(
      message:
          'The document scanner is not available on this device. You can take a standard photo or choose one from your library instead.',
      allowCameraFallback: true,
      allowGalleryFallback: true,
    );
  }

  return const CoverCaptureFailure(
    message:
        'The document scanner could not be opened. You can try again, take a standard photo, or choose one from your library.',
    allowRetry: true,
    allowCameraFallback: true,
    allowGalleryFallback: true,
  );
}

/// Multi-step screen for contributing books to the Community Book Database.
///
/// Entry mode for the community book contribution flow.
enum CommunityBookContributionMode {
  /// Standalone: cover first → ISBN scan → metadata → save → success screen.
  coverFirstStandalone,

  /// Inline from assignment scanner: ISBN already known → cover → metadata → save → pop with result.
  isbnFirstInline,
}

/// Result returned from the contribution flow in [isbnFirstInline] mode.
class CommunityBookContributionResult {
  const CommunityBookContributionResult({
    required this.isbn,
    required this.title,
    this.author,
    this.coverImageUrl,
    this.coverStoragePath,
    this.bookId,
    this.readingLevel,
  });

  final String isbn;
  final String title;
  final String? author;
  final String? coverImageUrl;
  final String? coverStoragePath;
  final String? bookId;
  final String? readingLevel;
}

/// Flow:
/// 1. Scan book cover using device camera with auto-edge detection
/// 2. Scan ISBN barcode
/// 3. Review/edit auto-filled metadata
/// 4. Upload cover + save to community database
class CoverScannerScreen extends StatefulWidget {
  const CoverScannerScreen({
    super.key,
    required this.teacher,
    this.mode = CommunityBookContributionMode.coverFirstStandalone,
    this.preScannedIsbn,
  }) : assert(
          mode == CommunityBookContributionMode.coverFirstStandalone ||
              preScannedIsbn != null,
          'preScannedIsbn is required for isbnFirstInline mode',
        );

  final UserModel teacher;
  final CommunityBookContributionMode mode;
  final String? preScannedIsbn;

  @override
  State<CoverScannerScreen> createState() => _CoverScannerScreenState();
}

enum _ScanStep { coverCapture, coverReview, isbnScan, metadataReview, saving }

class _CoverScannerScreenState extends State<CoverScannerScreen> {
  final CommunityBookService _communityService = CommunityBookService();
  final BookLookupService _lookupService = BookLookupService();
  final ImagePicker _imagePicker = ImagePicker();
  MobileScannerController? _scannerController;

  _ScanStep _currentStep = _ScanStep.coverCapture;
  bool _isOpeningCoverCapture = false;
  CoverCaptureFailure? _coverCaptureFailure;

  // Cover state
  File? _coverImage;
  Uint8List? _coverImageBytes;
  bool _isCropProcessing = false;
  bool _coverWasManuallyCropped = false;
  int _rotationQuarterTurns = 0;
  final _cropController = CropController();

  // ISBN state
  String? _scannedIsbn;
  bool _isProcessingBarcode = false;

  // Metadata state
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _readingLevelController = TextEditingController();
  bool _isLoadingMetadata = false;
  bool _bookAlreadyExists = false;
  bool _isDecodableBook = false;
  bool _applyGrade = false;
  GradingSchemaDefinition? _selectedSchemaDef;
  GradingLevel? _selectedLevel;
  final _customLevelController = TextEditingController();

  // Save state
  bool _isSaving = false;
  String? _saveError;
  bool _saveSuccess = false;

  // Cached school level schema key (fetched once on first save).
  // e.g., 'pmBenchmark', 'aToZ', 'none' — null means not yet fetched.
  String? _schoolLevelSchemaKey;

  bool get _isInlineMode =>
      widget.mode == CommunityBookContributionMode.isbnFirstInline;

  @override
  void initState() {
    super.initState();
    // In inline mode, pre-fill the ISBN so the ISBN scan step is skipped
    if (_isInlineMode && widget.preScannedIsbn != null) {
      _scannedIsbn = widget.preScannedIsbn;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startCoverCapture();
    });
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _titleController.dispose();
    _authorController.dispose();
    _readingLevelController.dispose();
    _customLevelController.dispose();
    super.dispose();
  }

  // ── Step 1: Cover Capture ──────────────────────────────────────────

  Future<void> _startCoverCapture() async {
    await _startDocumentScannerCapture();
  }

  Future<void> _startDocumentScannerCapture() async {
    if (_isOpeningCoverCapture) return;

    setState(() {
      _isOpeningCoverCapture = true;
      _coverCaptureFailure = null;
    });

    try {
      final pictures = await _captureCoverWithDocumentScanner();

      if (!mounted) return;

      if (pictures == null || pictures.isEmpty) {
        setState(() {
          _isOpeningCoverCapture = false;
          _coverCaptureFailure = _coverSelectionCancelledFailure;
        });
        return;
      }

      _applyCoverImage(pictures.first);
    } catch (e, st) {
      if (e is PlatformException) {
        debugPrint(
            '[CoverScanner] capture failed: PlatformException code=${e.code} '
            'message=${e.message} details=${e.details}\n$st');
      } else {
        debugPrint(
            '[CoverScanner] capture failed: type=${e.runtimeType} err=$e\n$st');
      }
      if (!mounted) return;

      final cameraStatus = await Permission.camera.status;
      if (!mounted) return;

      setState(() {
        _isOpeningCoverCapture = false;
        _coverCaptureFailure = coverCaptureFailureFor(
          error: e,
          cameraStatus: cameraStatus,
        );
      });
    }
  }

  Future<List<String>?> _captureCoverWithDocumentScanner() {
    if (useDirectIosDocumentScanner(defaultTargetPlatform)) {
      return _captureCoverWithNativeIosDocumentScanner();
    }

    return _captureCoverWithPluginDocumentScanner();
  }

  Future<List<String>?> _captureCoverWithPluginDocumentScanner() async {
    final permissionStatus = await _ensureCameraPermission();
    if (!_hasGrantedCameraAccess(permissionStatus)) {
      throw Exception('Permission not granted');
    }

    return CunningDocumentScanner.getPictures(
      noOfPages: 1,
      isGalleryImportAllowed: true,
    );
  }

  Future<List<String>?> _captureCoverWithNativeIosDocumentScanner() async {
    debugPrint(
        '[CoverScanner] invoking native scanSinglePage via channel '
        '${_singlePageScannerChannel.name}');
    final List<dynamic>? pictures;
    try {
      pictures = await _singlePageScannerChannel.invokeMethod<List<dynamic>>(
        'scanSinglePage',
        {
          'jpgCompressionQuality': 0.92,
        },
      );
    } on MissingPluginException catch (e) {
      debugPrint(
          '[CoverScanner] native handler not registered on iOS '
          '(MissingPluginException): ${e.message}');
      rethrow;
    } on PlatformException catch (e) {
      debugPrint(
          '[CoverScanner] native invokeMethod failed: code=${e.code} '
          'message=${e.message} details=${e.details}');
      rethrow;
    }

    debugPrint(
        '[CoverScanner] native scanSinglePage returned '
        '${pictures == null ? "null" : "${pictures.length} picture(s)"}');
    return pictures?.map((picture) => picture as String).toList();
  }

  Future<PermissionStatus> _ensureCameraPermission() async {
    final currentStatus = await Permission.camera.status;
    if (_hasGrantedCameraAccess(currentStatus)) {
      return currentStatus;
    }

    return Permission.camera.request();
  }

  bool _hasGrantedCameraAccess(PermissionStatus status) {
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  Future<void> _applyCoverImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    if (!mounted) return;

    setState(() {
      _isOpeningCoverCapture = false;
      _coverCaptureFailure = null;
      _coverImageBytes = bytes;
      _rotationQuarterTurns = 0;
      _coverWasManuallyCropped = false;
      _currentStep = _ScanStep.coverReview;
    });
  }

  Future<void> _pickCoverWithStandardCamera() async {
    final permissionStatus = await _ensureCameraPermission();
    if (!mounted) return;

    if (!_hasGrantedCameraAccess(permissionStatus)) {
      setState(() {
        _isOpeningCoverCapture = false;
        _coverCaptureFailure = coverCaptureFailureFor(
          error: Exception('Permission not granted'),
          cameraStatus: permissionStatus,
        );
      });
      return;
    }

    await _pickCoverImage(
      source: ImageSource.camera,
      onErrorMessage:
          'The camera could not be opened. You can try again, open app settings, or choose one from your library.',
    );
  }

  Future<void> _pickCoverFromLibrary() async {
    await _pickCoverImage(
      source: ImageSource.gallery,
      onErrorMessage:
          'The photo library could not be opened. Please check photo permissions and try again.',
    );
  }

  Future<void> _pickCoverImage({
    required ImageSource source,
    required String onErrorMessage,
  }) async {
    if (_isOpeningCoverCapture) return;

    setState(() {
      _isOpeningCoverCapture = true;
      _coverCaptureFailure = null;
    });

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 92,
      );

      if (!mounted) return;

      if (image == null) {
        setState(() {
          _isOpeningCoverCapture = false;
          _coverCaptureFailure = _coverSelectionCancelledFailure;
        });
        return;
      }

      _applyCoverImage(image.path);
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _isOpeningCoverCapture = false;
        _coverCaptureFailure = CoverCaptureFailure(
          message: onErrorMessage,
          allowRetry: source == ImageSource.camera,
          allowOpenSettings: source == ImageSource.camera,
          allowCameraFallback: false,
          allowGalleryFallback: true,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isOpeningCoverCapture = false;
        _coverCaptureFailure = CoverCaptureFailure(
          message: onErrorMessage,
          allowRetry: source == ImageSource.camera,
          allowOpenSettings: source == ImageSource.camera,
          allowCameraFallback: false,
          allowGalleryFallback: true,
        );
      });
    }
  }

  Future<void> _openCameraSettings() async {
    await openAppSettings();
  }

  // ── Step 1b: Cover Review (Crop & Rotate) ─────────────────────────

  Future<void> _rotateCoverImage() async {
    if (_coverImageBytes == null || _isCropProcessing) return;

    setState(() => _isCropProcessing = true);

    final rotated = await compute(_rotateImage90, _coverImageBytes!);
    if (!mounted) return;

    setState(() {
      _coverImageBytes = rotated;
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
      _isCropProcessing = false;
    });
  }

  static Uint8List _rotateImage90(Uint8List bytes) {
    final image = img.decodeImage(bytes);
    if (image == null) return bytes;
    final rotated = img.copyRotate(image, angle: 90);
    return Uint8List.fromList(img.encodeJpg(rotated, quality: 92));
  }

  void _acceptCover() {
    if (_isCropProcessing) return;
    _cropController.crop();
  }

  Future<void> _onCoverCropped(Uint8List croppedBytes) async {
    setState(() => _isCropProcessing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tempDir.path}/cover_crop_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(croppedBytes, flush: true);

      if (!mounted) return;

      _scannerController?.dispose();

      setState(() {
        _coverImage = tempFile;
        _coverWasManuallyCropped = true;
        _isCropProcessing = false;
        if (_isInlineMode) {
          // ISBN already known — skip barcode scan, go straight to metadata
          _currentStep = _ScanStep.metadataReview;
        } else {
          _currentStep = _ScanStep.isbnScan;
          _scannerController = MobileScannerController();
        }
      });

      // In inline mode, load metadata now (the ISBN is already set)
      if (_isInlineMode && _scannedIsbn != null) {
        _loadMetadata(_scannedIsbn!);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCropProcessing = false);
      _showError('Failed to process cropped image. Please try again.');
    }
  }

  void _retakeCover() {
    setState(() {
      _coverImageBytes = null;
      _coverImage = null;
      _rotationQuarterTurns = 0;
      _coverWasManuallyCropped = false;
      _currentStep = _ScanStep.coverCapture;
    });
    _startCoverCapture();
  }

  // ── Step 2: ISBN Barcode Scan ──────────────────────────────────────

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_isProcessingBarcode) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null) continue;

      final normalized = IsbnAssignmentService.normalizeIsbn(rawValue);
      if (normalized == null) continue;

      setState(() {
        _isProcessingBarcode = true;
        _scannedIsbn = normalized;
      });

      _scannerController?.stop();
      _loadMetadata(normalized);
      return;
    }
  }

  void _onManualIsbnEntry() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusLarge),
        ),
        title: Text('Enter ISBN', style: LumiType.subhead),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          cursorColor: LumiTokens.ink,
          decoration: InputDecoration(
            hintText: 'e.g. 9781234567890',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              borderSide: BorderSide(color: LumiTokens.rule),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
              borderSide:
                  const BorderSide(color: LumiTokens.yellow, width: 2),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: LumiTokens.yellow,
              foregroundColor: LumiTokens.ink,
            ),
            onPressed: () {
              final isbn = IsbnAssignmentService.normalizeIsbn(controller.text);
              if (isbn == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Invalid ISBN')),
                );
                return;
              }
              Navigator.of(ctx).pop();
              setState(() {
                _isProcessingBarcode = true;
                _scannedIsbn = isbn;
              });
              _scannerController?.stop();
              _loadMetadata(isbn);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // ── Step 3: Load & Review Metadata ─────────────────────────────────

  Future<void> _loadMetadata(String isbn) async {
    setState(() {
      _isLoadingMetadata = true;
      _currentStep = _ScanStep.metadataReview;
    });

    // Check if already in community database.
    final existing = await _communityService.lookupByIsbn(isbn);
    if (existing != null) {
      setState(() {
        _bookAlreadyExists = true;
        _titleController.text = existing.title;
        _authorController.text = existing.author ?? '';
        _readingLevelController.text = existing.readingLevel ?? '';
        _isLoadingMetadata = false;
      });
      return;
    }

    // Try the full lookup chain for auto-fill.
    final result = await _lookupService.lookupByIsbn(
      isbn: isbn,
      schoolId: widget.teacher.schoolId ?? '',
      actorId: widget.teacher.id,
    );

    if (!mounted) return;

    setState(() {
      if (result != null) {
        _titleController.text = result.title;
        _authorController.text = result.author ?? '';
        _readingLevelController.text = result.readingLevel ?? '';
      }
      _isLoadingMetadata = false;
    });
  }

  // ── Step 4: Save ──────────────────────────────────────────────────

  Future<void> _saveBook() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showError('Title is required.');
      return;
    }
    if (_scannedIsbn == null) return;

    setState(() {
      _isSaving = true;
      _saveError = null;
      _currentStep = _ScanStep.saving;
    });

    try {
      // Upload cover image.
      String? coverUrl;
      String? coverPath;
      if (_coverImage != null) {
        coverUrl = await _communityService.uploadCoverImage(
          isbn: _scannedIsbn!,
          imageFile: _coverImage!,
        );
        if (coverUrl != null) {
          coverPath = _communityService.coverStoragePath(_scannedIsbn!);
        } else if (_bookAlreadyExists && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Cover image could not be updated. Metadata was saved.'),
            ),
          );
        }
      }

      String? resolvedReadingLevel;
      if (_isDecodableBook && _applyGrade) {
        if (_selectedSchemaDef?.schema == GradingSchema.custom) {
          final custom = _customLevelController.text.trim();
          resolvedReadingLevel = custom.isNotEmpty ? custom : null;
        } else {
          resolvedReadingLevel = _selectedLevel?.value;
        }
      } else if (!_isDecodableBook) {
        final raw = _readingLevelController.text.trim();
        resolvedReadingLevel = raw.isNotEmpty ? raw : null;
      }

      // Resolve the level schema key for community provenance.
      // For decodable books, use the grading schema's metadata key.
      // For library books, use the school's reading level schema.
      String? resolvedLevelSchema;
      if (_isDecodableBook && _applyGrade && _selectedSchemaDef != null) {
        resolvedLevelSchema = _selectedSchemaDef!.metadataKey;
      } else if (!_isDecodableBook && resolvedReadingLevel != null) {
        // Lazily fetch and cache the school's level schema key.
        _schoolLevelSchemaKey ??= await _fetchSchoolLevelSchemaKey();
        if (_schoolLevelSchemaKey != 'none') {
          resolvedLevelSchema = _schoolLevelSchemaKey;
        }
      }

      // Save book to community database.
      await _communityService.addBook(
        isbn: _scannedIsbn!,
        title: title,
        contributorId: widget.teacher.id,
        contributorSchoolId: widget.teacher.schoolId ?? '',
        contributorName: widget.teacher.fullName,
        author: _authorController.text.trim().isNotEmpty
            ? _authorController.text.trim()
            : null,
        coverImageUrl: coverUrl,
        coverStoragePath: coverPath,
        readingLevel: resolvedReadingLevel,
        levelSchema: resolvedLevelSchema,
        source: 'teacher_scan',
        metadata: {
          'coverSource': coverUrl != null ? 'camera_scan' : null,
          'hasCameraScannedCover': coverUrl != null,
          'coverWasManuallyCropped': _coverWasManuallyCropped,
          'coverWasRotated': _rotationQuarterTurns > 0,
          if (_isDecodableBook) 'isDecodable': true,
          if (_isDecodableBook &&
              _applyGrade &&
              _selectedSchemaDef != null &&
              _selectedSchemaDef!.schema != GradingSchema.custom)
            'gradingSchema': _selectedSchemaDef!.metadataKey,
        },
      );

      if (!mounted) return;

      if (_isInlineMode) {
        // Return structured result to the calling scanner screen
        Navigator.of(context).pop(CommunityBookContributionResult(
          isbn: _scannedIsbn!,
          title: title,
          author: _authorController.text.trim().isNotEmpty
              ? _authorController.text.trim()
              : null,
          coverImageUrl: coverUrl,
          coverStoragePath: coverPath,
          bookId: 'isbn_${_scannedIsbn!}',
          readingLevel: resolvedReadingLevel,
        ));
      } else {
        setState(() {
          _isSaving = false;
          _saveSuccess = true;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = 'Failed to save book. Please try again.';
        _currentStep = _ScanStep.metadataReview;
      });
    }
  }

  /// Fetches the school's reading level schema key from Firestore.
  /// Returns 'none' if the school has no levels configured or on error.
  Future<String> _fetchSchoolLevelSchemaKey() async {
    final schoolId = widget.teacher.schoolId;
    if (schoolId == null || schoolId.isEmpty) return 'none';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(schoolId)
          .get();
      return (doc.data()?['levelSchema'] as String?) ?? 'none';
    } catch (_) {
      return 'none';
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _scanAnother() {
    _scannerController?.dispose();
    _scannerController = null;

    setState(() {
      _coverImage = null;
      _coverImageBytes = null;
      _rotationQuarterTurns = 0;
      _coverWasManuallyCropped = false;
      _isCropProcessing = false;
      _scannedIsbn = null;
      _isOpeningCoverCapture = false;
      _coverCaptureFailure = null;
      _isProcessingBarcode = false;
      _titleController.clear();
      _authorController.clear();
      _readingLevelController.clear();
      _isLoadingMetadata = false;
      _bookAlreadyExists = false;
      _isDecodableBook = false;
      _applyGrade = false;
      _selectedSchemaDef = null;
      _selectedLevel = null;
      _customLevelController.clear();
      _isSaving = false;
      _saveError = null;
      _saveSuccess = false;
      _currentStep = _ScanStep.coverCapture;
    });
    _startCoverCapture();
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep == _ScanStep.coverCapture,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        switch (_currentStep) {
          case _ScanStep.coverReview:
            _retakeCover();
          case _ScanStep.isbnScan:
            _scannerController?.dispose();
            _scannerController = null;
            setState(() => _currentStep = _ScanStep.coverReview);
          case _ScanStep.metadataReview:
            if (_isInlineMode) {
              // In inline mode, back goes to cover review (ISBN is fixed)
              setState(() => _currentStep = _ScanStep.coverReview);
            } else {
              setState(() {
                _scannedIsbn = null;
                _isProcessingBarcode = false;
                _currentStep = _ScanStep.isbnScan;
                _scannerController = MobileScannerController();
              });
            }
          case _ScanStep.saving:
            break;
          case _ScanStep.coverCapture:
            break;
        }
      },
      child: Theme(
        data: AppTheme.teacherTheme(),
        child: Scaffold(
          backgroundColor: _currentStep == _ScanStep.isbnScan
              ? Colors.black
              : LumiTokens.cream,
          appBar: _buildAppBar(),
          body: _saveSuccess ? _buildSuccessView() : _buildStepView(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final stepLabel = switch (_currentStep) {
      _ScanStep.coverCapture => 'Scan Cover',
      _ScanStep.coverReview => 'Adjust Cover',
      _ScanStep.isbnScan => 'Scan ISBN',
      _ScanStep.metadataReview => 'Review Details',
      _ScanStep.saving => 'Saving...',
    };

    return AppBar(
      title: Text(
        _saveSuccess ? 'Done!' : stepLabel,
        style: LumiType.subhead.copyWith(
          color: _currentStep == _ScanStep.isbnScan
              ? Colors.white
              : LumiTokens.ink,
        ),
      ),
      backgroundColor: _currentStep == _ScanStep.isbnScan
          ? Colors.black
          : LumiTokens.cream,
      foregroundColor: _currentStep == _ScanStep.isbnScan
          ? Colors.white
          : LumiTokens.ink,
      elevation: 0,
    );
  }

  Widget _buildStepView() {
    return switch (_currentStep) {
      _ScanStep.coverCapture => _buildCoverCaptureView(),
      _ScanStep.coverReview => _buildCoverReviewView(),
      _ScanStep.isbnScan => _buildIsbnScanView(),
      _ScanStep.metadataReview => _buildMetadataReviewView(),
      _ScanStep.saving => _buildSavingView(),
    };
  }

  // ── Cover Capture View ────────────────────────────────────────────

  Widget _buildCoverCaptureView() {
    if (_coverCaptureFailure == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: LumiTokens.yellow),
            const SizedBox(height: 16),
            Text('Opening cover scanner...', style: LumiType.body),
          ],
        ),
      );
    }

    final failure = _coverCaptureFailure!;
    final filledYellow = FilledButton.styleFrom(
      backgroundColor: LumiTokens.yellow,
      foregroundColor: LumiTokens.ink,
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
      ),
      textStyle: LumiType.button.copyWith(color: LumiTokens.ink),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: LumiTokens.yellow.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.document_scanner_rounded,
                  size: 36,
                  color: LumiTokens.yellow,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Cover Capture Unavailable',
                style: LumiType.subhead,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                failure.message,
                style: LumiType.body.copyWith(color: LumiTokens.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (failure.allowRetry)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _isOpeningCoverCapture ? null : _startCoverCapture,
                    style: filledYellow,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Document Scanner Again'),
                  ),
                ),
              if (failure.allowOpenSettings) ...[
                if (failure.allowRetry) const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _openCameraSettings,
                    style: filledYellow,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open App Settings'),
                  ),
                ),
              ],
              if (failure.allowCameraFallback) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isOpeningCoverCapture
                        ? null
                        : _pickCoverWithStandardCamera,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(
                          color: LumiTokens.yellow, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusPill),
                      ),
                      textStyle: LumiType.button.copyWith(color: LumiTokens.ink),
                    ),
                    icon: const Icon(Icons.camera_alt_outlined,
                        color: LumiTokens.yellow),
                    label: const Text('Take Photo Instead'),
                  ),
                ),
              ],
              if (failure.allowGalleryFallback) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed:
                        _isOpeningCoverCapture ? null : _pickCoverFromLibrary,
                    style: TextButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                      minimumSize: const Size.fromHeight(44),
                      textStyle: LumiType.button.copyWith(color: LumiTokens.ink),
                    ),
                    icon: const Icon(Icons.photo_library_outlined,
                        color: LumiTokens.yellow),
                    label: const Text('Choose From Library'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Cover Review View ──────────────────────────────────────────────

  Widget _buildCoverReviewView() {
    if (_coverImageBytes == null) {
      return const Center(
        child: CircularProgressIndicator(color: LumiTokens.yellow),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            // Crop widget
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Crop(
                  image: _coverImageBytes!,
                  controller: _cropController,
                  withCircleUi: false,
                  initialSize: 0.9,
                  baseColor: LumiTokens.cream,
                  maskColor: Colors.black54,
                  onCropped: _onCoverCropped,
                ),
              ),
            ),

            // Bottom action bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              decoration: BoxDecoration(
                color: LumiTokens.paper,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Retake
                  TextButton.icon(
                    onPressed: _isCropProcessing ? null : _retakeCover,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Retake'),
                    style: TextButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Rotate
                  IconButton(
                    onPressed: _isCropProcessing ? null : _rotateCoverImage,
                    icon: const Icon(Icons.rotate_right_rounded),
                    tooltip: 'Rotate 90°',
                    style: IconButton.styleFrom(
                      foregroundColor: LumiTokens.ink,
                    ),
                  ),

                  const Spacer(),

                  // Accept
                  FilledButton.icon(
                    onPressed: _isCropProcessing ? null : _acceptCover,
                    style: FilledButton.styleFrom(
                      backgroundColor: LumiTokens.yellow,
                      foregroundColor: LumiTokens.ink,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(LumiTokens.radiusMedium),
                      ),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use This Cover'),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Loading overlay
        if (_isCropProcessing)
          Positioned.fill(
            child: Container(
              color: Colors.black26,
              child: const Center(
                child:
                    CircularProgressIndicator(color: LumiTokens.yellow),
              ),
            ),
          ),
      ],
    );
  }

  // ── ISBN Scan View ────────────────────────────────────────────────

  Widget _buildIsbnScanView() {
    return Stack(
      children: [
        // Camera
        if (_scannerController != null)
          MobileScanner(
            controller: _scannerController!,
            onDetect: _onBarcodeDetected,
          ),

        // Cover thumbnail in top-left corner
        if (_coverImage != null)
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              width: 80,
              height: 110,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(_coverImage!, fit: BoxFit.cover),
              ),
            ),
          ),

        // Scanning overlay
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.85),
                  Colors.transparent,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white70,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  'Point camera at the ISBN barcode',
                  style: LumiType.bodyL.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Usually found on the back cover',
                  style: LumiType.caption.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: _onManualIsbnEntry,
                  icon: const Icon(Icons.keyboard, color: Colors.white70),
                  label: const Text(
                    'Enter ISBN manually',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Metadata Review View ──────────────────────────────────────────

  Widget _buildMetadataReviewView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover preview + ISBN badge
          Center(
            child: Column(
              children: [
                if (_coverImage != null)
                  Container(
                    width: 140,
                    height: 200,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: LumiTokens.shadowCard,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_coverImage!, fit: BoxFit.cover),
                    ),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: LumiTokens.yellow.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'ISBN: ${_scannedIsbn ?? ""}',
                    style: LumiType.caption.copyWith(
                      color: LumiTokens.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Existing book banner
          if (_bookAlreadyExists) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LumiTokens.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: LumiTokens.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: LumiTokens.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This book already exists in the community database. '
                      'You can update its cover image.',
                      style: LumiType.caption.copyWith(
                        color: LumiTokens.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_isLoadingMetadata)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: LumiTokens.yellow),
                    const SizedBox(height: 12),
                    Text('Looking up book details...',
                        style: LumiType.body),
                  ],
                ),
              ),
            )
          else ...[
            // Form fields
            _buildTextField(
              label: 'Title *',
              controller: _titleController,
              icon: Icons.menu_book_rounded,
            ),
            const SizedBox(height: 16),
            _buildTextField(
              label: 'Author',
              controller: _authorController,
              icon: Icons.person_outline,
            ),
            const SizedBox(height: 16),
            _buildBookTypeToggle(),
            const SizedBox(height: 16),
            if (_isDecodableBook)
              _buildGradeSection()
            else
              _buildTextField(
                label: 'Reading Level',
                controller: _readingLevelController,
                icon: Icons.trending_up_rounded,
                hint: 'e.g. A, B, 1, 2',
              ),

            if (_saveError != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: LumiTokens.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: LumiTokens.red.withValues(alpha: 0.3)),
                ),
                child: Text(
                  _saveError!,
                  style: LumiType.caption.copyWith(
                    color: LumiTokens.red,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveBook,
                style: FilledButton.styleFrom(
                  backgroundColor: LumiTokens.yellow,
                  foregroundColor: LumiTokens.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                ),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  _bookAlreadyExists
                      ? 'Update Community Database'
                      : 'Save to Community Database',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBookTypeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Book Type',
          style: LumiType.caption.copyWith(
            color: LumiTokens.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _BookTypeChip(
                label: 'Library',
                icon: Icons.local_library_outlined,
                selected: !_isDecodableBook,
                onTap: () => setState(() {
                  _isDecodableBook = false;
                  _applyGrade = false;
                  _selectedSchemaDef = null;
                  _selectedLevel = null;
                  _customLevelController.clear();
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BookTypeChip(
                label: 'Decodable',
                icon: Icons.auto_stories_outlined,
                selected: _isDecodableBook,
                onTap: () => setState(() {
                  _isDecodableBook = true;
                }),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Grading section (shown when book is marked Decodable) ─────────────────

  Widget _buildGradeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildApplyGradeToggle(),
        if (_applyGrade) ...[
          const SizedBox(height: 16),
          _buildSchemaSelector(),
          if (_selectedSchemaDef != null) ...[
            const SizedBox(height: 8),
            // Description banner for selected schema
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: LumiTokens.yellow.withValues(alpha: 0.14),
                borderRadius:
                    BorderRadius.circular(LumiTokens.radiusSmall),
              ),
              child: Text(
                _selectedSchemaDef!.description,
                style: LumiType.caption
                    .copyWith(color: LumiTokens.ink),
              ),
            ),
            const SizedBox(height: 12),
            _buildLevelSelector(),
          ],
        ],
      ],
    );
  }

  Widget _buildApplyGradeToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reading grade (optional)',
          style: LumiType.caption.copyWith(
            color: LumiTokens.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _BookTypeChip(
                label: 'No grade',
                icon: Icons.remove_circle_outline,
                selected: !_applyGrade,
                onTap: () => setState(() {
                  _applyGrade = false;
                  _selectedSchemaDef = null;
                  _selectedLevel = null;
                  _customLevelController.clear();
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BookTypeChip(
                label: 'Add grade',
                icon: Icons.grade_outlined,
                selected: _applyGrade,
                onTap: () => setState(() => _applyGrade = true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSchemaSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Grading system',
          style: LumiType.caption.copyWith(
            color: LumiTokens.muted,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: gradingSchemas.map((def) {
              final isSelected =
                  _selectedSchemaDef?.schema == def.schema;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SchemaChip(
                  schemaDef: def,
                  selected: isSelected,
                  onTap: () => setState(() {
                    _selectedSchemaDef = def;
                    _selectedLevel = null;
                    _customLevelController.clear();
                  }),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildLevelSelector() {
    final def = _selectedSchemaDef!;

    if (def.schema == GradingSchema.custom) {
      return _buildCustomLevelField();
    }

    if (def.schema == GradingSchema.readingDoctor) {
      return _buildReadingDoctorChips(def);
    }

    return _buildLevelChipWrap(def.levels);
  }

  Widget _buildLevelChipWrap(List<GradingLevel> levels) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: levels.map((level) {
        return _LevelChip(
          level: level,
          selected: _selectedLevel?.value == level.value,
          onTap: () => setState(() => _selectedLevel = level),
        );
      }).toList(),
    );
  }

  Widget _buildReadingDoctorChips(GradingSchemaDefinition def) {
    final part1 = def.levels.where((l) => l.sortKey < 20).toList();
    final part2 = def.levels.where((l) => l.sortKey >= 20).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupLabel('Part I — Basic Code'),
        const SizedBox(height: 6),
        _buildLevelChipWrap(part1),
        const SizedBox(height: 12),
        _buildGroupLabel('Part II — Intermediate Code'),
        const SizedBox(height: 6),
        _buildLevelChipWrap(part2),
      ],
    );
  }

  Widget _buildGroupLabel(String label) {
    return Text(
      label,
      style: LumiType.caption.copyWith(
        color: LumiTokens.muted,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildCustomLevelField() {
    return TextField(
      controller: _customLevelController,
      cursorColor: LumiTokens.ink,
      decoration: InputDecoration(
        labelText: 'Grade label',
        hintText: 'e.g. Set 3, Unit 12, Phase 5',
        prefixIcon: Icon(Icons.edit_outlined,
            color: LumiTokens.muted, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: BorderSide(color: LumiTokens.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: BorderSide(color: LumiTokens.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide:
              const BorderSide(color: LumiTokens.yellow, width: 2),
        ),
        filled: true,
        fillColor: LumiTokens.paper,
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      cursorColor: LumiTokens.ink,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: LumiTokens.muted, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: BorderSide(color: LumiTokens.rule),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide: BorderSide(color: LumiTokens.rule),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          borderSide:
              const BorderSide(color: LumiTokens.yellow, width: 2),
        ),
        filled: true,
        fillColor: LumiTokens.paper,
      ),
    );
  }

  // ── Saving View ───────────────────────────────────────────────────

  Widget _buildSavingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: LumiTokens.yellow),
          const SizedBox(height: 20),
          Text('Uploading cover and saving...', style: LumiType.subhead),
          const SizedBox(height: 8),
          Text(
            'This may take a moment',
            style: LumiType.body,
          ),
        ],
      ),
    );
  }

  // ── Success View ──────────────────────────────────────────────────

  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: LumiTokens.green.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 48,
                color: LumiTokens.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _bookAlreadyExists ? 'Book Updated!' : 'Book Added!',
              style: LumiType.heading,
            ),
            const SizedBox(height: 8),
            Text(
              _titleController.text,
              style: LumiType.bodyL.copyWith(
                color: LumiTokens.muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This book is now available to all teachers\nacross the Lumi community.',
              style: LumiType.body.copyWith(
                color: LumiTokens.muted,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _scanAnother,
                style: FilledButton.styleFrom(
                  backgroundColor: LumiTokens.yellow,
                  foregroundColor: LumiTokens.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                ),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text(
                  'Scan Another Book',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: LumiTokens.ink),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(LumiTokens.radiusMedium),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: LumiTokens.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Schema chip (horizontal schema selector) ──────────────────────────────────

class _SchemaChip extends StatelessWidget {
  const _SchemaChip({
    required this.schemaDef,
    required this.selected,
    required this.onTap,
  });

  final GradingSchemaDefinition schemaDef;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? LumiTokens.yellow : LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusPill),
          border: Border.all(
            color:
                selected ? LumiTokens.yellow : LumiTokens.rule,
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          schemaDef.displayName,
          style: TextStyle(
            fontSize: 13,
            fontWeight:
                selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? LumiTokens.ink : LumiTokens.muted,
          ),
        ),
      ),
    );
  }
}

// ── Level chip (individual level within a schema) ─────────────────────────────

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final GradingLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasSublabel = level.sublabel != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: hasSublabel ? 8 : 11,
        ),
        decoration: BoxDecoration(
          color: selected ? LumiTokens.yellow : LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusSmall),
          border: Border.all(
            color:
                selected ? LumiTokens.yellow : LumiTokens.rule,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              level.display,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? LumiTokens.ink : LumiTokens.muted,
                height: 1.1,
              ),
            ),
            if (hasSublabel) ...[
              const SizedBox(height: 3),
              Text(
                level.sublabel!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color:
                      selected ? LumiTokens.charcoal : LumiTokens.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Book type chip (Library / Decodable toggle) ───────────────────────────────

class _BookTypeChip extends StatelessWidget {
  const _BookTypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? LumiTokens.yellow : LumiTokens.paper,
          borderRadius: BorderRadius.circular(LumiTokens.radiusMedium),
          border: Border.all(
            color: selected ? LumiTokens.yellow : LumiTokens.rule,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? LumiTokens.ink : LumiTokens.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? LumiTokens.ink : LumiTokens.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
