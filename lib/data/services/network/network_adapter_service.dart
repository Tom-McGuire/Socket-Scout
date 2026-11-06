import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../domain/models/network_adapter_info.dart';

class NetworkAdapterService {
  static Future<List<NetworkAdapterInfo>> getAvailableAdapters() async {
    final adapterMap = <String, NetworkAdapterInfo>{};

    // 1. Enumerate standard interfaces with IP addresses via NetworkInterface
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(milliseconds: 600), onTimeout: () => []);

      for (final iface in interfaces) {
        String? ipv4;
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ipv4 = addr.address;
            break;
          }
        }

        adapterMap[iface.name] = NetworkAdapterInfo(
          name: iface.name,
          displayName: iface.name,
          ipAddress: ipv4,
          isLoopback: false,
          isUp: true,
        );
      }
    } catch (e) {
      debugPrint('NetworkInterface.list enumeration error: $e');
    }

    // 2. Discover unnumbered physical adapters (e.g. newly plugged Ethernet cable without IP yet)
    if (Platform.isLinux) {
      try {
        final sysNetDir = Directory('/sys/class/net');
        if (sysNetDir.existsSync()) {
          for (final entity in sysNetDir.listSync()) {
            final ifName = entity.path.split('/').last;
            if (ifName == 'lo' || ifName.startsWith('docker') || ifName.startsWith('veth')) {
              continue;
            }
            if (!adapterMap.containsKey(ifName)) {
              adapterMap[ifName] = NetworkAdapterInfo(
                name: ifName,
                displayName: ifName,
                ipAddress: null, // No IP assigned yet
                isLoopback: false,
                isUp: true,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('/sys/class/net enumeration error: $e');
      }
    }

    final result = adapterMap.values.toList();
    // Sort adapters: physical ethernet/wifi first, then alphabetical
    result.sort((a, b) => a.name.compareTo(b.name));

    // Add 'any' interface on Linux/macOS
    result.insert(0, NetworkAdapterInfo.all);

    return result;
  }
}
