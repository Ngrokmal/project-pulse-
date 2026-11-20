import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../account_status/presentation/account_gate.dart';
import '../../calls/presentation/calls_screen.dart';
import '../../explore/presentation/explore_screen.dart';
import '../../notifications/presentation/push_banner.dart';
import '../../presence/application/presence_controller.dart';
import '../../chat/presentation/chats_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../update/presentation/widgets/update_resume_gate.dart';

/// App shell with the reference bottom navigation: Home · Calls · Explore ·
/// Profile, in that order.
///
/// Explore's backend (friends requests, friendships, ranked people search) ships
/// as migration `0010_friends.sql`; if that migration has not been applied yet the
/// tab still opens and says so, instead of hiding a feature that exists in the
/// design.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    ChatsScreen(),
    CallsScreen(),
    ExploreScreen(),
    ProfileScreen(),
  ];

  static const _tabs = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Home'),
    (Icons.call_outlined, Icons.call_rounded, 'Calls'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    // Keeps `user_presence` warm while the signed-in shell is on screen.
    ref.watch(presenceHeartbeatProvider);
    return Scaffold(
      body: UpdateResumeGate(
        child: AccountGate(
          child: Column(
            children: [
              PushBanner(onOpenInbox: () => setState(() => _index = 0)),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    // Keep every tab warm, but only the visible one may animate:
                    // an off-screen tab that keeps ticking is exactly how a phone
                    // drops frames for a screen nobody is looking at.
                    for (final (index, screen) in _screens.indexed)
                      TickerMode(enabled: index == _index, child: screen),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.$1, color: AppColors.textMuted),
              selectedIcon: Icon(t.$2, color: AppColors.brand700),
              label: t.$3,
            ),
        ],
      ),
    );
  }
}
