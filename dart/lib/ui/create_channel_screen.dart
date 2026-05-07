import 'package:flutter/material.dart';

import 'create_group_wizard.dart';

/// §21.6: Channel creation uses the multi-step wizard flow:
/// InfoBox → create → SetupChannelBox (public/private + username)
/// → MemberPicker → navigate to channel.
///
/// This screen delegates to [showCreateChannelWizard] which implements
/// the full spec-compliant flow.
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pop();
      showCreateChannelWizard(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
