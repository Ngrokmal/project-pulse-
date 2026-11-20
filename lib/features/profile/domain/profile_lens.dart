import 'profile_view_mode.dart';

/// The four lenses on the card rail.
enum ProfileLens {
  story,
  people,
  media,
  settings;

  /// Visitors get "Safety", because the owner-only sections (who sees what,
  /// security, the danger block) are not theirs to configure.
  String label(ProfileViewMode mode) => switch (this) {
    ProfileLens.story => 'Story',
    ProfileLens.people => 'People',
    ProfileLens.media => 'Media',
    ProfileLens.settings => mode.isVisitor ? 'Safety' : 'Settings',
  };

  static ProfileLens parse(String? raw) => switch (raw) {
    'people' => ProfileLens.people,
    'media' => ProfileLens.media,
    'settings' => ProfileLens.settings,
    _ => ProfileLens.story,
  };
}
