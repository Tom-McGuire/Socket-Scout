import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';
import 'dialogs/device_library_dialog.dart';

/// Tier-1 Top Control Bar conforming strictly to the Network Suite
/// 5-Zone Standardization Specification (52px fixed height, canonical layout).
class Tier1TopControlBar extends StatelessWidget {
  const Tier1TopControlBar({
    super.key,
    this.zone2Key,
    this.zone3Key,
  });

  final GlobalKey? zone2Key;
  final GlobalKey? zone3Key;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();
    final isDemo = vm.isDemoMode;
    final isWifi = vm.isWifiMode;
    final hasItems = isWifi
        ? vm.totalWifiDiscoveriesCount > 0
        : vm.totalDiscoveriesCount > 0;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // ==================== ZONE 1: BRANDING ====================
          SizedBox(
            width: 32,
            height: 32,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/app_icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 32,
                  height: 32,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(
                    Icons.hub,
                    size: 18,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SOCKET SCOUT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                isWifi
                    ? 'Wi-Fi Access Point Scout (BSSID / RF)'
                    : 'Switch Port Identifier (LLDP / CDP)',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // ==================== ZONE 2: INTERFACE & TARGET ====================
          Row(
            key: zone2Key,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 32,
                width: 220,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.inputBorder),
                ),
                child: Row(
                  children: [
                    Icon(
                      isWifi ? Icons.wifi : Icons.settings_ethernet,
                      size: 16,
                      color: isWifi
                          ? AppTheme.primaryAccent
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<NetworkAdapterInfo>(
                          value: vm.adapters.contains(vm.selectedAdapter)
                              ? vm.selectedAdapter
                              : null,
                          dropdownColor: AppTheme.surfaceElevated,
                          isDense: true,
                          isExpanded: true,
                          icon: Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: AppTheme.textSecondary,
                          ),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                          ),
                          selectedItemBuilder: (ctx) => vm.adapters.map((adapter) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                adapter.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            );
                          }).toList(),
                          items: vm.adapters.map((adapter) {
                            return DropdownMenuItem<NetworkAdapterInfo>(
                              value: adapter,
                              child: Row(
                                children: [
                                  Icon(
                                    adapter.isWifi
                                        ? Icons.wifi
                                        : Icons.settings_ethernet,
                                    size: 14,
                                    color: adapter.isWifi
                                        ? AppTheme.primaryAccent
                                        : AppTheme.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      adapter.label,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged:
                              vm.isListening ? null : (a) => vm.selectAdapter(a),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Refresh Interfaces',
                icon: Icon(
                  Icons.refresh,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: vm.isListening ? null : () => vm.refreshAdapters(),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // ==================== ZONE 3: PRIMARY ACTIONS ====================
          FilledButton.icon(
            key: zone3Key,
            onPressed: () => vm.toggleListening(),
            style: FilledButton.styleFrom(
              backgroundColor:
                  vm.isListening ? AppTheme.error : AppTheme.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            icon: Icon(
              vm.isListening ? Icons.stop : Icons.play_arrow,
              size: 17,
            ),
            label: Text(
              vm.isListening
                  ? (isWifi ? 'STOP SCOUTING' : 'STOP LISTENING')
                  : (isWifi ? 'START SCOUTING' : 'START LISTENING'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),

          const Spacer(),

          // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
          // Open PCAP File Button (Wired LLDP/CDP mode)
          if (!isWifi) ...[
            OutlinedButton.icon(
              onPressed: () async {
                final result = await FilePicker.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['pcap', 'pcapng', 'cap'],
                );
                if (result.isNotEmpty && result.single.path != null) {
                  final file = File(result.single.path!);
                  final count = await vm.importPcapFile(file);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                            Text('Imported $count L2 switch announcements'),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.folder_open, size: 15),
              label: const Text('Open PCAP', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.inputBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Device Library Button
          OutlinedButton.icon(
            onPressed: () => DeviceLibraryDialog.show(context),
            icon: const Icon(Icons.devices, size: 15),
            label: const Text('Device Library', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textPrimary,
              side: BorderSide(color: AppTheme.inputBorder),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Load Demo / Exit Demo Button
          OutlinedButton.icon(
            onPressed: (!isDemo && vm.isListening)
                ? null
                : (isDemo
                    ? () => vm.endDemoWalkthrough()
                    : () => vm.startDemoWalkthrough()),
            icon: Icon(
              isDemo ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              size: 15,
              color: isDemo ? AppTheme.warning : null,
            ),
            label: Text(
              isDemo ? 'Exit Demo' : 'Load Demo',
              style: TextStyle(
                fontSize: 11,
                color: isDemo ? AppTheme.warning : null,
                fontWeight: isDemo ? FontWeight.w600 : null,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDemo ? AppTheme.warning : AppTheme.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              side: BorderSide(
                color: isDemo
                    ? AppTheme.warning.withValues(alpha: 0.8)
                    : AppTheme.inputBorder,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ==================== ZONE 5: CLEAR & EXPORT ====================
          OutlinedButton.icon(
            onPressed: (vm.isListening || !hasItems)
                ? null
                : () => vm.clearAll(),
            icon: const Icon(Icons.delete_sweep_outlined, size: 15),
            label: const Text('Clear', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  AppTheme.isDark ? Colors.red.shade300 : AppTheme.error,
              side: BorderSide(color: AppTheme.inputBorder),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
          const SizedBox(width: 8),

          PopupMenuButton<String>(
            tooltip: 'Export',
            enabled: hasItems,
            color: AppTheme.surfaceElevated,
            onSelected: (val) {
              if (val == 'csv') {
                final text = vm.exportCsv();
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('CSV copied to clipboard')),
                );
              } else if (val == 'json') {
                final text = vm.exportJson();
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('JSON copied to clipboard')),
                );
              } else if (val == 'report') {
                final text = vm.exportReport();
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Engineering Report copied to clipboard'),
                  ),
                );
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(
                      Icons.description,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Copy Engineering Report (Text)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(
                      Icons.table_chart,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Copy CSV to Clipboard',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    Icon(Icons.code, size: 16, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Copy JSON to Clipboard',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.inputBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.download,
                    size: 15,
                    color: hasItems ? AppTheme.textPrimary : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Export',
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          hasItems ? AppTheme.textPrimary : AppTheme.textMuted,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color:
                        hasItems ? AppTheme.textSecondary : AppTheme.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
