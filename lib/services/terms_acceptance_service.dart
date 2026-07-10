import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/legal_links.dart';
import '../data/models/user_model.dart';
import 'firebase_service.dart';

class TermsAcceptanceService {
  TermsAcceptanceService({
    FirebaseFirestore? firestore,
    FirebaseService? firebaseService,
  })  : _firestore = firestore ?? FirebaseService.instance.firestore,
        _firebaseService = firebaseService ?? FirebaseService.instance;

  final FirebaseFirestore _firestore;
  final FirebaseService _firebaseService;

  static const currentTermsVersion = '2026-07-10';
  static const termsUrl = LegalLinks.termsOfUse;
  static const privacyUrl = LegalLinks.privacyPolicy;

  static bool hasAcceptedCurrentTerms(UserModel user) =>
      user.hasAcceptedTermsVersion(currentTermsVersion);

  Future<void> acceptCurrentTerms(UserModel user) async {
    final authUser = _firebaseService.auth.currentUser;
    if (authUser == null || authUser.uid != user.id) {
      throw StateError('Terms can only be accepted by the signed-in user.');
    }

    final schoolId = user.schoolId?.trim();
    final docRef = schoolId != null && schoolId.isNotEmpty
        ? _firestore
            .collection('schools')
            .doc(schoolId)
            .collection(user.role == UserRole.parent ? 'parents' : 'users')
            .doc(user.id)
        : _firestore.collection('users').doc(user.id);

    await docRef.update({
      'termsAccepted': true,
      'termsAcceptedAt': FieldValue.serverTimestamp(),
      'termsAcceptedVersion': currentTermsVersion,
      'termsAcceptedPlatform': _platformLabel,
    }).timeout(const Duration(seconds: 12));
  }

  static String get _platformLabel {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }
}
