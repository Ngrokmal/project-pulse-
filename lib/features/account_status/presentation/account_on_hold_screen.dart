import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/error/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../auth/application/auth_controller.dart';
import '../application/account_status_controller.dart';
import '../domain/account_status.dart';
import 'widgets/held_orrery.dart';

/// The notice a suspended account cannot get past (§25).
///
/// It is a page, not a dialog: the bottom bar, the router and the back gesture
/// all lead back here, and the only two ways out are the ones printed on it —
/// ask a human to look again, or sign in as somebody else. The session is ended
/// before this screen is shown, so nothing behind it can quietly keep working.
class AccountOnHoldScreen extends ConsumerStatefulWidget {
  const AccountOnHoldScreen({super.key});

  @override
  ConsumerState<AccountOnHoldScreen> createState() =>
      _AccountOnHoldScreenState();
}

class _AccountOnHoldScreenState extends ConsumerState<AccountOnHoldScreen> {
  HoldStage _stage = HoldStage.held;
  AppealReceipt? _receipt;
  bool _appealOpen = false;
  bool _sending = false;
  String? _error;
  String _note = '';

  // The notice's own palette: the app turns dark for this screen, because the
  // thing it is saying is not a normal moment.
  static const _bg = Color(0xFF08070F);
  static const _ink = Color(0xFFF6F4FB);
  static const _muted = Color(0xFFA8A4BC);
  static const _amber = Color(0xFFF7B267);
  static const _mint = Color(0xFF3BE59B);

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  Future<void> _fileAppeal(String password) async {
    final hold = ref.read(accountLockProvider);
    if (hold == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });

    final lock = ref.read(accountLockProvider.notifier);
    final auth = ref.read(authControllerProvider.notifier);
    final repo = ref.read(accountStatusRepositoryProvider);

    // The notice signs in *only* to file this appeal; the watchdog is told not
    // to end the session out from under the request.
    lock.beginAppealSession();
    try {
      if (ref.read(authControllerProvider) is! AuthSignedIn) {
        final failure = await auth.signIn(
          email: hold.email ?? '',
          password: password,
        );
        if (failure != null) {
          setState(() {
            _sending = false;
            _error = failure.userMessage;
          });
          await lock.endAppealSession();
          return;
        }
      }

      final signedIn = ref.read(authControllerProvider);
      if (signedIn is! AuthSignedIn) {
        setState(() {
          _sending = false;
          _error = 'That sign-in did not go through. Try again.';
        });
        await lock.endAppealSession();
        return;
      }

      final caseCode = hold.info.caseCode;
      if (caseCode == null || caseCode.isEmpty) {
        setState(() {
          _sending = false;
          _error = 'This case has no reference yet. Email help@pulse.chat.';
        });
        await lock.endAppealSession();
        return;
      }

      final appeal = await repo.submitAppeal(
        userId: signedIn.user.id,
        caseCode: caseCode,
        note: _note,
      );

      if (!mounted) return;
      await _showReceived(appeal);
    } on AppealAlreadyOpenFailure {
      final signedIn = ref.read(authControllerProvider);
      if (signedIn is AuthSignedIn) {
        final existing = await repo.fetchLatestAppeal(signedIn.user.id);
        if (existing != null && mounted) await _showReceived(existing);
      }
    } on AccountSuspendedFailure catch (failure) {
      if (mounted) setState(() => _error = failure.userMessage);
    } on AppFailure catch (failure) {
      if (mounted) setState(() => _error = failure.userMessage);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'That did not send. Try again in a moment.');
      }
    } finally {
      // Signed in for the appeal, signed out for everything else.
      await lock.endAppealSession();
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showReceived(AccountAppeal appeal) async {
    final hold = ref.read(accountLockProvider);
    setState(() {
      _stage = HoldStage.received;
      _appealOpen = false;
      _error = null;
      _receipt = AppealReceipt(
        reference: _referenceFor(appeal, hold?.info.caseCode),
        submittedAt: appeal.createdAt,
        caseCode: hold?.info.caseCode,
      );
    });
    HapticFeedback.mediumImpact();
  }

  /// A short, readable reference derived from the appeal id, so support can ask
  /// for "the four characters on your screen".
  static String _referenceFor(AccountAppeal appeal, String? caseCode) {
    final tail = appeal.id.replaceAll('-', '');
    final head = tail.length >= 6 ? tail.substring(0, 6) : tail;
    final base = caseCode ?? 'PULSE';
    return '$base-$head'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hold = ref.watch(accountLockProvider);
    final info = hold?.info;
    if (info == null) {
      // Nothing to hold: this screen is only reachable with a hold, and the
      // router will move on. Drawing a blank page for a frame is worse than
      // drawing nothing at all.
      return const Scaffold(backgroundColor: _bg);
    }

    final received = _stage == HoldStage.received;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF120E22), _bg],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -160,
                right: -120,
                child: _Orb(
                  color: (received ? _mint : AppColors.brand500).withValues(
                    alpha: 0.20,
                  ),
                  size: 380,
                ),
              ),
              Positioned(
                bottom: -180,
                left: -140,
                child: _Orb(
                  color: (received ? _mint : const Color(0xFFB7405A))
                      .withValues(alpha: 0.16),
                  size: 420,
                ),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 34),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 232,
                        child: Center(
                          child: HeldOrrery(
                            received: received,
                            size: 232,
                            reduceMotion: _reduceMotion,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: _Eyebrow(received: received, mint: _mint),
                      ),
                      const SizedBox(height: 22),
                      _Headline(info: info, received: received, ink: _ink),
                      const SizedBox(height: 14),
                      _Lede(
                        received: received,
                        info: info,
                        email: hold?.maskedEmail ?? 'your email',
                        mint: _mint,
                      ),
                      const SizedBox(height: 24),
                      _CaseCard(
                        info: info,
                        email: hold?.maskedEmail ?? 'your email',
                        received: received,
                      ),
                      const SizedBox(height: 18),
                      if (!received) ...[
                        _PrimaryAction(
                          label: _appealOpen
                              ? 'Close the appeal'
                              : 'Ask a person to look again',
                          onPressed: () =>
                              setState(() => _appealOpen = !_appealOpen),
                        ),
                        const SizedBox(height: 10),
                        _GhostAction(
                          label: 'Sign in with a different account',
                          onPressed: () {
                            // The one exit: forget the case and go back to a
                            // sign-in form that is not tied to this account.
                            ref.read(accountLockProvider.notifier).clear();
                            context.go('/auth');
                          },
                        ),
                        if (_appealOpen) ...[
                          const SizedBox(height: 14),
                          _AppealPanel(
                            sending: _sending,
                            error: _error,
                            unsignedEmail: hold?.email,
                            note: _note,
                            onNoteChanged: (value) => _note = value,
                            onSubmit: _fileAppeal,
                          ),
                        ],
                      ] else ...[
                        if (_receipt != null)
                          _Receipt(receipt: _receipt!, mint: _mint),
                        const SizedBox(height: 14),
                        _GhostAction(
                          label: 'Sign in with a different account',
                          onPressed: () {
                            // The one exit: forget the case and go back to a
                            // sign-in form that is not tied to this account.
                            ref.read(accountLockProvider.notifier).clear();
                            context.go('/auth');
                          },
                        ),
                      ],
                      const SizedBox(height: 26),
                      _NextSteps(
                        received: received,
                        mint: _mint,
                        amber: _amber,
                        muted: _muted,
                        faint: const Color(0xFF7C7892),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          'help@pulse.chat',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF7C7892),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _Orb extends StatelessWidget {
  const _Orb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.received, required this.mint});

  final bool received;
  final Color mint;

  @override
  Widget build(BuildContext context) {
    final color = received ? mint : const Color(0xFFFF8E9E);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 420),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            received ? 'APPEAL RECEIVED' : 'ACCOUNT ON HOLD',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.info,
    required this.received,
    required this.ink,
  });

  final AccountStatusInfo info;
  final bool received;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: 'Poppins',
      fontSize: 27,
      height: 1.24,
      letterSpacing: -0.5,
      fontWeight: FontWeight.w600,
      color: ink,
    );
    final accent = base.copyWith(
      fontStyle: FontStyle.italic,
      color: received ? const Color(0xFF3BE59B) : const Color(0xFFFF9E86),
      fontWeight: FontWeight.w500,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 460),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: received
          ? Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Your appeal is ', style: base),
                  TextSpan(text: 'in.', style: accent),
                  TextSpan(text: '\nNow a person reads it.', style: base),
                ],
              ),
              key: const ValueKey('received'),
              textAlign: TextAlign.center,
            )
          : Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${info.headlineTop}\n', style: base),
                  TextSpan(
                    text: info.state == AccountState.banned
                        ? 'closed.'
                        : 'The account is ',
                    style: base,
                  ),
                  if (info.state != AccountState.banned)
                    TextSpan(text: 'paused.', style: accent),
                ],
              ),
              key: const ValueKey('held'),
              textAlign: TextAlign.center,
            ),
    );
  }
}

class _Lede extends StatelessWidget {
  const _Lede({
    required this.received,
    required this.info,
    required this.email,
    required this.mint,
  });

  final bool received;
  final AccountStatusInfo info;
  final String email;
  final Color mint;

  @override
  Widget build(BuildContext context) {
    const muted = Color(0xFFA8A4BC);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 460),
      child: Text(
        received
            ? 'Thank you — that is everything we needed. The answer, either way, '
                  'goes to $email.'
            : info.explanation,
        key: ValueKey(received),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14.5, height: 1.55, color: muted),
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  const _CaseCard({
    required this.info,
    required this.email,
    required this.received,
  });

  final AccountStatusInfo info;
  final String email;
  final bool received;

  static const _ink = Color(0xFFF6F4FB);
  static const _muted = Color(0xFFA8A4BC);
  static const _line = Color(0xFF262238);
  static const _card = Color(0xFF12101C);

  @override
  Widget build(BuildContext context) {
    final tagColor = received
        ? const Color(0xFF3BE59B)
        : const Color(0xFFF7B267);
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          _Row(
            icon: Icons.alternate_email_rounded,
            label: 'The account you tried',
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    email,
                    style: const TextStyle(
                      fontSize: 14.5,
                      color: _ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tagColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    received ? 'IN REVIEW' : 'ON HOLD',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: tagColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          _Row(
            icon: Icons.report_gmailerrorred_rounded,
            label: 'Why',
            child: Text(
              info.reasonText?.isNotEmpty == true
                  ? info.reasonText!
                  : 'A report on this account is being looked at by a person.',
              style: const TextStyle(fontSize: 14.5, height: 1.45, color: _ink),
            ),
          ),
          const Divider(height: 1, color: _line),
          _Row(
            icon: Icons.schedule_rounded,
            label: received ? 'Answer by' : 'Review',
            child: Text(
              received
                  ? (info.endsAt != null
                        ? '${_date(info.endsAt!)} — usually sooner.'
                        : 'A person is on it now. No date is invented.')
                  : (info.endsAt != null
                        ? 'Access returns after ${_date(info.endsAt!)}.'
                        : 'Waiting on a person — no date is invented.'),
              style: const TextStyle(fontSize: 14.5, height: 1.45, color: _ink),
            ),
          ),
          if (info.caseCode != null && info.caseCode!.isNotEmpty) ...[
            const Divider(height: 1, color: _line),
            _Row(
              icon: Icons.confirmation_number_outlined,
              label: 'Case',
              child: Text(
                info.caseCode!,
                style: const TextStyle(
                  fontSize: 14,
                  color: _muted,
                  fontFeatures: [FontFeature.tabularFigures()],
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _date(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = value.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]}, $hh:$mm';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.child});

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1728),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFF262238)),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF9C97B8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: Color(0xFF7C7892),
                  ),
                ),
                const SizedBox(height: 5),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand500,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class _GhostAction extends StatelessWidget {
  const _GhostAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFECE9F7),
          side: const BorderSide(color: Color(0xFF2E2944)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.input),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }
}

class _AppealPanel extends StatefulWidget {
  const _AppealPanel({
    required this.sending,
    required this.error,
    required this.unsignedEmail,
    required this.note,
    required this.onNoteChanged,
    required this.onSubmit,
  });

  final bool sending;
  final String? error;
  final String? unsignedEmail;
  final String note;
  final ValueChanged<String> onNoteChanged;
  final Future<void> Function(String password) onSubmit;

  @override
  State<_AppealPanel> createState() => _AppealPanelState();
}

class _AppealPanelState extends State<_AppealPanel> {
  final _password = TextEditingController();
  final _note = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _note.text = widget.note;
  }

  @override
  void dispose() {
    _password.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12101C),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2E2944)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us what happened',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: Color(0xFFF6F4FB),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Two or three sentences is plenty. A person reads every appeal — '
            'there is no bot on the other side, which is also why it can take a '
            'day.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Color(0xFFA8A4BC),
            ),
          ),
          const SizedBox(height: 14),
          _Field(
            controller: _note,
            hint:
                'e.g. I shared a work document in a group and stopped when '
                'asked.',
            maxLines: 4,
            maxLength: 1200,
            onChanged: widget.onNoteChanged,
            fill: const Color(0xFF0E0C16),
          ),
          const SizedBox(height: 10),
          if (widget.unsignedEmail != null && widget.unsignedEmail!.isNotEmpty)
            _Field(
              controller: _password,
              hint: 'Your password — the notice signs in only to send this',
              obscure: _obscure,
              fill: const Color(0xFF0E0C16),
              suffix: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: const Color(0xFF7C7892),
                ),
              ),
            ),
          if (widget.error != null) ...[
            const SizedBox(height: 10),
            Text(
              widget.error!,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFFFF8E9E),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _PrimaryAction(
            label: widget.sending ? 'Sending…' : 'Send the appeal',
            onPressed: widget.sending
                ? () {}
                : () => widget.onSubmit(_password.text),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.fill,
    this.maxLines = 1,
    this.maxLength,
    this.obscure = false,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final Color fill;
  final int maxLines;
  final int? maxLength;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      obscureText: obscure,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14.5, color: Color(0xFFF6F4FB)),
      cursorColor: AppColors.brand400,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFF6E6A85)),
        filled: true,
        fillColor: fill,
        suffixIcon: suffix,
        counterStyle: const TextStyle(fontSize: 10, color: Color(0xFF6E6A85)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Color(0xFF2E2944)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.brand400, width: 1.4),
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.receipt, required this.mint});

  final AppealReceipt receipt;
  final Color mint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: mint.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mint.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 20, color: mint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Received. A person reads it next.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF6F4FB),
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  receipt.reference,
                  style: TextStyle(
                    fontSize: 12.5,
                    letterSpacing: 0.6,
                    color: mint.withValues(alpha: 0.9),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextSteps extends StatelessWidget {
  const _NextSteps({
    required this.received,
    required this.mint,
    required this.amber,
    required this.muted,
    required this.faint,
  });

  final bool received;
  final Color mint;
  final Color amber;
  final Color muted;
  final Color faint;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (
        'The account was paused',
        'Your chats, photos and contacts are untouched. Nothing was deleted.',
        true,
      ),
      (
        received ? 'A person reads your appeal' : 'A person reads the report',
        received
            ? 'If it was a mistake, the hold is lifted and you are signed '
                  'straight back in.'
            : 'Appeals go to a human. If the report was wrong, the hold is '
                  'lifted.',
        received,
      ),
      (
        'You get one email either way',
        'The outcome, and — if the hold stands — exactly what to change.',
        false,
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT HAPPENS NEXT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: faint,
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0
                          ? mint.withValues(alpha: 0.14)
                          : steps[i].$3
                          ? amber.withValues(alpha: 0.16)
                          : Colors.transparent,
                      border: Border.all(
                        color: i == 0
                            ? mint.withValues(alpha: 0.5)
                            : steps[i].$3
                            ? amber.withValues(alpha: 0.6)
                            : const Color(0xFF332E48),
                      ),
                    ),
                    child: i == 0
                        ? Icon(Icons.check_rounded, size: 14, color: mint)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: steps[i].$3 ? amber : faint,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${steps[i].$1}. ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE9E6F4),
                              ),
                            ),
                            TextSpan(
                              text: steps[i].$2,
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13.5, height: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
