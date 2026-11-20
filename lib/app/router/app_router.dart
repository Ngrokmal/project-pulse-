import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/account_status/application/account_status_controller.dart';
import '../../features/account_status/domain/account_status.dart';
import '../../features/account_status/presentation/account_on_hold_screen.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/dev/presentation/design_gallery.dart';
import '../../features/calls/presentation/call_screen.dart';
import '../../features/inbox/presentation/personal_inbox_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/update/presentation/update_screen.dart';
import '../../features/chat/presentation/create_group_screen.dart';
import '../../features/force_audio/presentation/force_audio_screen.dart';
import '../../features/diagnostics/presentation/connection_screen.dart';
import '../../features/profile/presentation/blocked_people_screen.dart';
import '../../features/profile/presentation/peer_card_screen.dart';
import '../../features/profile/presentation/profile_visitors_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/shell/presentation/home_shell.dart';

/// Where the app is allowed to be, given what the server says about the
/// account. A hold is not a dialog somebody can swipe away: every location
/// redirects to the notice, and the notice's own two actions are the only ways
/// out of it.
const accountHoldPath = '/account-on-hold';

final routerProvider = Provider<GoRouter>((ref) {
  // GoRouter re-evaluates `redirect` when this fires, and only then: the router
  // itself must stay the same instance or the navigation stack is rebuilt.
  final lockedSignal = ValueNotifier<bool>(
    ref.read(accountLockProvider) != null,
  );
  ref.listen<AccountHold?>(accountLockProvider, (_, next) {
    lockedSignal.value = next != null;
  });
  ref.onDispose(lockedSignal.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: lockedSignal,
    redirect: (context, state) {
      final locked = ref.read(accountLockProvider) != null;
      final atNotice = state.matchedLocation == accountHoldPath;

      if (locked && !atNotice) return accountHoldPath;
      if (!locked && atNotice) {
        return ref.read(authControllerProvider) is AuthSignedIn
            ? '/app'
            : '/welcome';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/welcome',
        name: 'welcome',
        pageBuilder: (context, state) => _fade(state, const WelcomeScreen()),
      ),
      GoRoute(
        path: '/auth',
        name: 'auth',
        pageBuilder: (context, state) => _fade(
          state,
          AuthScreen(
            startInSignup: state.uri.queryParameters['mode'] == 'signup',
          ),
        ),
      ),
      GoRoute(
        path: accountHoldPath,
        name: 'account-on-hold',
        builder: (context, state) => const AccountOnHoldScreen(),
      ),
      GoRoute(
        path: '/update',
        name: 'update',
        pageBuilder: (context, state) => _fade(state, const UpdateScreen()),
      ),
      GoRoute(
        path: '/app',
        name: 'app',
        pageBuilder: (context, state) => _fade(state, const HomeShell()),
      ),
      GoRoute(
        path: '/chat/:id',
        name: 'chat',
        pageBuilder: (context, state) => _fade(
          state,
          PersonalInboxScreen(conversationId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) => _fade(state, const SettingsScreen()),
      ),
      GoRoute(
        path: '/call/:id',
        name: 'call',
        pageBuilder: (context, state) =>
            _fade(state, CallScreen(callId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/group/new',
        name: 'group-new',
        pageBuilder: (context, state) =>
            _fade(state, const CreateGroupScreen()),
      ),
      GoRoute(
        path: '/force-audio/:alertId',
        name: 'force-audio',
        pageBuilder: (context, state) => _fade(
          state,
          ForceAudioScreen(alertId: state.pathParameters['alertId']!),
        ),
      ),
      GoRoute(
        path: '/profile/edit',
        name: 'edit-profile',
        pageBuilder: (context, state) =>
            _fade(state, const EditProfileScreen()),
      ),
      // Someone else's card, read the way a visitor reads it. Reached by opening
      // a person (a search result, a visitor in Profile views) — never by a
      // button that says "Message".
      GoRoute(
        path: '/u/:id',
        name: 'peer-card',
        pageBuilder: (context, state) =>
            _fade(state, PeerCardScreen(peerId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/profile/views',
        name: 'profile-views',
        pageBuilder: (context, state) =>
            _fade(state, const ProfileVisitorsScreen()),
      ),
      GoRoute(
        path: '/blocked',
        name: 'blocked',
        pageBuilder: (context, state) =>
            _fade(state, const BlockedPeopleScreen()),
      ),
      GoRoute(
        path: '/connection',
        name: 'connection',
        pageBuilder: (context, state) => _fade(state, const ConnectionScreen()),
      ),
      GoRoute(
        path: '/design',
        name: 'design',
        builder: (context, state) => const DesignGalleryScreen(),
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Route not found: ${state.uri}'))),
  );
});

/// Set from Settings ("Reduce motion"). A ValueNotifier keeps the router
/// instance stable — rebuilding GoRouter would reset the navigation stack.
final reduceMotionNotifier = ValueNotifier<bool>(false);

CustomTransitionPage<void> _fade(GoRouterState state, Widget child) {
  final reduceMotion = reduceMotionNotifier.value;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondary, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: const Cubic(0.22, 1, 0.36, 1),
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
