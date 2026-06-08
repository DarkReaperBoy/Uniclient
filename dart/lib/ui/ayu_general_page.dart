import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';
import 'confirm_box.dart';
import 'telegram_toast.dart';

class AyuGeneralPage extends StatelessWidget {
  const AyuGeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    // Translation — AyuGram's subsection title is tr::lng_translate_settings_subtitle()
    // ("Translate Messages"); the button beneath is titled ayu_TranslationProvider
    // ("Translation Provider") and carries a beta badge
    // (settings_general.cpp:37,83,113-115).
    b.addSkip();
    b.addSectionTitle('Translate Messages');
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
        // AyuGram only pushes the Native option when
        // Platform::IsTranslateProviderAvailable() is true (settings_general.cpp:46-60).
        // On Linux that requires `crow`/`org.kde.CrowTranslate` on PATH
        // (translate_provider_linux.cpp:86-88); macOS/Windows always have it.
        // `nativeTranslateAvailable` mirrors that exact check (app_state.dart:2051),
        // so gate on it too — otherwise selecting "Linux" without Crow installed
        // silently reverts to Telegram via the setter clamp.
        if (nativeProviderName != null && appState.nativeTranslateAvailable)
          3: nativeProviderName,
      },
      onChanged: (v) {
        appState.setTranslationProvider(v);
        // macOS native-translation guidance toast — when the Native provider
        // (index 3 == TranslationProvider::Native, labelled "macOS" on a Mac) is
        // chosen, AyuGram pops a 6s toast warning that on-device translation
        // silently fails until the user downloads local language packs in System
        // Settings. The C++ guards it with `if constexpr (Platform::IsMac())`, so
        // it fires on macOS only (settings_general.cpp:94-101 /
        // lang.strings:6914 lng_translate_settings_use_platform_mac_about).
        if (Platform.isMacOS && v == 3) {
          showTelegramToast(
            context,
            "Translation on macOS won't work until you download local "
            'language packs in System Settings.',
            duration: const Duration(seconds: 6),
            multiline: true,
          );
        }
      },
    );
    // Beta badge on the provider button — ayu.addBetaBadge(button)
    // (settings_general.cpp:114); badge text "BETA" (settings_ayu_utils.cpp:52).
    b.addBetaBadge('BETA', labelText: 'Translation Provider');

    // General section
    b.addSectionDivider();
    b.addSectionTitle('General');

    b.addSettingToggle(
      label: 'Disable Stories',
      value: appState.disableStories,
      onChanged: (v) {
        // AyuGram applies the setting then shows a restart prompt
        // (settings_general.cpp:171-174 → ShowRestartPrompt).
        appState.setDisableStories(v);
        _showRestartPrompt(context);
      },
    );

    b.addSettingToggle(
      label: 'Disable Open Link Warning',
      value: appState.disableOpenLinkWarning,
      onChanged: (v) => appState.setDisableOpenLinkWarning(v),
    );

    b.addCollapsibleToggle(
      label: 'Disable Similar Channels',
      // AyuGram starts the collapsible hidden (raw->hide(instant),
      // settings_ayu_utils.cpp:454) with toggledWhenAll=true — the master toggle
      // is on only when BOTH children are on (settings_general.cpp:199).
      isExpanded: false,
      toggledWhenAll: true,
      onMasterToggle: (v) {
        appState.setCollapseSimilarChannels(v);
        appState.setHideSimilarChannels(v);
      },
      children: [
        AyuNestedCheckboxItem(
          label: 'Collapse Similar Channels',
          value: appState.collapseSimilarChannels,
          onChanged: (v) => appState.setCollapseSimilarChannels(v),
        ),
        AyuNestedCheckboxItem(
          label: 'Hide Similar Channels Tab',
          value: appState.hideSimilarChannels,
          onChanged: (v) => appState.setHideSimilarChannels(v),
        ),
      ],
    );

    b.addSettingToggle(
      label: 'Disable Notify Delay',
      value: appState.disableNotifyDelay,
      onChanged: (v) => appState.setDisableNotifyDelay(v),
    );

    // Divider — second group
    b.addSectionDivider();

    b.addSettingToggle(
      label: 'Filter Zalgo',
      value: appState.filterZalgo,
      onChanged: (v) {
        // AyuGram applies the setting immediately on toggle, then shows the
        // standard restart prompt (settings_general.cpp:218-228 → ShowRestartPrompt)
        // — identical to "Disable Stories".
        appState.setFilterZalgo(v);
        _showRestartPrompt(context);
      },
      showBetaBadge: true,
    );

    b.addSettingToggle(
      label: 'Improve Link Previews',
      value: appState.improveLinkPreviews,
      onChanged: (v) => appState.setImproveLinkPreviews(v),
    );

    b.addSettingToggle(
      label: 'Show Message Seconds',
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

    // AyuGram's `ayu_SettingsSpoofWebviewAsAndroid` string is "Spoof Client as
    // Android" — the toggle spoofs the whole client UA, not just the webview
    // (settings_general.cpp:254 / lang.strings:8129). The subsection header above
    // stays "Webview" to match the C++ subsection title.
    b.addSettingToggle(
      label: 'Spoof Client as Android',
      value: appState.spoofWebviewAsAndroid,
      onChanged: (v) => appState.setSpoofWebviewAsAndroid(v),
    );

    b.addCollapsibleToggle(
      label: 'Bigger Window',
      // AyuGram starts collapsed (raw->hide(instant)) with toggledWhenAll=false —
      // the master toggle is on when ANY child is on (settings_general.cpp:274).
      isExpanded: false,
      toggledWhenAll: false,
      onMasterToggle: (v) {
        appState.setIncreaseWebviewHeight(v);
        appState.setIncreaseWebviewWidth(v);
      },
      children: [
        AyuNestedCheckboxItem(
          label: 'Increase Content Height',
          value: appState.increaseWebviewHeight,
          onChanged: (v) => appState.setIncreaseWebviewHeight(v),
        ),
        AyuNestedCheckboxItem(
          label: 'Increase Content Width',
          value: appState.increaseWebviewWidth,
          onChanged: (v) => appState.setIncreaseWebviewWidth(v),
        ),
      ],
    );

    // Confirmations section
    b.addSectionDivider();
    b.addSectionTitle('Confirmations');

    b.addSettingToggle(
      label: 'For Stickers',
      value: appState.stickerConfirmation,
      onChanged: (v) => appState.setStickerConfirmation(v),
    );

    b.addSettingToggle(
      label: 'For GIFs',
      value: appState.gifConfirmation,
      onChanged: (v) => appState.setGifConfirmation(v),
    );

    b.addSettingToggle(
      label: 'For Voice Messages',
      value: appState.voiceConfirmation,
      onChanged: (v) => appState.setVoiceConfirmation(v),
    );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'General',
      children: b.build(),
    );
  }
}

// Faithful port of AyuGram's ShowRestartPrompt (settings_ayu_utils.cpp:36-45):
// apply-then-prompt with "Restart Now" (Core::Restart) / "Later".
void _showRestartPrompt(BuildContext context) {
  showConfirmBox(
    context,
    title: 'Restart Required',
    text: 'Some settings will be applied after restarting.',
    confirmText: 'Restart Now',
    cancelText: 'Later',
    onConfirm: () {
      context.read<AppState>().flushSettingsSync();
      final exe = Platform.resolvedExecutable;
      Process.start(exe, Platform.executableArguments,
              mode: ProcessStartMode.detached)
          .then((_) {
        exit(0);
      }).catchError((_) {
        exit(0);
      });
    },
    strictCancel: true,
  );
}
