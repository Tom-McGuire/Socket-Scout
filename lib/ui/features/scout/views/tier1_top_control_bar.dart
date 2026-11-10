import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';
import 'dialogs/device_library_dialog.dart';

/// Tier-1 Top Control Bar conforming strictly to the Network Suite
/// 5-Zone Standardization Specification (52px fixed height, canonical layout).
class Tier1TopControlBar extends StatelessWidget {
  const Tier1TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2C2C2C), width: 1),
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
                  child: const Icon(
                    Icons.hub,
                    size: 18,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SOCKET SCOUT',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
              Text(
                'Switch Port Identifier (LLDP / CDP)',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),

          // ==================== ZONE 2: INTERFACE & TARGET ====================
          Container(
            height: 32,
            width: 220,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.inputFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.borderInput),
            ),
            child: Row(
              children: [
                const Icon(Icons.settings_ethernet, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<NetworkAdapterInfo>(
                      value: vm.selectedAdapter,
                      dropdownColor: AppTheme.surfaceContainer,
                      isDense: true,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Colors.white,
                      ),
                      items: vm.adapters.map((adapter) {
                        return DropdownMenuItem<NetworkAdapterInfo>(
                          value: adapter,
                          child: Text(
                            adapter.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: vm.isListening ? null : (a) => vm.selectAdapter(a),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Refresh Interfaces',
            icon: const Icon(Icons.refresh, size: 16, color: Colors.white60),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            onPressed: vm.isListening ? null : () => vm.refreshAdapters(),
          ),
          const SizedBox(width: 12),

          // ==================== ZONE 3: PRIMARY ACTIONS ====================
          FilledButton.icon(
            onPressed: () => vm.toggleListening(),
            style: FilledButton.styleFrom(
              backgroundColor: vm.isListening
                  ? const Color(0xFFEF4444) // Active Red
                  : const Color(0xFF10B981), // Idle Emerald Green (from ARP Scout)
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: Icon(
              vm.isListening ? Icons.stop : Icons.play_arrow,
              size: 17,
            ),
            label: Text(
              vm.isListening ? 'STOP LISTENING' : 'START LISTENING',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),

          const Spacer(),

          // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
          // Open PCAP File Button
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
                    SnackBar(content: Text('Imported $count L2 switch announcements')),
                  );
                }
              }
            },
            icon: const Icon(Icons.folder_open, size: 15),
            label: const Text('Open PCAP', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),

          // Device Library Button
          OutlinedButton.icon(
            onPressed: () => DeviceLibraryDialog.show(context),
            icon: const Icon(Icons.devices, size: 15),
            label: const Text('Device Library', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),

          // Load Demo Button
          OutlinedButton.icon(
            onPressed: vm.isListening
                ? null
                : () {
                    vm.loadDemoData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Injected Cisco, Netgear & Aruba L2 discovery demo packets'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
            icon: const Icon(Icons.play_circle_outline, size: 15),
            label: const Text('Load Demo', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),

          // ==================== ZONE 5: CLEAR & EXPORT ====================
          OutlinedButton.icon(
            onPressed: (vm.isListening || vm.totalDiscoveriesCount == 0)
                ? null
                : () => vm.clearAll(),
            icon: const Icon(Icons.delete_sweep_outlined, size: 15),
            label: const Text('Clear', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade300,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 8),

          PopupMenuButton<String>(
            tooltip: 'Export',
            enabled: vm.totalDiscoveriesCount > 0,
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
                  const SnackBar(content: Text('Engineering Report copied to clipboard')),
                );
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.description, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Copy Engineering Report (Text)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Copy CSV to Clipboard', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'json',
                child: Row(
                  children: [
                    Icon(Icons.code, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Copy JSON to Clipboard', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download, size: 15, color: Colors.white70),
                  SizedBox(width: 6),
                  Text('Export', style: TextStyle(fontSize: 11, color: Colors.white70)),
                  Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
