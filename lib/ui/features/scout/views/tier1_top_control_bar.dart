import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';

class Tier1TopControlBar extends StatelessWidget {
  const Tier1TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // App Logo & Title
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primaryAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppTheme.primaryAccent.withValues(alpha: 0.3),
              ),
            ),
            child: const Icon(
              Icons.hub,
              size: 20,
              color: AppTheme.primaryAccent,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'SOCKET SCOUT',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
              Text(
                'Switch Port Identifier (LLDP / CDP)',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Interface Selector Dropdown
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.inputFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.borderInput),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_ethernet, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<NetworkAdapterInfo>(
                    value: vm.selectedAdapter,
                    dropdownColor: AppTheme.surfaceContainer,
                    icon: const Icon(Icons.arrow_drop_down, size: 18),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    items: vm.adapters.map((adapter) {
                      return DropdownMenuItem<NetworkAdapterInfo>(
                        value: adapter,
                        child: Text(adapter.label),
                      );
                    }).toList(),
                    onChanged: vm.isListening ? null : (a) => vm.selectAdapter(a),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Network Adapters',
                  icon: const Icon(Icons.refresh, size: 14, color: Colors.white60),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: vm.isListening ? null : () => vm.refreshAdapters(),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Start / Stop Listening Button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: vm.isListening ? AppTheme.error : AppTheme.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: Icon(
              vm.isListening ? Icons.stop : Icons.play_arrow,
              size: 16,
            ),
            label: Text(
              vm.isListening ? 'STOP LISTENING' : 'START LISTENING',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            onPressed: () => vm.toggleListening(),
          ),

          const SizedBox(width: 8),

          // Demo Mode Button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              side: const BorderSide(color: AppTheme.borderInput),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.science_outlined, size: 15, color: Colors.amber),
            label: const Text(
              'DEMO PRESETS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
            ),
            onPressed: () {
              vm.loadDemoData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Injected Cisco, Netgear & Aruba L2 discovery demo packets'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),

          const SizedBox(width: 8),

          // Open PCAP File Button
          IconButton(
            tooltip: 'Open PCAP / PCAPNG file',
            icon: const Icon(Icons.folder_open, size: 18, color: Colors.white70),
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
          ),

          // Export Popup Menu
          PopupMenuButton<String>(
            tooltip: 'Export Discovery Data',
            icon: const Icon(Icons.file_download_outlined, size: 18, color: Colors.white70),
            color: AppTheme.surfaceContainer,
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
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'report',
                child: Row(
                  children: [
                    Icon(Icons.description, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Copy Engineering Report (Text)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text('Copy CSV to Clipboard', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
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
          ),

          // Clear Button
          IconButton(
            tooltip: 'Clear Discovery History',
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.white54),
            onPressed: vm.totalDiscoveriesCount == 0 ? null : () => vm.clearAll(),
          ),
        ],
      ),
    );
  }
}
