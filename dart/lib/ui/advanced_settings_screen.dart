import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Advanced settings page (§17). Opened from Settings → Advanced row.
/// Contains: System Integration (§17.6) with native window frame toggle.
class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final appState = context.watch<AppState>();

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final dividerColor =
        isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverBg =
        isDark ? const Color(0xFF232E3C) : const Color(0xFFF1F1F1);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Advanced',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // §17.6: System Integration section.
          if (Platform.isLinux) ...[
            // Section header.
            Padding(
              padding: const EdgeInsets.only(
                  left: 20, right: 20, top: 14, bottom: 6),
              child: Text(
                'System Integration',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ),
            // "Use system window frame" toggle — spec §1, §17.6.
            InkWell(
              onTap: () => appState
                  .setNativeWindowFrame(!appState.nativeWindowFrame),
              hoverColor: hoverBg,
              splashColor: hoverBg.withValues(alpha: 0.5),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Use system window frame',
                            style: TextStyle(fontSize: 15, color: textColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Use the native system titlebar instead of the custom one',
                            style:
                                TextStyle(fontSize: 13, color: subtextColor),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: appState.nativeWindowFrame,
                      onChanged: (v) => appState.setNativeWindowFrame(v),
                      activeColor: accentColor,
                    ),
                  ],
                ),
              ),
            ),
            Container(height: 8, color: dividerColor),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
