import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../widgets/guided_tour_overlay.dart';
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
  final GlobalKey _zone2Key = GlobalKey();
  final GlobalKey _zone3Key = GlobalKey();
  final GlobalKey _heroCardKey = GlobalKey();
  final GlobalKey _historyTableKey = GlobalKey();
  final GlobalKey _inspectorKey = GlobalKey();

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

  List<GuidedTourStep> _buildTourSteps(SocketScoutViewModel vm) {
    if (vm.isWifiMode) {
      void ensureFirstWifiSelected() {
        if (vm.selectedWifiDiscovery == null && vm.wifiDiscoveries.isNotEmpty) {
          vm.selectWifiDiscovery(vm.wifiDiscoveries.first);
        }
      }

      return [
        GuidedTourStep(
          targetKey: _zone2Key,
          title: 'Zone 2: Wi-Fi Network Adapter Selector',
          description:
              'Selecting a wireless adapter automatically switches Socket Scout into Wi-Fi Access Point Scout mode. Switch back to an Ethernet NIC anytime for wired LLDP/CDP.',
        ),
        GuidedTourStep(
          targetKey: _zone3Key,
          title: 'Zone 3: Start Wi-Fi AP Scouting',
          description:
              'Poll OS wireless telemetry to identify the connected Access Point BSSID, SSID, band/channel, RSSI signal strength, PHY speed, and roaming transitions.',
        ),
        GuidedTourStep(
          targetKey: _heroCardKey,
          title: 'Active Access Point Summary Card',
          description:
              'Immediately inspect the connected AP display name, BSSID radio MAC, SSID, RSSI signal quality, RF band/channel width, PHY link speed, and security mode.',
        ),
        GuidedTourStep(
          targetKey: _historyTableKey,
          title: 'Wi-Fi Roaming History Table',
          description:
              'Track every Access Point association and roaming event as you walk the site. Right-click any AP to copy RF details or save a custom AP name to the Shared Device Library.',
          onStepEnter: ensureFirstWifiSelected,
        ),
        GuidedTourStep(
          targetKey: _inspectorKey,
          title: 'RF & Neighbor AP Inspector',
          description:
              'Review full RF Summary fields, nearby Neighbor APs for roaming diagnostics, raw OS telemetry, and the CLI command, or export CSV/JSON/Engineering Reports.',
          onStepEnter: ensureFirstWifiSelected,
        ),
      ];
    }

    void ensureFirstSelected() {
      if (vm.selectedDiscovery == null && vm.discoveries.isNotEmpty) {
        vm.selectDiscovery(vm.discoveries.first);
      }
    }

    return [
      GuidedTourStep(
        targetKey: _zone2Key,
        title: 'Zone 2: Physical Ethernet Interface Selector',
        description:
            'Select the wired Ethernet network adapter plugged into your wall jack or switch port (or use Refresh after connecting a USB NIC).',
      ),
      GuidedTourStep(
        targetKey: _zone3Key,
        title: 'Zone 3: Start Listening (LLDP / CDP)',
        description:
            'Start passive Layer-2 frame capture to intercept LLDP (IEEE 802.1AB) and Cisco Discovery Protocol advertisements sent by upstream switches.',
      ),
      GuidedTourStep(
        targetKey: _heroCardKey,
        title: 'Active Switch Port Summary Card',
        description:
            'Immediately read the connected Switch Hostname, Physical Port ID, Native VLAN, Management IP, Chassis MAC, and PoE/Link capabilities.',
      ),
      GuidedTourStep(
        targetKey: _historyTableKey,
        title: 'Captured Frame History Table',
        description:
            'Review historical switch advertisements as you move from socket to socket. Right-click any row to copy details or save the switch to the Shared Device Library.',
        onStepEnter: ensureFirstSelected,
      ),
      GuidedTourStep(
        targetKey: _inspectorKey,
        title: 'TLV Attribute Inspector & Export',
        description:
            'Inspect parsed Summary fields, Raw TLV trees, Hex/ASCII dumps, and the generated tcpdump command, or export CSV/JSON/Engineering Reports from the top bar.',
        onStepEnter: ensureFirstSelected,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<SocketScoutViewModel>();
    final isDemoMode = context.select<SocketScoutViewModel, bool>(
      (model) => model.isDemoMode,
    );

    return Scaffold(
      body: GuidedTourOverlay(
        isActive: isDemoMode,
        steps: _buildTourSteps(vm),
        onFinish: () => vm.endDemoWalkthrough(),
        child: Column(
          children: [
            // Tier 1: Top Control Bar
            Tier1TopControlBar(
              zone2Key: _zone2Key,
              zone3Key: _zone3Key,
            ),

            // Tier 2: Global Alert / Status Banner (Conditional)
            const Tier2StatusBanner(),

            // Tier 3: Filter & Triage Toolbar
            const Tier3FilterToolbar(),

            // Tier 4: Primary Data Workspace (Expanded)
            Expanded(
              child: Tier4PrimaryWorkspace(
                heroCardKey: _heroCardKey,
                historyTableKey: _historyTableKey,
              ),
            ),

            // Tier 5: Collapsible Detail Inspector & Persistent Status Bar
            Tier5DetailInspector(key: _inspectorKey),
          ],
        ),
      ),
    );
  }
}
