import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';

class AyuGeneralPage extends StatelessWidget {
  const AyuGeneralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    b.addSectionTitle('General');
    b.addSettingToggle(
      label: 'Show message seconds',
      subtitle: 'Display seconds in message timestamps (HH:mm:ss)',
      value: appState.showMessageSeconds,
      onChanged: (v) => appState.setShowMessageSeconds(v),
    );

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'General',
      children: b.build(),
    );
  }
}
