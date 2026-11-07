import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';

class Tier2StatusBanner extends StatelessWidget {
  const Tier2StatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();

    // 1. Error Banner
    if (vm.lastError != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppTheme.error.withValues(alpha: 0.15),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: AppTheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                vm.lastError!,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
              ),
            ),
            if (vm.lastError!.contains('sudo setcap')) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  side: const BorderSide(color: AppTheme.borderInput),
                ),
                icon: const Icon(Icons.copy, size: 13, color: Colors.white70),
                label: const Text('Copy Fix Command', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  const cmd = 'sudo setcap cap_net_raw,cap_net_admin=eip \$(which tcpdump)';
                  Clipboard.setData(const ClipboardData(text: cmd));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied setcap command to clipboard')),
                  );
                },
              ),
            ],
          ],
        ),
      );
    }

    // 2. Active Listening Indicator
    if (vm.isListening) {
      final elapsed = vm.elapsedSeconds;
      final mins = (elapsed ~/ 60).toString().padLeft(2, '0');
      final secs = (elapsed % 60).toString().padLeft(2, '0');

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.12),
          border: Border(
            bottom: BorderSide(color: AppTheme.success.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'LISTENING ON ${vm.selectedAdapter?.name.toUpperCase() ?? 'INTERFACE'}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '•  Waiting for switch multicast frames (LLDP / CDP announce every 30-60s)  •  Elapsed: $mins:$secs  •  Frames: ${vm.framesReceived}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.white70,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            if (vm.latestDiscovery != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Connected: ${vm.latestDiscovery!.switchHostname} [${vm.latestDiscovery!.portId}]',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
