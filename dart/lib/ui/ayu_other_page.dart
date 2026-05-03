import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';

class AyuOtherPage extends StatelessWidget {
  const AyuOtherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    // Drawer Elements (§54.8)
    b.addSectionTitle('Drawer Elements');
    b.addSettingToggle(
      label: 'My Profile',
      subtitle: 'Show My Profile in drawer',
      value: appState.showMyProfileInDrawer,
      onChanged: (v) => appState.setShowMyProfileInDrawer(v),
    );
    if (appState.menuBots.isNotEmpty)
      b.addSettingToggle(
        label: 'Bots',
        subtitle: 'Show menu bots in drawer',
        value: appState.showBotsInDrawer,
        onChanged: (v) => appState.setShowBotsInDrawer(v),
      );
    b.addSettingToggle(
      label: 'New Group',
      subtitle: 'Show New Group in drawer',
      value: appState.showNewGroupInDrawer,
      onChanged: (v) => appState.setShowNewGroupInDrawer(v),
    );
    b.addSettingToggle(
      label: 'New Channel',
      subtitle: 'Show New Channel in drawer',
      value: appState.showNewChannelInDrawer,
      onChanged: (v) => appState.setShowNewChannelInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Contacts',
      subtitle: 'Show Contacts in drawer',
      value: appState.showContactsInDrawer,
      onChanged: (v) => appState.setShowContactsInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Calls',
      subtitle: 'Show Calls in drawer',
      value: appState.showCallsInDrawer,
      onChanged: (v) => appState.setShowCallsInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Saved Messages',
      subtitle: 'Show Saved Messages in drawer',
      value: appState.showSavedMessagesInDrawer,
      onChanged: (v) => appState.setShowSavedMessagesInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Night Mode',
      subtitle: 'Show Night Mode toggle in drawer',
      value: appState.showDrawerThemeToggle,
      onChanged: (v) => appState.setShowDrawerThemeToggle(v),
    );
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in drawer',
      value: appState.showGhostToggleInDrawer,
      onChanged: (v) => appState.setShowGhostToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Read Receipts (LRead)',
      subtitle: 'Show Read Receipts toggle in drawer',
      value: appState.showLReadToggleInDrawer,
      onChanged: (v) => appState.setShowLReadToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Story Reads (SRead)',
      subtitle: 'Show Story Reads toggle in drawer',
      value: appState.showSReadToggleInDrawer,
      onChanged: (v) => appState.setShowSReadToggleInDrawer(v),
    );
    b.addSettingToggle(
      label: 'Streamer Mode',
      subtitle: 'Show Streamer Mode toggle in drawer',
      value: appState.showStreamerToggleInDrawer,
      onChanged: (v) => appState.setShowStreamerToggleInDrawer(v),
    );

    b.addSectionDivider();

    // Tray Elements (§54.8)
    b.addSectionTitle('Tray Elements');
    b.addSettingToggle(
      label: 'Ghost Mode',
      subtitle: 'Show Ghost Mode toggle in system tray menu',
      value: appState.showGhostToggleInTray,
      onChanged: (v) => appState.setShowGhostToggleInTray(v),
    );
    b.addSettingToggle(
      label: 'Streamer Mode',
      subtitle: 'Show Streamer Mode toggle in system tray menu',
      value: appState.showStreamerToggleInTray,
      onChanged: (v) => appState.setShowStreamerToggleInTray(v),
    );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'Other',
      children: b.build(),
    );
  }
}
