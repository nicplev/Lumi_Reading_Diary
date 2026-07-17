import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'sms_verification_service.dart';

enum AccountReauthenticationMethod {
  password,
  phone,
  google,
  apple,
  unsupported
}

class AccountReauthenticationProfile {
  const AccountReauthenticationProfile({
    required this.method,
    required this.identifier,
  });

  final AccountReauthenticationMethod method;
  final String identifier;
}

class AccountReauthenticationException implements Exception {
  const AccountReauthenticationException(this.code);

  final String code;

  bool get cancelled => code == 'cancelled';

  @override
  String toString() => code;
}

typedef ReauthenticationCodePrompt = Future<String?> Function(
  String? phoneHint,
  Future<void> Function() resend,
  String? errorMessage,
);

abstract class AccountReauthenticationController {
  Future<AccountReauthenticationProfile> loadProfile();

  Future<void> reauthenticateWithPassword(
    String password,
    ReauthenticationCodePrompt promptForCode,
  );

  Future<void> reauthenticateWithPhone(
    ReauthenticationCodePrompt promptForCode,
  );

  Future<void> reauthenticateWithProvider(
    AccountReauthenticationMethod method,
  );
}

AccountReauthenticationMethod accountReauthenticationMethodForProviders(
  Iterable<String> providerIds,
) {
  final ids = providerIds.toSet();
  if (ids.contains('password')) return AccountReauthenticationMethod.password;
  if (ids.contains('phone')) return AccountReauthenticationMethod.phone;
  if (ids.contains('google.com')) return AccountReauthenticationMethod.google;
  if (ids.contains('apple.com')) return AccountReauthenticationMethod.apple;
  return AccountReauthenticationMethod.unsupported;
}

String accountReauthenticationErrorMessage(
  AccountReauthenticationException error,
) {
  return switch (error.code) {
    'invalid-credential' ||
    'wrong-password' ||
    'invalid-verification-code' =>
      'Those details were not correct. Please try again.',
    'too-many-requests' ||
    'quota-exceeded' =>
      'Too many verification attempts. Please wait before trying again.',
    'network-request-failed' ||
    'rate-limit-unavailable' =>
      'Lumi could not verify you. Check your connection and try again.',
    'user-disabled' =>
      'This account has been disabled. Contact support for help.',
    'session-changed' ||
    'no-current-user' =>
      'Your session changed. Sign in again before deleting your account.',
    'unsupported-provider' =>
      'This sign-in method cannot be verified here yet. Sign out and sign '
          'back in before deleting your account.',
    _ => 'Lumi could not verify you. Please try again.',
  };
}

class FirebaseAccountReauthenticationService
    implements AccountReauthenticationController {
  FirebaseAccountReauthenticationService({
    FirebaseAuth? auth,
    SmsVerificationService? smsService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _smsService = smsService ?? SmsVerificationService();

  final FirebaseAuth _auth;
  final SmsVerificationService _smsService;

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AccountReauthenticationException('no-current-user');
    }
    return user;
  }

  @override
  Future<AccountReauthenticationProfile> loadProfile() async {
    final user = _requireUser();
    final method = accountReauthenticationMethodForProviders(
      user.providerData.map((provider) => provider.providerId),
    );
    final identifier = switch (method) {
      AccountReauthenticationMethod.password => user.email ?? '',
      AccountReauthenticationMethod.phone => user.phoneNumber ?? '',
      AccountReauthenticationMethod.google => user.email ?? 'Google account',
      AccountReauthenticationMethod.apple => user.email ?? 'Apple account',
      AccountReauthenticationMethod.unsupported => '',
    };
    return AccountReauthenticationProfile(
      method: method,
      identifier: identifier,
    );
  }

  @override
  Future<void> reauthenticateWithPassword(
    String password,
    ReauthenticationCodePrompt promptForCode,
  ) async {
    final user = _requireUser();
    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw const AccountReauthenticationException('unsupported-provider');
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: password),
      );
    } on FirebaseAuthMultiFactorException catch (error) {
      await _resolveMfa(error.resolver, promptForCode);
    } on FirebaseAuthException catch (error) {
      throw AccountReauthenticationException(error.code);
    }
    await _refreshTokenFor(user.uid);
  }

  Future<void> _resolveMfa(
    MultiFactorResolver resolver,
    ReauthenticationCodePrompt promptForCode,
  ) async {
    SmsCodeHandle handle;
    try {
      handle = await _smsService.sendLoginCode(resolver: resolver);
    } on FirebaseAuthException catch (error) {
      throw AccountReauthenticationException(error.code);
    }

    PhoneMultiFactorInfo? hint;
    for (final candidate in resolver.hints) {
      if (candidate is PhoneMultiFactorInfo) {
        hint = candidate;
        break;
      }
    }
    String? promptError;
    while (true) {
      final code = await promptForCode(
        hint?.phoneNumber,
        () async {
          try {
            handle = await _smsService.sendLoginCode(
              resolver: resolver,
              forceResendingToken: handle.resendToken,
            );
          } on FirebaseAuthException catch (error) {
            throw AccountReauthenticationException(error.code);
          }
        },
        promptError,
      );
      if (code == null) {
        throw const AccountReauthenticationException('cancelled');
      }
      try {
        await _smsService.resolveLogin(
          resolver: resolver,
          verificationId: handle.verificationId,
          smsCode: code,
        );
        return;
      } on FirebaseAuthException catch (error) {
        if (error.code == 'invalid-verification-code') {
          promptError = accountReauthenticationErrorMessage(
            const AccountReauthenticationException('invalid-verification-code'),
          );
          continue;
        }
        throw AccountReauthenticationException(error.code);
      }
    }
  }

  @override
  Future<void> reauthenticateWithPhone(
    ReauthenticationCodePrompt promptForCode,
  ) async {
    final user = _requireUser();
    final phone = user.phoneNumber?.trim();
    if (phone == null || phone.isEmpty) {
      throw const AccountReauthenticationException('unsupported-provider');
    }
    SmsCodeHandle handle;
    try {
      handle = await _smsService.sendPrimaryPhoneCode(
        phoneNumberE164: phone,
      );
    } on FirebaseAuthException catch (error) {
      throw AccountReauthenticationException(error.code);
    }

    String? promptError;
    while (true) {
      final code = await promptForCode(
        phone,
        () async {
          try {
            handle = await _smsService.sendPrimaryPhoneCode(
              phoneNumberE164: phone,
              forceResendingToken: handle.resendToken,
            );
          } on FirebaseAuthException catch (error) {
            throw AccountReauthenticationException(error.code);
          }
        },
        promptError,
      );
      if (code == null) {
        throw const AccountReauthenticationException('cancelled');
      }
      try {
        final credential = PhoneAuthProvider.credential(
          verificationId: handle.verificationId,
          smsCode: code,
        );
        await _requireSameUser(user.uid)
            .reauthenticateWithCredential(credential);
        break;
      } on FirebaseAuthException catch (error) {
        if (error.code == 'invalid-verification-code') {
          promptError = accountReauthenticationErrorMessage(
            const AccountReauthenticationException('invalid-verification-code'),
          );
          continue;
        }
        throw AccountReauthenticationException(error.code);
      }
    }
    await _refreshTokenFor(user.uid);
  }

  @override
  Future<void> reauthenticateWithProvider(
    AccountReauthenticationMethod method,
  ) async {
    final user = _requireUser();
    final AuthProvider provider = switch (method) {
      AccountReauthenticationMethod.google => GoogleAuthProvider(),
      AccountReauthenticationMethod.apple => AppleAuthProvider(),
      _ => throw const AccountReauthenticationException(
          'unsupported-provider',
        ),
    };
    try {
      if (kIsWeb) {
        await user.reauthenticateWithPopup(provider);
      } else {
        await user.reauthenticateWithProvider(provider);
      }
    } on FirebaseAuthException catch (error) {
      if (const {
        'web-context-cancelled',
        'popup-closed-by-user',
        'cancelled',
        'canceled',
      }.contains(error.code)) {
        throw const AccountReauthenticationException('cancelled');
      }
      throw AccountReauthenticationException(error.code);
    }
    await _refreshTokenFor(user.uid);
  }

  User _requireSameUser(String uid) {
    final current = _requireUser();
    if (current.uid != uid) {
      throw const AccountReauthenticationException('session-changed');
    }
    return current;
  }

  Future<void> _refreshTokenFor(String uid) async {
    try {
      await _requireSameUser(uid).getIdToken(true);
    } on AccountReauthenticationException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AccountReauthenticationException(error.code);
    }
  }
}
