import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';
import 'confirm_box.dart';

class AyuGeneralPage extends StatelessWidget {
  const AyuGeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    // Translation Provider
    b.addSkip();
    b.addSectionTitle('Translation Provider');
    final nativeProviderName = Platform.isMacOS
        ? 'macOS'
        : Platform.isWindows
            ? 'Windows'
            : Platform.isLinux
                ? 'Linux'
                : null;
    b.addChooseButton(
      label: 'Translation Provider',
      value: appState.translationProvider,
      items: {
        0: 'Telegram',
        1: 'Google',
        2: 'Yandex',
        if (nativeProviderName != null) 3: nativeProviderName,
      },
      onChanged: (v) => appState.setTranslationProvider(v),
    );

    // General section
    b.addSectionDivider();
    b.addSectionTitle('General');

    b.addSettingToggle(
      label: 'Disable Stories',
      subtitle: 'Hide the Stories row from the chat list',
      value: appState.disableStories,
      onChanged: (v) => appState.setDisableStories(v),
    );

    b.addSettingToggle(
      label: 'Disable Open Link Warning',
      subtitle: 'Skip confirmation when opening external URLs',
      value: appState.disableOpenLinkWarning,
      onChanged: (v) => appState.setDisableOpenLinkWarning(v),
    );

    b.addCollapsibleToggle(
      label: 'Disable Similar Channels',
      isExpanded: appState.collapseSimilarChannels ||
          appState.hideSimilarChannelsTab,
      children: [
        AyuNestedCheckboxItem(
          label: 'Collapse Similar Channels',
          value: appState.collapseSimilarChannels,
          onChanged: (v) => appState.setCollapseSimilarChannels(v),
        ),
        AyuNestedCheckboxItem(
          label: 'Hide Similar Channels Tab',
          value: appState.hideSimilarChannelsTab,
          onChanged: (v) => appState.setHideSimilarChannelsTab(v),
        ),
      ],
    );

    b.addSettingToggle(
      label: 'Disable Notify Delay',
      subtitle: 'Receive notifications instantly without delay',
      value: appState.disableNotifyDelay,
      onChanged: (v) => appState.setDisableNotifyDelay(v),
    );

    // Divider — second group
    b.addSectionDivider();

    b.addSettingToggle(
      label: 'Filter Zalgo',
      subtitle: 'Filter stacked diacritical marks that overflow text',
      value: appState.filterZalgo,
      onChanged: (v) {
        showConfirmBox(
          context,
          title: 'Restart Required',
          text: 'Filter Zalgo will be applied after restarting.',
          confirmText: 'Apply',
          cancelText: 'Cancel',
          onConfirm: () => appState.setFilterZalgo(v),
        );
      },
      showBetaBadge: true,
    );

    b.addSettingToggle(
      label: 'Improve Link Previews',
      subtitle: 'Enhanced link preview metadata extraction',
      value: appState.improveLinkPreviews,
      onChanged: (v) => appState.setImproveLinkPreviews(v),
    );

    b.addSettingToggle(
      label: 'Show Message Seconds',
      subtitle: 'Display seconds in timestamps (HH:mm:ss)',
      value: appState.showMessageSeconds,
      onChanged: (v) => appState.setShowMessageSeconds(v),
    );

    b.addChooseButton(
      label: 'Show Peer ID',
      value: appState.showPeerId,
      items: const {
        0: 'Hide',
        1: 'Telegram API',
        2: 'Bot API',
      },
      onChanged: (v) => appState.setShowPeerId(v),
    );

    // Webview section
    b.addSectionDivider();
    b.addSectionTitle('Webview');

    b.addSettingToggle(
      label: 'Spoof Client as Android',
      subtitle: 'Webview reports as Android for mobile-only bot apps',
      value: appState.spoofClientAsAndroid,
      onChanged: (v) => appState.setSpoofClientAsAndroid(v),
    );

    b.addCollapsibleToggle(
      label: 'Bigger Window',
      isExpanded: appState.increaseContentHeight ||
          appState.increaseContentWidth,
      children: [
        AyuNestedCheckboxItem(
          label: 'Increase Content Height',
          value: appState.increaseContentHeight,
          onChanged: (v) => appState.setIncreaseContentHeight(v),
        ),
        AyuNestedCheckboxItem(
          label: 'Increase Content Width',
          value: appState.increaseContentWidth,
          onChanged: (v) => appState.setIncreaseContentWidth(v),
        ),
      ],
    );

    // Confirmations section
    b.addSectionDivider();
    b.addSectionTitle('Confirmations');

    b.addSettingToggle(
      label: 'For Stickers',
      subtitle: 'Confirm before sending a sticker',
      value: appState.confirmStickers,
      onChanged: (v) => appState.setConfirmStickers(v),
    );

    b.addSettingToggle(
      label: 'For GIFs',
      subtitle: 'Confirm before sending a GIF',
      value: appState.confirmGifs,
      onChanged: (v) => appState.setConfirmGifs(v),
    );

    b.addSettingToggle(
      label: 'For Voice Messages',
      subtitle: 'Confirm before sending a voice message',
      value: appState.confirmVoiceMessages,
      onChanged: (v) => appState.setConfirmVoiceMessages(v),
    );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'General',
      children: b.build(),
    );
  }
}
