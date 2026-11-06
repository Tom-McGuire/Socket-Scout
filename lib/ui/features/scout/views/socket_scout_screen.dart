import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/socket_scout_view_model.dart';
import 'tier1_top_control_bar.dart';
import 'tier2_status_banner.dart';
import 'tier3_filter_toolbar.dart';
import 'tier4_primary_workspace.dart';
import 'tier5_detail_inspector.dart';

class SocketScoutScreen extends StatefulWidget {
  const SocketScoutScreen({super.key});

  @override
  State<SocketScoutScreen> createState() => _SocketScoutScreenState();
}

class _SocketScoutScreenState extends State<SocketScoutScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final vm = Provider.of<SocketScoutViewModel>(context, listen: false);
    if (vm.isListening) {
      await vm.stopListening();
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          // Tier 1: Top Control Bar
          Tier1TopControlBar(),

          // Tier 2: Global Alert / Status Banner (Conditional)
          Tier2StatusBanner(),

          // Tier 3: Filter & Triage Toolbar
          Tier3FilterToolbar(),

          // Tier 4: Primary Data Workspace (Expanded)
          Expanded(
            child: Tier4PrimaryWorkspace(),
          ),

          // Tier 5: Collapsible Detail Inspector & Persistent Status Bar
          Tier5DetailInspector(),
        ],
      ),
    );
  }
}
