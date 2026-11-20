import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/profile_lens.dart';
import '../domain/profile_view_mode.dart';

/// What the card is showing right now: which lens, and who is looking.
///
/// Deliberately in memory only. A preview mode is a stance you take for a
/// minute, not a setting somebody should be able to leave switched on by
/// accident — and the Profile tab always opens as the owner.
class ProfileViewState {
  const ProfileViewState({
    this.lens = ProfileLens.story,
    this.mode = ProfileViewMode.owner,
  });

  final ProfileLens lens;
  final ProfileViewMode mode;

  bool get isVisitor => mode.isVisitor;

  ProfileViewState copyWith({ProfileLens? lens, ProfileViewMode? mode}) =>
      ProfileViewState(lens: lens ?? this.lens, mode: mode ?? this.mode);
}

class ProfileViewController extends Notifier<ProfileViewState> {
  @override
  ProfileViewState build() => const ProfileViewState();

  void setLens(ProfileLens lens) {
    if (state.lens == lens) return;
    state = state.copyWith(lens: lens);
  }

  void setMode(ProfileViewMode mode) {
    if (state.mode == mode) return;
    state = state.copyWith(mode: mode);
  }

  void flipMode() => setMode(
    state.isVisitor ? ProfileViewMode.owner : ProfileViewMode.visitor,
  );

  /// Back to how the tab always opens.
  void reset() => state = const ProfileViewState();
}

final profileViewProvider =
    NotifierProvider<ProfileViewController, ProfileViewState>(
      ProfileViewController.new,
    );
