import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/local_db.dart';
import 'user_profile.dart';

class ProfileController extends StateNotifier<UserProfile?> {
  ProfileController() : super(_load());

  static const String _key = 'me';

  static UserProfile? _load() {
    final json = LocalDb.readJson(LocalDb.profile, _key);
    return json == null ? null : UserProfile.fromJson(json);
  }

  Future<void> save(UserProfile profile) async {
    await LocalDb.writeJson(LocalDb.profile, _key, profile.toJson());
    state = profile;
  }

  void clear() => state = null;
}

final profileProvider =
    StateNotifierProvider<ProfileController, UserProfile?>(
  (ref) => ProfileController(),
);
