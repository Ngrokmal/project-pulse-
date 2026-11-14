import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/call_controller.dart';
import '../domain/call_session.dart';

/// Full-screen call UI. It never invents a state: the label is the machine's,
/// and "Connected" only appears once both the row and the media layer agree.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.callId});

  final String callId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    // The row may already be ringing when this screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = ref.read(callControllerProvider(widget.callId)).value;
      if (session?.state == CallState.connecting) {
        ref.read(callControllerProvider(widget.callId).notifier).mediaReady();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(callControllerProvider(widget.callId));
    final controller = ref.read(callControllerProvider(widget.callId).notifier);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _ErrorBody(onClose: _close),
          data: (session) {
            if (session == null) return _ErrorBody(onClose: _close);
            final live = session.state.isLive;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                children: [
                  const Spacer(),
                  CircleAvatar(
                    radius: 56,
                    backgroundColor: AppColors.brand600.withValues(alpha: 0.14),
                    child: Text(
                      session.peerName.isEmpty
                          ? '?'
                          : session.peerName.substring(0, 1).toUpperCase(),
                      style: AppTypography.headlineMedium.copyWith(
                        color: AppColors.brand600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(session.peerName, style: AppTypography.titleLarge),
                  const SizedBox(height: 6),
                  Text(
                    session.kind == CallKind.video
                        ? 'Video call · ${session.state.label}'
                        : 'Audio call · ${session.state.label}',
                    style: AppTypography.caption,
                  ),
                  if (session.state == CallState.active) ...[
                    const SizedBox(height: 8),
                    Text(
                      session.elapsedLabel(_now),
                      style: AppTypography.titleMedium.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (session.state == CallState.reconnecting)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'The connection dropped — hold on.',
                        style: AppTypography.caption.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  if (session.state.isFinished) ...[
                    const SizedBox(height: 8),
                    Text(
                      session.endReason == null
                          ? session.state.label
                          : '${session.state.label} (${session.endReason})',
                      style: AppTypography.caption,
                    ),
                  ],
                  const Spacer(),
                  if (session.state == CallState.ringing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallButton(
                          icon: Icons.call_end_rounded,
                          label: 'Decline',
                          color: AppColors.danger,
                          onTap: controller.decline,
                        ),
                        _CallButton(
                          icon: Icons.call_rounded,
                          label: 'Accept',
                          color: AppColors.brand600,
                          onTap: controller.accept,
                        ),
                      ],
                    )
                  else if (live)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallButton(
                          icon: session.muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: session.muted ? 'Unmute' : 'Mute',
                          onTap: controller.toggleMute,
                        ),
                        _CallButton(
                          icon: Icons.call_end_rounded,
                          label: 'End',
                          color: AppColors.danger,
                          onTap: controller.hangup,
                        ),
                        _CallButton(
                          icon: session.speaker
                              ? Icons.volume_up_rounded
                              : Icons.volume_down_rounded,
                          label: 'Speaker',
                          onTap: controller.toggleSpeaker,
                        ),
                      ],
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _close,
                        child: const Text('Close'),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/app');
    }
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_disabled_rounded, size: 36),
          const SizedBox(height: 10),
          Text('This call is not available', style: AppTypography.titleMedium),
          const SizedBox(height: 14),
          TextButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? AppColors.card,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Icon(
                icon,
                size: 26,
                color: color == null
                    ? AppColors.textPrimary
                    : AppColors.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}
