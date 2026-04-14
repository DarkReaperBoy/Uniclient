import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
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
    final appState = context.watch<AppState>();
    final chatState = context.watch<ChatState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show loading while engine initializes.
    if (!appState.initialized && appState.initError == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.accent),
              const SizedBox(height: 16),
              Text('Starting engine...', style: TextStyle(
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              )),
            ],
          ),
        ),
      );
    }

    // Show error if engine failed to init.
    if (appState.initError != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Engine failed to start', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(appState.initError!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ),
        ),
      );
    }

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
                : _buildEmptyState(context, appState),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasAccounts = appState.accounts.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasAccounts ? Icons.chat_bubble_outline_rounded : Icons.add_circle_outline_rounded,
            size: 64,
            color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
          ),
          const SizedBox(height: 16),
          Text(
            hasAccounts
                ? 'Select a chat to start messaging'
                : 'Add a platform to get started',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
          ),
          if (!hasAccounts) ...[
            const SizedBox(height: 8),
            Text(
              'Click the + button on the left',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
