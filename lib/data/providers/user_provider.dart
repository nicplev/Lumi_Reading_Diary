import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/firebase_service.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return UserRepository();
});

final authStateChangesProvider = StreamProvider<String?>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.authStateChanges.map((user) => user?.uid);
});

final userProvider = StreamProvider<UserModel?>((ref) {
  final uid = ref.watch(authStateChangesProvider).value;
  if (uid != null) {
    final userRepository = ref.read(userRepositoryProvider);
    return userRepository.getUser(uid).asStream();
  }
  return Stream.value(null);
});
