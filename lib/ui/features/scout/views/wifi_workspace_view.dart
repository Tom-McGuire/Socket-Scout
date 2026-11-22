import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/wifi_ap_discovery.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';
import 'dialogs/edit_device_dialog.dart';

/// Tier-4 workspace rendered automatically when a Wi-Fi adapter is selected.
class WifiWorkspaceView extends StatelessWidget {
  const WifiWorkspaceView({
    super.key,
    this.heroCardKey,
    this.historyTableKey,
  });

  final GlobalKey? heroCardKey;
  final GlobalKey? historyTableKey;

  static Color bandColor(WifiBand band) {
    switch (band) {
      case WifiBand.band24:
        return AppTheme.isDark
            ? const Color(0xFFFBBF24)
            : const Color(0xFFB45309);
      case WifiBand.band5:
        return AppTheme.isDark
            ? const Color(0xFF38BDF8)
            : const Color(0xFF0369A1);
      case WifiBand.band6:
        return AppTheme.isDark
            ? const Color(0xFFA78BFA)
            : const Color(0xFF6D28D9);
      case WifiBand.unknown:
        return AppTheme.textSecondary;
    }
  }

  static Color rssiColor(int? rssiDbm) {
    if (rssiDbm == null) return AppTheme.textSecondary;
    if (rssiDbm >= -55) return AppTheme.success;
    if (rssiDbm >= -67) {
      return AppTheme.isDark
          ? const Color(0xFF38BDF8)
          : const Color(0xFF0369A1);
    }
    if (rssiDbm >= -75) return AppTheme.warning;
    return AppTheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();
    final items = vm.wifiDiscoveries;

    if (items.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    final heroItem = vm.selectedWifiDiscovery ?? vm.latestWifiDiscovery;

    return Column(
      children: [
        if (heroItem != null) _buildHeroApCard(context, vm, heroItem),
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
                      final isSelected = item == vm.selectedWifiDiscovery;
                      return _buildTableRow(
                        context,
                        vm,
                        item,
                        isSelected,
                        () => vm.selectWifiDiscovery(item),
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

  Widget _buildHeroApCard(
    BuildContext context,
    SocketScoutViewModel vm,
    WifiApDiscovery item,
  ) {
    final bColor = bandColor(item.band);
    final sigColor = rssiColor(item.rssiDbm);
    final isDemoBadge = item.isDemo && !item.hasCustomName;
    final badgeColor = isDemoBadge ? AppTheme.warning : AppTheme.success;

    return GestureDetector(
      key: heroCardKey,
      onSecondaryTapUp: (details) =>
          _showWifiContextMenu(context, vm, item, details.globalPosition),
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
                // AP Icon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: bColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(Icons.wifi_tethering, size: 22, color: bColor),
                ),
                const SizedBox(width: 14),

                // AP Name, Band Badge & Shared DB Badge
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SelectableText(
                            item.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: bColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: bColor.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              item.band.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: bColor,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: item.isDemo
                                ? 'Demo preset (not in shared library). Right-click or tap to add.'
                                : 'Right-click or tap to edit Access Point in Shared Library',
                            child: InkWell(
                              onTap: () =>
                                  EditDeviceDialog.showForWifiDiscovery(
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
                                          ? Icons.wifi_tethering
                                          : (item.isDemo
                                              ? Icons.science_outlined
                                              : Icons.wifi_tethering),
                                      size: 10,
                                      color: badgeColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.hasCustomName
                                          ? 'CUSTOM IDENTITY'
                                          : (item.isDemo
                                              ? 'DEMO PRESET'
                                              : 'SHARED DB • ACCESS POINT'),
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
                        'SSID: ${item.ssid}  •  BSSID: ${item.normalizedBssid}'
                        '${item.resolvedVendor != null ? '  •  ${item.resolvedVendor}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Signal Strength Badge (Prominent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sigColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: sigColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'SIGNAL (${item.signalQualityLabel.toUpperCase()})',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        item.rssiDbm != null
                            ? '${item.rssiDbm} dBm'
                            : item.formattedRssi,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: sigColor,
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

            // RF Parameter Row
            Wrap(
              spacing: 20,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildHeroAttribute(
                  icon: Icons.cell_tower,
                  label: 'Channel / Band',
                  value: item.formattedChannel,
                  valueColor: bColor,
                ),
                _buildHeroAttribute(
                  icon: Icons.speed,
                  label: 'PHY Rate',
                  value: item.formattedLinkSpeed,
                  isMonospace: true,
                ),
                if (item.wifiStandard != null)
                  _buildHeroAttribute(
                    icon: Icons.wifi,
                    label: 'Standard',
                    value: item.wifiStandard!,
                  ),
                if (item.securityType != null)
                  _buildHeroAttribute(
                    icon: Icons.lock_outline,
                    label: 'Security',
                    value: item.securityType!,
                  ),
                if (item.effectiveSnrDb != null)
                  _buildHeroAttribute(
                    icon: Icons.graphic_eq,
                    label: 'SNR',
                    value: '${item.effectiveSnrDb} dB',
                    isMonospace: true,
                  ),
                _buildHeroAttribute(
                  icon: Icons.radar,
                  label: 'Neighbors',
                  value: '${item.neighbors.length} APs',
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
          SizedBox(width: 75, child: Text('BAND', style: headerStyle)),
          SizedBox(
            width: 220,
            child: Text('AP NAME / BSSID', style: headerStyle),
          ),
          SizedBox(width: 150, child: Text('SSID', style: headerStyle)),
          SizedBox(width: 90, child: Text('CHANNEL', style: headerStyle)),
          SizedBox(width: 95, child: Text('RSSI', style: headerStyle)),
          SizedBox(width: 135, child: Text('LINK SPEED', style: headerStyle)),
          Expanded(child: Text('VENDOR', style: headerStyle)),
        ],
      ),
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    SocketScoutViewModel vm,
    WifiApDiscovery item,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(item.timestamp);
    final bColor = bandColor(item.band);
    final sigColor = rssiColor(item.rssiDbm);

    return InkWell(
      onTap: onTap,
      onSecondaryTapUp: (details) {
        vm.selectWifiDiscovery(item);
        _showWifiContextMenu(context, vm, item, details.globalPosition);
      },
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: isSelected
            ? AppTheme.primaryAccent.withValues(alpha: 0.15)
            : Colors.transparent,
        child: Row(
          children: [
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
            SizedBox(
              width: 75,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: bColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: bColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    item.band.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: bColor,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 220,
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
            SizedBox(
              width: 150,
              child: Text(
                item.ssid,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryAccent,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                item.channel != null ? 'Ch ${item.channel}' : '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            SizedBox(
              width: 95,
              child: Text(
                item.rssiDbm != null ? '${item.rssiDbm} dBm' : '—',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: sigColor,
                ),
              ),
            ),
            SizedBox(
              width: 135,
              child: Text(
                item.formattedLinkSpeed,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: Text(
                item.resolvedVendor ?? 'Unknown',
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
              isListening ? Icons.wifi_find : Icons.wifi_tethering,
              size: 56,
              color: isListening
                  ? AppTheme.success
                  : AppTheme.primaryAccent.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isListening
                ? 'Scouting Wi-Fi Access Points...'
                : 'Wi-Fi Access Point Scout Mode Ready',
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
                  ? 'Polling ${vm.selectedAdapter?.name ?? 'Wi-Fi adapter'} for associated Access Point BSSID, RF band/channel, RSSI signal strength, and roaming changes...'
                  : 'Connect ${vm.selectedAdapter?.name ?? 'your Wi-Fi adapter'} to a wireless network and click "Start Scouting" to identify the connected Access Point, or load built-in Wi-Fi demo presets.',
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
                  isListening ? 'STOP SCOUTING' : 'START SCOUTING',
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

  void _showWifiContextMenu(
    BuildContext context,
    SocketScoutViewModel vm,
    WifiApDiscovery item,
    Offset position,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

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
                      ? 'Edit AP Identity (${item.displayName})...'
                      : (item.isDemo
                          ? 'Add Demo AP to Shared Library...'
                          : 'Add to Device Library (${item.displayName})...'),
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
          value: 'copy_bssid',
          child: Row(
            children: [
              Icon(Icons.fingerprint, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copy BSSID (${item.normalizedBssid})',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_ssid',
          child: Row(
            children: [
              Icon(Icons.wifi, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copy SSID (${item.ssid})',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_channel',
          child: Row(
            children: [
              Icon(Icons.cell_tower, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copy Channel / Band (${item.formattedChannel})',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_rssi',
          child: Row(
            children: [
              Icon(Icons.signal_wifi_4_bar,
                  size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Copy RSSI (${item.formattedRssi})',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_all',
          child: Row(
            children: [
              Icon(Icons.copy_all, size: 15, color: AppTheme.textSecondary),
              const SizedBox(width: 10),
              Text(
                'Copy All AP Details',
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      if (value == 'edit_shared') {
        EditDeviceDialog.showForWifiDiscovery(
          context,
          item,
          onSaved: vm.notifyDeviceUpdated,
        );
      } else if (value == 'copy_bssid') {
        _copyText(context, item.normalizedBssid, 'BSSID');
      } else if (value == 'copy_ssid') {
        _copyText(context, item.ssid, 'SSID');
      } else if (value == 'copy_channel') {
        _copyText(context, item.formattedChannel, 'Channel / Band');
      } else if (value == 'copy_rssi') {
        _copyText(context, item.formattedRssi, 'RSSI');
      } else if (value == 'copy_all') {
        _copyText(context, item.summaryDescription, 'AP details');
      }
    });
  }

  void _copyText(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $label to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
