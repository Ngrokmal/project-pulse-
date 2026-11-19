import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../application/update_controller.dart';
import 'widgets/update_painters.dart';

/// The page a launch lands on when there is a newer Pulse.
///
/// It is a *page*, not a dialog: the reference language of the app (deep violet
/// gradient, one gradient CTA, one honest sentence per fact) with the state of
/// the download written across the middle. Nothing here is decorative padding —
/// every element answers a question the user would otherwise ask: which version,
/// how big, what changed, why it needs permission, and where the file went.
class UpdateScreen extends ConsumerStatefulWidget {
  const UpdateScreen({super.key});

  @override
  ConsumerState<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends ConsumerState<UpdateScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = ref.read(updateControllerProvider.notifier);
      final phase = ref.read(updateControllerProvider).phase;
      if (phase == UpdatePhase.idle || phase == UpdatePhase.failed) {
        controller.check();
      } else {
        controller.refreshPermission();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the "install unknown apps" screen: the permission may
    // have changed while we were away.
    if (state == AppLifecycleState.resumed) {
      ref.read(updateControllerProvider.notifier).refreshPermission();
    }
  }

  void _leave() {
    final auth = ref.read(authControllerProvider);
    context.go(auth is AuthSignedIn ? '/app' : '/welcome');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updateControllerProvider);
    final installed = ref.watch(installedBuildProvider).value;

    return Scaffold(
      backgroundColor: const Color(0xFF120B22),
      body: Stack(
        children: [
          const Positioned.fill(child: UpdateAurora()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      const Spacer(),
                      TextButton(
                        onPressed: state.isWorking ? null : _leave,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFCFC6EA),
                        ),
                        child: const Text('Later'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    children: [
                      _Header(state: state, installed: installed),
                      const SizedBox(height: 22),
                      _Body(state: state),
                    ],
                  ),
                ),
                _Footer(
                  state: state,
                  onDownload: () =>
                      ref.read(updateControllerProvider.notifier).download(),
                  onCancel: () => ref
                      .read(updateControllerProvider.notifier)
                      .cancelDownload(),
                  onInstall: () =>
                      ref.read(updateControllerProvider.notifier).install(),
                  onAllow: () => ref
                      .read(updateControllerProvider.notifier)
                      .refreshPermission(),
                  onRetry: () =>
                      ref.read(updateControllerProvider.notifier).check(),
                  onLater: () async {
                    await ref
                        .read(updateControllerProvider.notifier)
                        .remindLater();
                    if (mounted) _leave();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── header

class _Header extends StatelessWidget {
  const _Header({required this.state, required this.installed});

  final UpdateState state;
  final InstalledBuild? installed;

  @override
  Widget build(BuildContext context) {
    final update = state.update;

    return Column(
      children: [
        const _PulsingMark(),
        const SizedBox(height: 20),
        Text(
          update == null
              ? 'Checking for updates'
              : (state.phase == UpdatePhase.upToDate
                    ? 'You’re up to date'
                    : 'A newer Pulse is ready'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 23,
            height: 1.2,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          update == null
              ? 'One quick request to the release channel.'
              : '${state.variant?.sizeLabel ?? update.sizeLabel} · ${update.notes.isEmpty ? 'Polish and fixes' : '${update.notes.length} changes'}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: Color(0xFFA79DC6),
          ),
        ),
        if (update != null) ...[
          const SizedBox(height: 18),
          _VersionPill(
            from: installed?.versionName ?? '—',
            to: update.versionName,
          ),
        ],
      ],
    );
  }
}

class _PulsingMark extends StatefulWidget {
  const _PulsingMark();

  @override
  State<_PulsingMark> createState() => _PulsingMarkState();
}

class _PulsingMarkState extends State<_PulsingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppMotion.reducedMotion(context);

    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduce)
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  size: const Size.square(132),
                  painter: UpdateHaloPainter(t: _pulse.value),
                ),
              ),
            ),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[Color(0xFF9B8AF5), Color(0xFF4F25C4)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x8C5F3FDC),
                  blurRadius: 34,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: const Icon(
              Icons.system_update_rounded,
              size: 38,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill({required this.from, required this.to});

  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            from,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF9F95BF),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: Color(0xFFB9A9F5),
            ),
          ),
          Text(
            to,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────── body

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final update = state.update;

    if (state.phase == UpdatePhase.upToDate) {
      return const _Card(
        child: Row(
          children: [
            Icon(Icons.verified_rounded, size: 20, color: Color(0xFF4ADE80)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'This build is the newest one on the release channel. Nothing '
                'to install.',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFCFC7E6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (update == null) {
      return const _Card(
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB9A9F5)),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Asking GitHub for the latest build…',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFCFC7E6),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (update.notes.isEmpty)
                const Text(
                  'A newer build of Pulse, signed with the same key — installing '
                  'it keeps every chat, every message and your session.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFCFC7E6),
                  ),
                )
              else
                for (final note in update.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: Color(0xFF8B7BF0),
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFCFC7E6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              if (state.phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 6),
                _DownloadBar(state: state),
              ],
              if (state.phase == UpdatePhase.ready) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.download_done_rounded,
                      size: 16,
                      color: Color(0xFF4ADE80),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Downloaded and verified — ${state.variant?.sizeLabel ?? update.sizeLabel}. '
                        'It stays on the phone, so nothing is fetched twice.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9FD9B4),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (!state.canInstall && state.phase == UpdatePhase.ready)
          const _PermissionCard(),
        if (state.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _Card(
              tint: const Color(0x33FF6B6B),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFFFFB4B4),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      state.message!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFFFD5D5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.tint});

  final Widget child;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tint ?? Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _DownloadBar extends StatelessWidget {
  const _DownloadBar({required this.state});

  final UpdateState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: Colors.white.withValues(alpha: 0.10)),
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: progress ?? 0.02),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  builder: (context, value, _) => FractionallySizedBox(
                    widthFactor: value.clamp(0.02, 1.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[Color(0xFF9B8AF5), Color(0xFF4F25C4)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Text(
              progress == null
                  ? 'Downloading…'
                  : 'Downloading ${state.percent}%',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFFCFC7E6),
              ),
            ),
            const Spacer(),
            Text(
              state.total > 0
                  ? '${_mb(state.received)} / ${_mb(state.total)} MB'
                  : '',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8F85AE),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);
}

class _PermissionCard extends ConsumerWidget {
  const _PermissionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _Card(
      tint: const Color(0x1AFFC46B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'One permission first',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Color(0xFFFFE0A8),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Android will not let Pulse open the installer until you allow '
            '“Install unknown apps” for Pulse. It is one switch, and it is the '
            'only way a sideloaded app can update itself.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE3CFA9),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton(
                onPressed: () =>
                    ref.read(updateControllerProvider.notifier).install(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFFE0A8),
                  side: const BorderSide(color: Color(0x66FFC46B)),
                  shape: const StadiumBorder(),
                ),
                child: const Text('Allow'),
              ),
              const SizedBox(width: 10),
              TextButton(
                onPressed: () => ref
                    .read(updateControllerProvider.notifier)
                    .refreshPermission(),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB9A9F5),
                ),
                child: const Text('I’ve allowed it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────── footer

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.onDownload,
    required this.onCancel,
    required this.onInstall,
    required this.onAllow,
    required this.onRetry,
    required this.onLater,
  });

  final UpdateState state;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onInstall;
  final VoidCallback onAllow;
  final VoidCallback onRetry;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final Widget primary;
    switch (state.phase) {
      case UpdatePhase.available:
        primary = _Cta(
          label: 'Download update',
          icon: Icons.download_rounded,
          onTap: onDownload,
        );
      case UpdatePhase.downloading:
        primary = _Cta(
          label: state.progress == null
              ? 'Downloading…'
              : 'Downloading ${state.percent}%',
          icon: Icons.stop_circle_outlined,
          onTap: onCancel,
          muted: true,
        );
      case UpdatePhase.ready:
        primary = _Cta(
          label: state.canInstall ? 'Install update' : 'Allow and install',
          icon: Icons.system_update_rounded,
          onTap: state.canInstall ? onInstall : onAllow,
        );
      case UpdatePhase.installing:
        primary = const _Cta(
          label: 'Opening the installer…',
          icon: Icons.hourglass_bottom_rounded,
          onTap: null,
          muted: true,
        );
      case UpdatePhase.failed:
        primary = _Cta(
          label: state.update == null ? 'Try again' : 'Download update',
          icon: Icons.refresh_rounded,
          onTap: state.update == null ? onRetry : onDownload,
        );
      case UpdatePhase.checking:
      case UpdatePhase.upToDate:
      case UpdatePhase.idle:
        primary = _Cta(
          label: state.phase == UpdatePhase.upToDate
              ? 'Back to Pulse'
              : 'Checking…',
          icon: Icons.arrow_forward_rounded,
          onTap: state.phase == UpdatePhase.upToDate ? onLater : null,
          muted: state.phase != UpdatePhase.upToDate,
        );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          primary,
          const SizedBox(height: 8),
          if (state.update != null && state.phase != UpdatePhase.ready)
            TextButton(
              onPressed: state.isWorking ? null : onLater,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9C92BC),
              ),
              child: const Text('Not now'),
            ),
          if (state.phase == UpdatePhase.ready)
            Text(
              'Android will show one confirmation — that tap is the system\'s, '
              'and no app can skip it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${AppConfig.appName} ${AppConfig.buildLabel}',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: Colors.white.withValues(alpha: 0.26),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cta extends StatefulWidget {
  const _Cta({
    required this.label,
    required this.icon,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool muted;

  @override
  State<_Cta> createState() => _CtaState();
}

class _CtaState extends State<_Cta> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap!.call();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: enabled ? 1 : 0.6,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: widget.muted
                  ? const LinearGradient(
                      colors: <Color>[Color(0xFF3A3357), Color(0xFF2C2745)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[Color(0xFF9B8AF5), Color(0xFF4F25C4)],
                    ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: widget.muted
                  ? null
                  : const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x995F3FDC),
                        blurRadius: 26,
                        offset: Offset(0, 14),
                      ),
                    ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 19, color: Colors.white),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
