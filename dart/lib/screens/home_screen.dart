import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/chat_state.dart';
import '../theme/theme.dart';
import '../widgets/platform_rail.dart';
import '../widgets/sidebar.dart';
import '../widgets/chat_view.dart';

/// Main screen — platform rail + sidebar + chat area.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // Platform rail (left edge)
          const PlatformRail(),

          // Vertical divider
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),

          // Sidebar (chat list)
          const SizedBox(
            width: AppSizes.sidebarWidth,
            child: Sidebar(),
          ),

          // Vertical divider
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),

          // Main chat area
          Expanded(
            child: chatState.activeChat != null
                ? const ChatView()
                : _buildEmptyState(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
          ),
          const SizedBox(height: 16),
          Text(
            'Select a chat to start messaging',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}
