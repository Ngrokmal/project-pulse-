import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../media/application/media_controller.dart';
import '../../domain/inbox_palette.dart';

/// Real upload progress above the composer. It slides in with the first byte and
/// out when the upload finishes — the composer itself is never blocked by it.
class UploadProgressBar extends ConsumerWidget {
  const UploadProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(mediaUploadProvider);
    final visible = upload != null;
    final progress = upload?.progress.clamp(0.0, 1.0) ?? 0.0;
    final percent = (progress * 100).round();

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 14,
                        color: InboxPalette.brand600,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Uploading ${upload.fileName} — $percent%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: InboxPalette.brand100,
                      valueColor: const AlwaysStoppedAnimation(
                        InboxPalette.brand600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
