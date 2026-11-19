import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../application/explore_chat_launcher.dart';
import '../domain/person.dart';

/// The one way Explore opens a conversation: resolve the id, then push the real
/// personal inbox route (`/chat/:id`) over the tab, so Back returns to Explore
/// exactly where it was.
Future<void> openExploreChat(
  BuildContext context,
  WidgetRef ref,
  Person person,
) async {
  final conversationId = await ref
      .read(exploreChatLauncherProvider)
      .openWith(person);
  if (conversationId == null || !context.mounted) return;
  await context.push<void>('/chat/$conversationId');
}
