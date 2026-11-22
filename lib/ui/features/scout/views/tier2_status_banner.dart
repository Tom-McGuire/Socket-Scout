import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';

class Tier2StatusBanner extends StatelessWidget {
  const Tier2StatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();

    // 1. Error / Permission Banner
    if (vm.lastError != null) {
      final isPerm = vm.isWifiPermissionBlocked;
      final bannerColor = isPerm ? AppTheme.warning : AppTheme.error;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: bannerColor.withValues(alpha: 0.15),
        child: Row(
          children: [
            Icon(
              isPerm ? Icons.location_off_outlined : Icons.error_outline,
              size: 16,
              color: bannerColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SelectableText(
                vm.lastError!,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            if (vm.lastError!.contains('sudo setcap')) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  side: BorderSide(color: AppTheme.borderInput),
                ),
                icon: Icon(Icons.copy, size: 13, color: AppTheme.textSecondary),
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

    // 2. Active Listening / Wi-Fi Scouting Indicator
    if (vm.isListening) {
      final elapsed = vm.elapsedSeconds;
      final mins = (elapsed ~/ 60).toString().padLeft(2, '0');
      final secs = (elapsed % 60).toString().padLeft(2, '0');

      if (vm.isWifiMode) {
        final latestWifi = vm.latestWifiDiscovery;
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
                decoration: BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'SCOUTING WIFI ON ${vm.selectedAdapter?.name.toUpperCase() ?? 'INTERFACE'}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  latestWifi != null
                      ? '•  SSID: ${latestWifi.ssid}  •  BSSID: ${latestWifi.normalizedBssid}  •  RSSI: ${latestWifi.formattedRssi}  •  Elapsed: $mins:$secs'
                      : '•  Polling wireless association & RF telemetry  •  Elapsed: $mins:$secs  •  Polls: ${vm.wifiPollsCompleted}',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              if (latestWifi != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'AP: ${latestWifi.displayName} [${latestWifi.formattedChannel}]',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
            ],
          ),
        );
      }

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
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'LISTENING ON ${vm.selectedAdapter?.name.toUpperCase() ?? 'INTERFACE'}',
              style: TextStyle(
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
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textSecondary,
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
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
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
