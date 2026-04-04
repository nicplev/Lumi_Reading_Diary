import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/community_book_service.dart';

final communityBookServiceProvider = Provider<CommunityBookService>((ref) {
  return CommunityBookService();
});
