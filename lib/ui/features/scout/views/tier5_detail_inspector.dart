import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/switch_port_discovery.dart';
import '../../../../data/services/capture/capture_service.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';
import 'dialogs/edit_device_dialog.dart';

class Tier5DetailInspector extends StatefulWidget {
  const Tier5DetailInspector({super.key});

  @override
  State<Tier5DetailInspector> createState() => _Tier5DetailInspectorState();
}

class _Tier5DetailInspectorState extends State<Tier5DetailInspector>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  static Color _protocolColor(DiscoveryProtocol protocol) {
    final isLldp = protocol == DiscoveryProtocol.lldp;
    if (AppTheme.isDark) {
      return isLldp ? const Color(0xFF38BDF8) : const Color(0xFFA78BFA);
    }
    return isLldp ? const Color(0xFF0369A1) : const Color(0xFF6D28D9);
  }

  static Color get _vlanColor =>
      AppTheme.isDark ? Colors.amberAccent : const Color(0xFFB45309);

  static Color get _mgmtIpColor =>
      AppTheme.isDark ? Colors.lightGreenAccent : const Color(0xFF047857);

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();
    final selected = vm.selectedDiscovery;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inspector Body (Height 230px if selected)
          if (selected != null)
            SizedBox(
              height: 230,
              child: Column(
                children: [
                  // Inspector Tab Header Row
                  _buildInspectorHeader(context, selected, vm),
                  // Tab Views
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSummaryTab(context, selected),
                        _buildRawTlvsTab(context, selected),
                        _buildHexInspectorTab(context, selected),
                        _buildCliPreviewTab(context, vm),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Persistent Bottom Status Bar
          _buildStatusBar(context, vm),
        ],
      ),
    );
  }

  Widget _buildInspectorHeader(
    BuildContext context,
    SwitchPortDiscovery item,
    SocketScoutViewModel vm,
  ) {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(item.timestamp);
    final protoColor = _protocolColor(item.protocol);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Protocol Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: protoColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: protoColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              item.protocol.label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: protoColor,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Switch & Port summary
          Text(
            '${item.displayName}  •  ${item.portId}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),

          Text(
            timeStr,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),

          const SizedBox(width: 16),

          // Tabs
          Expanded(
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: AppTheme.primaryAccent,
              labelColor: AppTheme.textPrimary,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(text: 'SUMMARY'),
                Tab(text: 'RAW TLV TREE'),
                Tab(text: 'HEX / ASCII DUMP'),
                Tab(text: 'CLI COMMAND'),
              ],
            ),
          ),

          // Add / Edit in Shared Device Library
          IconButton(
            tooltip: 'Add / Edit in Shared Device Library',
            icon: Icon(
              Icons.bookmark_add_outlined,
              size: 15,
              color: AppTheme.success,
            ),
            onPressed: () {
              EditDeviceDialog.showForDiscovery(
                context,
                item,
                onSaved: vm.notifyDeviceUpdated,
              );
            },
          ),

          // Copy Summary Button
          IconButton(
            tooltip: 'Copy Switch Port Details',
            icon: Icon(Icons.copy, size: 14, color: AppTheme.textSecondary),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.summaryDescription));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied switch summary to clipboard'),
                ),
              );
            },
          ),

          // Close Inspector
          IconButton(
            tooltip: 'Close Inspector',
            icon: Icon(Icons.close, size: 15, color: AppTheme.textMuted),
            onPressed: () => vm.selectDiscovery(null),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab(BuildContext context, SwitchPortDiscovery item) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          _buildFieldCard(
            'Switch Hostname',
            item.switchHostname,
            isSelectable: true,
          ),
          _buildFieldCard(
            'Physical Port ID',
            item.portId,
            isSelectable: true,
            isMono: true,
            highlightColor: AppTheme.primaryAccent,
          ),
          _buildFieldCard(
            'Hardware Platform / Model',
            item.switchModel,
            isSelectable: true,
          ),
          if (item.portDescription != null)
            _buildFieldCard(
              'Port Description',
              item.portDescription!,
              isSelectable: true,
            ),
          _buildFieldCard(
            'Active VLAN / PVID',
            item.formattedVlan,
            isSelectable: true,
            highlightColor: _vlanColor,
          ),
          if (item.managementIp != null)
            _buildFieldCard(
              'Management IP',
              item.managementIp!,
              isSelectable: true,
              isMono: true,
              highlightColor: _mgmtIpColor,
            ),
          if (item.chassisId != null)
            _buildFieldCard(
              'Chassis ID (MAC)',
              item.chassisId!,
              isSelectable: true,
              isMono: true,
            ),
          _buildFieldCard(
            'Shared Device DB',
            item.isDemo
                ? 'Demo preset (ignored by Shared Device DB)'
                : 'Stored as Switch (auto-promotes in Route Scout)',
            highlightColor: item.isDemo ? AppTheme.warning : AppTheme.success,
          ),
          _buildFieldCard('Hold-time (TTL)', '${item.ttl} seconds'),
          if (item.capabilities.isNotEmpty)
            _buildFieldCard(
              'System Capabilities',
              item.capabilities.join(', '),
            ),
          if (item.powerMdi != null)
            _buildFieldCard('PoE / Power Via MDI', item.powerMdi!),
          if (item.linkAggregation != null)
            _buildFieldCard('Link Aggregation (LAG)', item.linkAggregation!),
          if (item.mtu != null)
            _buildFieldCard('MTU / Max Frame', '${item.mtu} bytes'),
          if (item.duplex != null) _buildFieldCard('Duplex / PHY', item.duplex!),
          if (item.vtpDomain != null)
            _buildFieldCard('VTP Domain', item.vtpDomain!),
          _buildFieldCard('Ingress Adapter', item.interfaceName, isMono: true),
        ],
      ),
    );
  }

  Widget _buildFieldCard(
    String label,
    String value, {
    bool isSelectable = false,
    bool isMono = false,
    Color? highlightColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.inputFill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          if (isSelectable)
            SelectableText(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: isMono ? 'monospace' : null,
                color: highlightColor ?? AppTheme.textPrimary,
              ),
            )
          else
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: isMono ? 'monospace' : null,
                color: highlightColor ?? AppTheme.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRawTlvsTab(BuildContext context, SwitchPortDiscovery item) {
    if (item.rawTlvs.isEmpty) {
      return Center(
        child: Text(
          'No TLVs recorded for this entry.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: item.rawTlvs.length,
      separatorBuilder: (ctx, idx) =>
          Divider(height: 1, color: AppTheme.border),
      itemBuilder: (ctx, idx) {
        final tlv = item.rawTlvs[idx];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  'T: ${tlv.type}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
                child: Text(
                  tlv.typeName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SelectableText(
                  tlv.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${tlv.length} bytes',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHexInspectorTab(BuildContext context, SwitchPortDiscovery item) {
    if (item.rawHex.isEmpty) {
      return Center(
        child: Text(
          'No raw byte dump available.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      color: AppTheme.isDark ? const Color(0xFF0D1117) : AppTheme.surfaceHigh,
      child: SelectableText(
        item.rawHex,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.35,
          color: AppTheme.isDark
              ? const Color(0xFFC9D1D9)
              : AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCliPreviewTab(BuildContext context, SocketScoutViewModel vm) {
    final cmd = vm.generatedCommandLine.isNotEmpty
        ? vm.generatedCommandLine
        : 'tcpdump -i ${vm.selectedAdapter?.name ?? 'eth0'} -U -s 0 -w - "${CaptureService.bpfFilter}"';

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.isDark
              ? const Color(0xFF0F141C)
              : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.isDark
                ? const Color(0xFF30363D)
                : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.terminal, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Generated Command',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    side: BorderSide(
                      color: AppTheme.isDark
                          ? const Color(0xFF30363D)
                          : AppTheme.inputBorder,
                    ),
                  ),
                  icon: Icon(
                    Icons.copy,
                    size: 12,
                    color: AppTheme.textSecondary,
                  ),
                  label: const Text(
                    'Copy Command',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: cmd));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied CLI command to clipboard'),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              cmd,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.isDark
                    ? const Color(0xFF58A6FF)
                    : AppTheme.accent,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Streams live Layer 2 multicast frames (LLDP 0x88CC & CDP 0x2000) directly into the binary dissector pipe.',
              style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, SocketScoutViewModel vm) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBg,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Adapter Indicator
            Icon(Icons.network_check, size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 6),
            Text(
              'Adapter: ${vm.selectedAdapter?.name ?? 'None'}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),

            const SizedBox(width: 14),
            VerticalDivider(width: 1, color: AppTheme.border),
            const SizedBox(width: 14),

            // Total Discoveries
            Text(
              'Showing ${vm.discoveries.length} of ${vm.totalDiscoveriesCount} switch announcements',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),

            const SizedBox(width: 14),
            VerticalDivider(width: 1, color: AppTheme.border),
            const SizedBox(width: 14),

            // Packets count
            Text(
              'Frames received: ${vm.framesReceived}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),

            const SizedBox(width: 14),
            VerticalDivider(width: 1, color: AppTheme.border),
            const SizedBox(width: 14),

            // Status Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: (vm.isListening ? AppTheme.success : AppTheme.textMuted)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      (vm.isListening ? AppTheme.success : AppTheme.textMuted)
                          .withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                vm.isListening ? 'LISTENING' : 'IDLE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color:
                      vm.isListening ? AppTheme.success : AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
