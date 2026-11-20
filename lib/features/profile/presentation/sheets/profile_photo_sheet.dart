import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../auth/application/auth_controller.dart';
import '../../application/photo_studio_controller.dart';
import '../../data/profile_photo_picker.dart';
import '../../domain/profile.dart';
import '../../domain/profile_photo.dart';
import '../widgets/orbit_ring.dart';
import '../widgets/pulse_ui.dart';

/// The photo studio.
///
/// Tapping the avatar raises this, and it does the whole job: pick from the
/// camera or the library, drag and pinch the square you want, then a real
/// 512×512 PNG goes to `avatars/<uid>/` and the card's column is rewritten with
/// its URL. Removing puts the initials back — on the server too.
class ProfilePhotoSheet extends ConsumerStatefulWidget {
  const ProfilePhotoSheet({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<ProfilePhotoSheet> createState() => _ProfilePhotoSheetState();
}

class _ProfilePhotoSheetState extends ConsumerState<ProfilePhotoSheet> {
  final ProfilePhotoPicker _picker = ProfilePhotoPicker();
  bool _picking = false;

  PhotoStudioController get _studio => ref.read(photoStudioProvider.notifier);

  String? get _userId {
    final auth = ref.read(authControllerProvider);
    return auth is AuthSignedIn ? auth.user.id : null;
  }

  @override
  void initState() {
    super.initState();
    // A sheet that opens with the last pick's leftover crop is a trap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _studio.reset();
    });
  }

  Future<void> _pick(PhotoSource source) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picked = source == PhotoSource.camera
          ? await _picker.fromCamera()
          : await _picker.fromGallery();
      if (!mounted || picked == null) return;
      _studio.accept(
        bytes: picked.bytes,
        mimeType: picked.mimeType,
        imageSize: picked.size,
      );
    } catch (_) {
      if (mounted) {
        PulseToast.show(context, 'The picker could not open. Try again.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    final userId = _userId;
    if (userId == null) return;
    final failure = await _studio.save(userId: userId);
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      PulseToast.show(context, 'Photo updated');
    }
  }

  Future<void> _remove() async {
    final userId = _userId;
    if (userId == null) return;
    final failure = await _studio.remove(
      userId: userId,
      existingUrl: widget.profile.avatarUrl,
    );
    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      PulseToast.show(context, 'Back to your initials');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(photoStudioProvider);
    final hasExisting = widget.profile.avatarUrl != null;
    final canSave = state.hasPhoto && !state.busy;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE1DDF0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your photo', style: AppTypography.titleLarge),
                          const SizedBox(height: 3),
                          Text(
                            'Drag to reframe, pinch or slide to zoom. One '
                            'square, so every screen agrees.',
                            style: AppTypography.caption.copyWith(
                              fontSize: 12,
                              height: 1.45,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _Stage(state: state, initials: widget.profile.initials),
                const SizedBox(height: 14),
                if (state.hasPhoto)
                  _ZoomRow(value: state.crop.zoom, onChanged: _studio.zoomTo)
                else
                  Text(
                    hasExisting
                        ? 'Your photo is on the card. Pick a new one to replace '
                              'it, or go back to initials.'
                        : 'No photo yet — your initials stand in until you pick '
                              'one.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption.copyWith(
                      fontSize: 12,
                      height: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SourceButton(
                        icon: Icons.photo_camera_outlined,
                        label: 'Camera',
                        busy: _picking,
                        onTap: () => _pick(PhotoSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SourceButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Gallery',
                        busy: _picking,
                        onTap: () => _pick(PhotoSource.gallery),
                      ),
                    ),
                    if (state.hasPhoto || hasExisting) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SourceButton(
                          icon: Icons.text_fields_rounded,
                          label: 'Initials',
                          busy: state.busy,
                          onTap: state.hasPhoto ? _studio.useInitials : _remove,
                        ),
                      ),
                    ],
                  ],
                ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorLine(message: state.error!),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: canSave ? _save : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand600,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm + 4),
                      ),
                    ),
                    child: state.busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save photo'),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: state.busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 184 px window. What is inside it is exactly what gets uploaded.
class _Stage extends StatelessWidget {
  const _Stage({required this.state, required this.initials});

  final PhotoStudioState state;
  final String initials;

  @override
  Widget build(BuildContext context) {
    const edge = PhotoCrop.window;
    return Center(
      child: SizedBox(
        width: edge + 20,
        height: edge + 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // The comet aperture the card will wear, under the window, so the
            // photo is framed the way it will be seen.
            Positioned.fill(
              child: OrbitRing(
                faceSize: edge,
                spark: false,
                face: const SizedBox.shrink(),
              ),
            ),
            SizedBox(
              width: edge,
              height: edge,
              child: state.hasPhoto
                  ? _Framed(state: state)
                  : _InitialsStage(initials: initials),
            ),
          ],
        ),
      ),
    );
  }
}

class _Framed extends ConsumerWidget {
  const _Framed({required this.state});

  final PhotoStudioState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final image = state.imageSize;
    final cover = PhotoCrop.coverScale(image);
    return GestureDetector(
      onPanUpdate: (details) =>
          ref.read(photoStudioProvider.notifier).panBy(details.delta),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PhotoCrop.window / 2),
        child: ColoredBox(
          color: const Color(0xFF0B0A14),
          child: UnconstrainedBox(
            child: Transform.translate(
              offset: state.crop.offset,
              child: Transform.scale(
                scale: cover * state.crop.zoom,
                child: SizedBox(
                  width: image.width,
                  height: image.height,
                  child: Image.memory(
                    state.bytes!,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InitialsStage extends StatelessWidget {
  const _InitialsStage({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: Center(
        child: Text(
          initials,
          style: AppTypography.displaySmall.copyWith(
            fontSize: 52,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _ZoomRow extends StatelessWidget {
  const _ZoomRow({required this.value, required this.onChanged});

  final double value;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.zoom_out_rounded,
          size: 17,
          color: AppColors.textMuted,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: AppColors.brand500,
              inactiveTrackColor: AppColors.brand100,
              thumbColor: AppColors.brand600,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.clamp(PhotoCrop.minZoom, PhotoCrop.maxZoom),
              min: PhotoCrop.minZoom,
              max: PhotoCrop.maxZoom,
              onChanged: onChanged,
            ),
          ),
        ),
        const Icon(Icons.zoom_in_rounded, size: 17, color: AppColors.textMuted),
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.busy,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(AppRadius.sm + 4),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: AppColors.brand600),
            const SizedBox(height: 5),
            Text(
              label,
              style: AppTypography.caption.copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.brand700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F4),
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        border: Border.all(color: const Color(0xFFFBD5DC)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.caption.copyWith(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
