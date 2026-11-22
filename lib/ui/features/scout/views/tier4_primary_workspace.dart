import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/switch_port_discovery.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';
import 'dialogs/edit_device_dialog.dart';
import 'wifi_workspace_view.dart';

class Tier4PrimaryWorkspace extends StatelessWidget {
  const Tier4PrimaryWorkspace({
    super.key,
    this.heroCardKey,
    this.historyTableKey,
  });

  final GlobalKey? heroCardKey;
  final GlobalKey? historyTableKey;

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
    if (vm.isWifiMode) {
      return WifiWorkspaceView(
        heroCardKey: heroCardKey,
        historyTableKey: historyTableKey,
      );
    }

    final items = vm.discoveries;

    if (items.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    final heroItem = vm.selectedDiscovery ?? vm.latestDiscovery;

    return Column(
      children: [
        // Top Hero Switch Card (Quick Glance)
        if (heroItem != null) _buildHeroSwitchCard(context, vm, heroItem),

        // Data Table Header & List wrapped in key for Guided Tour Spotlight
        Expanded(
          child: Column(
            key: historyTableKey,
            children: [
              _buildTableHeader(context),
              Expanded(
                child: Container(
                  color: AppTheme.surface,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (ctx, idx) =>
                        Divider(height: 1, color: AppTheme.border),
                    itemBuilder: (ctx, idx) {
                      final item = items[idx];
                      final isSelected = item == vm.selectedDiscovery;
                      return _buildTableRow(
                        context,
                        vm,
                        item,
                        isSelected,
                        () => vm.selectDiscovery(item),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSwitchCard(
    BuildContext context,
    SocketScoutViewModel vm,
    SwitchPortDiscovery item,
  ) {
    final protoColor = _protocolColor(item.protocol);
    final isDemoBadge = item.isDemo && !item.hasCustomName;
    final badgeColor = isDemoBadge ? AppTheme.warning : AppTheme.success;

    return GestureDetector(
      key: heroCardKey,
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, vm, item, details.globalPosition),
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hardware Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: protoColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: protoColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.dns, size: 22, color: protoColor),
                ),
                const SizedBox(width: 14),

                // Switch Name & Model
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SelectableText(
                            item.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: protoColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: protoColor.withValues(alpha: 0.4),
                              ),
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
                          const SizedBox(width: 6),
                          Tooltip(
                            message: item.isDemo
                                ? 'Demo preset (not in shared library). Right-click or tap to add.'
                                : 'Right-click or tap to edit device in Shared Library',
                            child: InkWell(
                              onTap: () => EditDeviceDialog.showForDiscovery(
                                context,
                                item,
                                onSaved: vm.notifyDeviceUpdated,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: badgeColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item.hasCustomName
                                          ? Icons.hub_outlined
                                          : (item.isDemo
                                              ? Icons.science_outlined
                                              : Icons.hub_outlined),
                                      size: 10,
                                      color: badgeColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.hasCustomName
                                          ? 'CUSTOM IDENTITY'
                                          : (item.isDemo
                                              ? 'DEMO PRESET'
                                              : 'SHARED DB • SWITCH'),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                        color: badgeColor,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.edit_note,
                                      size: 11,
                                      color: badgeColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.hasCustomName
                            ? '${item.switchHostname} • ${item.switchModel}'
                            : item.switchModel,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Physical Port Badge (Prominent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'PHYSICAL PORT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        item.portId,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 10),

            // Technical Parameter Row
            Wrap(
              spacing: 20,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // VLAN ID
                _buildHeroAttribute(
                  icon: Icons.tag,
                  label: 'Active VLAN',
                  value: item.formattedVlan,
                  valueColor: _vlanColor,
                ),

                // Management IP
                if (item.managementIp != null)
                  _buildHeroAttribute(
                    icon: Icons.language,
                    label: 'Management IP',
                    value: item.managementIp!,
                    valueColor: _mgmtIpColor,
                    isMonospace: true,
                    canCopy: true,
                    context: context,
                  ),

                // Chassis MAC
                if (item.chassisId != null)
                  _buildHeroAttribute(
                    icon: Icons.fingerprint,
                    label: 'Chassis ID (MAC)',
                    value: item.chassisId!,
                    isMonospace: true,
                  ),

                // PoE Power
                if (item.powerMdi != null)
                  _buildHeroAttribute(
                    icon: Icons.bolt,
                    label: 'Power / PoE',
                    value: item.powerMdi!,
                  ),

                // Capabilities
                if (item.capabilities.isNotEmpty)
                  _buildHeroAttribute(
                    icon: Icons.device_hub,
                    label: 'Capabilities',
                    value: item.capabilities.join(', '),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroAttribute({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isMonospace = false,
    bool canCopy = false,
    BuildContext? context,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            fontFamily: isMonospace ? 'monospace' : null,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
        if (canCopy && context != null) ...[
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Copied $value to clipboard'),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Icon(Icons.copy, size: 12, color: AppTheme.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _buildTableHeader(BuildContext context) {
    final headerStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.6,
      color: AppTheme.textSecondary,
    );

    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        border: Border(
          top: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text('TIMESTAMP', style: headerStyle)),
          SizedBox(width: 70, child: Text('PROTO', style: headerStyle)),
          SizedBox(
            width: 200,
            child: Text('SWITCH HOSTNAME', style: headerStyle),
          ),
          SizedBox(width: 160, child: Text('PORT ID', style: headerStyle)),
          SizedBox(width: 90, child: Text('VLAN', style: headerStyle)),
          SizedBox(width: 130, child: Text('MGMT IP', style: headerStyle)),
          Expanded(child: Text('MODEL / PLATFORM', style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    SocketScoutViewModel vm,
    SwitchPortDiscovery item,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(item.timestamp);
    final protoColor = _protocolColor(item.protocol);

    return InkWell(
      onTap: onTap,
      onSecondaryTapUp: (details) {
        vm.selectDiscovery(item);
        _showContextMenu(context, vm, item, details.globalPosition);
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: isSelected
            ? AppTheme.primaryAccent.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
            // Timestamp
            SizedBox(
              width: 140,
              child: Text(
                timeStr,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),

            // Protocol Badge
            SizedBox(
              width: 70,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: protoColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: protoColor.withValues(alpha: 0.3)),
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
              ),
            ),

            // Switch Hostname / Custom Name
            SizedBox(
              width: 200,
              child: Row(
                children: [
                  if (item.hasCustomName) ...[
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                  Expanded(
                    child: Text(
                      item.displayName,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: item.hasCustomName
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Port ID
            SizedBox(
              width: 160,
              child: Text(
                item.portId,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryAccent,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // VLAN ID
            SizedBox(
              width: 90,
              child: Text(
                item.vlanId != null ? 'VLAN ${item.vlanId}' : '—',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: item.vlanId != null ? _vlanColor : AppTheme.textMuted,
                ),
              ),
            ),

            // Management IP
            SizedBox(
              width: 130,
              child: Text(
                item.managementIp ?? '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: item.managementIp != null
                      ? _mgmtIpColor
                      : AppTheme.textMuted,
                ),
              ),
            ),

            // Model / Platform
            Expanded(
              child: Text(
                item.switchModel,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, SocketScoutViewModel vm) {
    final isListening = vm.isListening;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isListening
                  ? AppTheme.success.withValues(alpha: 0.12)
                  : AppTheme.primaryAccent.withValues(alpha: 0.12),
              border: Border.all(
                color: isListening
                    ? AppTheme.success.withValues(alpha: 0.35)
                    : AppTheme.primaryAccent.withValues(alpha: 0.35),
                width: 2,
              ),
            ),
            child: Icon(
              isListening ? Icons.settings_input_antenna : Icons.radar,
              size: 56,
              color: isListening
                  ? AppTheme.success
                  : AppTheme.primaryAccent.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isListening
                ? 'Listening for Switch Announcements...'
                : 'No Switch Discovery Packets Received',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 520,
            child: Text(
              isListening
                  ? 'Listening on ${vm.selectedAdapter?.name ?? 'selected adapter'}. Switches transmit LLDP and CDP frames every 30 to 60 seconds (or immediately on link up). Waiting for frames...'
                  : 'Connect your Ethernet cable to a managed switch port and click "Start Listening", or load built-in demo packets to explore features.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isListening ? AppTheme.error : AppTheme.success,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: Icon(
                  isListening ? Icons.stop : Icons.play_arrow,
                  size: 16,
                ),
                label: Text(
                  isListening ? 'STOP LISTENING' : 'START LISTENING',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => vm.toggleListening(),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  side: BorderSide(color: AppTheme.borderInput),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: AppTheme.warning,
                ),
                label: Text(
                  'LOAD DEMO DATA',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                onPressed: isListening ? null : () => vm.startDemoWalkthrough(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    SocketScoutViewModel vm,
    SwitchPortDiscovery item,
    Offset position,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final mac = item.effectiveMacAddress ?? item.chassisId;
    final hasMac = mac != null && mac.trim().isNotEmpty;
    final hasMgmtIp =
        item.managementIp != null && item.managementIp!.trim().isNotEmpty;
    final hasVlan = item.vlanId != null;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      color: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.border),
      ),
      items: [
        PopupMenuItem(
          value: 'edit_shared',
          child: Row(
            children: [
              Icon(
                item.hasCustomName
                    ? Icons.edit_note
                    : Icons.bookmark_add_outlined,
                size: 16,
                color: AppTheme.success,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.hasCustomName
                      ? 'Edit Device Identity (${item.displayName})...'
                      : (item.isDemo
                          ? 'Add Demo Switch to Shared Library...'
                          : 'Add to Device Library (${item.switchHostname})...'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_hostname',
          child: Row(
            children: [
              Icon(Icons.dns_outlined, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copy Switch Hostname (${item.switchHostname})',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_port',
          child: Row(
            children: [
              Icon(Icons.alt_route, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copy Physical Port (${item.portId})',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (hasMgmtIp)
          PopupMenuItem(
            value: 'copy_mgmt_ip',
            child: Row(
              children: [
                Icon(Icons.language, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Copy Management IP (${item.managementIp})',
                    style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (hasMac)
          PopupMenuItem(
            value: 'copy_mac',
            child: Row(
              children: [
                Icon(Icons.fingerprint, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Copy MAC / Chassis ID ($mac)',
                    style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (hasVlan)
          PopupMenuItem(
            value: 'copy_vlan',
            child: Row(
              children: [
                Icon(Icons.tag, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Copy ${item.formattedVlan}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_summary',
          child: Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 15,
                color: AppTheme.primaryAccent,
              ),
              const SizedBox(width: 10),
              Text(
                'Copy All Switch Details',
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      switch (value) {
        case 'edit_shared':
          EditDeviceDialog.showForDiscovery(
            context,
            item,
            onSaved: vm.notifyDeviceUpdated,
          );
          break;
        case 'copy_hostname':
          Clipboard.setData(ClipboardData(text: item.switchHostname));
          _showCopySnackBar(context, 'Copied hostname: ${item.switchHostname}');
          break;
        case 'copy_port':
          Clipboard.setData(ClipboardData(text: item.portId));
          _showCopySnackBar(context, 'Copied port: ${item.portId}');
          break;
        case 'copy_mgmt_ip':
          if (item.managementIp != null) {
            Clipboard.setData(ClipboardData(text: item.managementIp!));
            _showCopySnackBar(context, 'Copied IP: ${item.managementIp!}');
          }
          break;
        case 'copy_mac':
          if (mac != null) {
            Clipboard.setData(ClipboardData(text: mac));
            _showCopySnackBar(context, 'Copied MAC: $mac');
          }
          break;
        case 'copy_vlan':
          if (item.vlanId != null) {
            Clipboard.setData(ClipboardData(text: item.vlanId.toString()));
            _showCopySnackBar(context, 'Copied VLAN: ${item.vlanId}');
          }
          break;
        case 'copy_summary':
          Clipboard.setData(ClipboardData(text: item.summaryDescription));
          _showCopySnackBar(context, 'Copied switch details to clipboard');
          break;
      }
    });
  }

  void _showCopySnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
