import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';

class AyuFiltersPage extends StatelessWidget {
  const AyuFiltersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return ayuSettingsScaffold(
      context: context,
      title: 'Filters',
      children: [
        const SizedBox(height: 48),
        Center(
          child: Icon(Icons.filter_alt_outlined,
              size: 64,
              color: isDark
                  ? const Color(0xFF3E546A)
                  : const Color(0xFFCCCCCC)),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text('Regex Filters',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87)),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Message filtering with regex patterns, shadow banning, '
            'and per-dialog rules.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: subtitleColor),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
