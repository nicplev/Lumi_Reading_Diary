class PersistentImageCacheService {
  PersistentImageCacheService._();

  static final PersistentImageCacheService instance =
      PersistentImageCacheService._();

  Future<String?> getCachedFilePath(String imageUrl) async => null;
}
