import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/auth_screen.dart';
import '../../features/dev/presentation/design_gallery.dart';
import '../../features/calls/presentation/call_screen.dart';
import '../../features/inbox/presentation/personal_inbox_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/update/presentation/update_screen.dart';
import '../../features/chat/presentation/create_group_screen.dart';
import '../../features/force_audio/presentation/force_audio_screen.dart';
import '../../features/diagnostics/presentation/connection_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/shell/presentation/home_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
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
