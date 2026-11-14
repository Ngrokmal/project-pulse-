import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/connection_diagnostics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/gradient_button.dart';

/// Runs the real probes and shows exactly what failed. This is the screen to
/// open when the app says anything about being offline.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends ConsumerState<ConnectionScreen> {
  List<DiagnosticStep>? _steps;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _steps = null;
    });
    final steps = await const ConnectionDiagnostics().run();
    if (!mounted) return;
    setState(() {
      _steps = steps;
      _running = false;
    });
  }

  String get _report {
    final steps = _steps ?? const <DiagnosticStep>[];
    final buffer = StringBuffer()
      ..writeln('PULSE connection report')
      ..writeln('build     : ${AppConfig.buildLabel}')
      ..writeln('endpoint  : ${AppConfig.supabaseUrl}')
      ..writeln('key kind  : ${AppConfig.keyKind}')
      ..writeln('platform  : ${Theme.of(context).platform.name}');
    for (final s in steps) {
      buffer.writeln(
        '${s.label.padRight(7)} ${s.name}'
        '${s.milliseconds != null ? ' (${s.milliseconds}ms)' : ''}'
        '${s.detail != null ? ' :: ${s.detail}' : ''}',
      );
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final allOk = steps != null && steps.every((s) => s.ok);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Connection check'),
        actions: [
          IconButton(
            tooltip: 'Copy report',
            onPressed: steps == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _report));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Report copied')),
                    );
                  },
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenX),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        allOk
                            ? Icons.check_circle_rounded
                            : Icons.network_check_rounded,
                        size: 20,
                        color: allOk ? AppColors.success : AppColors.brand600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        allOk ? 'Everything reachable' : 'Checking your link',
                        style: AppTypography.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Build ${AppConfig.buildLabel} · ${AppConfig.keyKind}',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_running)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (steps != null)
              for (final step in steps) ...[
                _StepTile(step: step),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 18),
            GradientButton(
              label: _running ? 'Checking…' : 'Run again',
              loading: _running,
              onPressed: _running ? null : _run,
            ),
            const SizedBox(height: 10),
            Text(
              'Tip: if DNS and HTTPS pass but the app still fails, sign out and '
              'sign in again — an expired session shows a different error.',
              style: AppTypography.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});

  final DiagnosticStep step;

  @override
  Widget build(BuildContext context) {
    final color = step.ok ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            step.ok
                ? Icons.check_circle_outline_rounded
                : Icons.error_outline_rounded,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(step.name, style: AppTypography.titleMedium),
                    ),
                    if (step.milliseconds != null)
                      Text(
                        '${step.milliseconds} ms',
                        style: AppTypography.caption,
                      ),
                  ],
                ),
                if (step.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(step.detail!, style: AppTypography.caption),
                ],
                if (step.hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    step.hint!,
                    style: AppTypography.caption.copyWith(color: color),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
