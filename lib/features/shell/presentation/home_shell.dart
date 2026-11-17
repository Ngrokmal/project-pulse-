import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../account_status/presentation/account_gate.dart';
import '../../calls/presentation/calls_screen.dart';
import '../../notifications/presentation/push_banner.dart';
import '../../presence/application/presence_controller.dart';
import '../../chat/presentation/chats_screen.dart';
import '../../profile/presentation/profile_screen.dart';

/// App shell with the reference bottom navigation.
/// Explore lands in Phase 3 (search backend) — it is intentionally not shown
/// yet instead of shipping a decorative, non-functional tab (§19.18).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _tabs = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Home'),
    (Icons.call_outlined, Icons.call_rounded, 'Calls'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    // Keeps `user_presence` warm while the signed-in shell is on screen.
    ref.watch(presenceHeartbeatProvider);
    return Scaffold(
      body: AccountGate(
        child: Column(
          children: [
            PushBanner(onOpenInbox: () => setState(() => _index = 0)),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: const [ChatsScreen(), CallsScreen(), ProfileScreen()],
              ),
            ),
          ],
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
