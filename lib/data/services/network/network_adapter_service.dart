import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../domain/models/network_adapter_info.dart';

class NetworkAdapterService {
  static Future<List<NetworkAdapterInfo>> getAvailableAdapters() async {
    final adapterMap = <String, NetworkAdapterInfo>{};

    // Detect known Wi-Fi adapter names from OS-specific tools
    final osWifiNames = await _detectOsWifiAdapterNames();

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

        final kind = classifyAdapterKind(
          iface.name,
          osWifiNames: osWifiNames,
          hasLinuxWirelessDir: _hasLinuxWirelessDir(iface.name),
        );

        adapterMap[iface.name] = NetworkAdapterInfo(
          name: iface.name,
          displayName: iface.name,
          ipAddress: ipv4,
          isLoopback: false,
          isUp: true,
          kind: kind,
        );
      }
    } catch (e) {
      debugPrint('NetworkInterface.list enumeration error: $e');
    }

    // 2. Discover unnumbered physical adapters (e.g. newly plugged Ethernet cable or unassociated Wi-Fi)
    if (Platform.isLinux) {
      try {
        final sysNetDir = Directory('/sys/class/net');
        if (sysNetDir.existsSync()) {
          for (final entity in sysNetDir.listSync()) {
            final ifName = entity.path.split('/').last;
            if (ifName == 'lo' ||
                ifName.startsWith('docker') ||
                ifName.startsWith('veth')) {
              continue;
            }
            if (!adapterMap.containsKey(ifName)) {
              final kind = classifyAdapterKind(
                ifName,
                osWifiNames: osWifiNames,
                hasLinuxWirelessDir: _hasLinuxWirelessDir(ifName),
              );
              adapterMap[ifName] = NetworkAdapterInfo(
                name: ifName,
                displayName: ifName,
                ipAddress: null, // No IP assigned yet
                isLoopback: false,
                isUp: true,
                kind: kind,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('/sys/class/net enumeration error: $e');
      }
    }

    final result = adapterMap.values.toList();
    // Sort adapters alphabetically by name
    result.sort((a, b) => a.name.compareTo(b.name));

    // Add 'any' interface on Linux/macOS
    result.insert(0, NetworkAdapterInfo.all);

    return result;
  }

  static bool _hasLinuxWirelessDir(String ifaceName) {
    if (!Platform.isLinux) return false;
    try {
      return Directory('/sys/class/net/$ifaceName/wireless').existsSync() ||
          Directory('/sys/class/net/$ifaceName/phy80211').existsSync();
    } catch (_) {
      return false;
    }
  }

  static Future<Set<String>> _detectOsWifiAdapterNames() async {
    final names = <String>{};
    try {
      if (Platform.isWindows) {
        final res = await Process.run(
          'netsh',
          ['wlan', 'show', 'interfaces'],
        ).timeout(const Duration(milliseconds: 1200));
        if (res.exitCode == 0) {
          names.addAll(parseWindowsWifiAdapterNames(res.stdout.toString()));
        }
      } else if (Platform.isMacOS) {
        final res = await Process.run(
          'networksetup',
          ['-listallhardwareports'],
        ).timeout(const Duration(milliseconds: 1200));
        if (res.exitCode == 0) {
          names.addAll(parseMacOsWifiDevices(res.stdout.toString()));
        }
      }
    } catch (e) {
      debugPrint('Wi-Fi adapter OS probe warning: $e');
    }
    return names;
  }

  /// Classifies an interface name as wired, wifi, any, or other.
  static AdapterKind classifyAdapterKind(
    String interfaceName, {
    Set<String> osWifiNames = const {},
    bool hasLinuxWirelessDir = false,
  }) {
    final trimmed = interfaceName.trim();
    final lower = trimmed.toLowerCase();

    if (lower == 'any') return AdapterKind.any;

    if (hasLinuxWirelessDir) return AdapterKind.wifi;

    for (final wifiName in osWifiNames) {
      if (wifiName.trim().toLowerCase() == lower) {
        return AdapterKind.wifi;
      }
    }

    // Fallback naming heuristics across Linux, Windows, macOS
    if (lower.startsWith('wlan') ||
        lower.startsWith('wlp') ||
        lower.startsWith('wlo') ||
        lower.startsWith('wlx') ||
        lower.startsWith('wifi') ||
        lower.contains('wi-fi') ||
        lower.contains('wireless') ||
        lower.contains('airport')) {
      return AdapterKind.wifi;
    }

    return AdapterKind.wired;
  }

  /// Parses `netsh wlan show interfaces` output for interface `Name` and `Description` values.
  static Set<String> parseWindowsWifiAdapterNames(String output) {
    final result = <String>{};
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final match =
          RegExp(r'^(Name|Description)\s*:\s*(.+)$', caseSensitive: false)
              .firstMatch(line);
      if (match != null) {
        final value = match.group(2)?.trim();
        if (value != null && value.isNotEmpty) {
          result.add(value);
        }
      }
    }
    return result;
  }

  /// Parses `networksetup -listallhardwareports` output and returns Device names (e.g. `en0`)
  /// associated with `Wi-Fi` or `AirPort` hardware ports.
  static Set<String> parseMacOsWifiDevices(String output) {
    final result = <String>{};
    bool isWifiPort = false;
    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        isWifiPort = false;
        continue;
      }
      final portMatch = RegExp(r'^Hardware Port:\s*(.+)$', caseSensitive: false)
          .firstMatch(line);
      if (portMatch != null) {
        final portName = portMatch.group(1)!.trim().toLowerCase();
        isWifiPort =
            portName.contains('wi-fi') || portName.contains('airport');
        continue;
      }
      if (isWifiPort) {
        final devMatch =
            RegExp(r'^Device:\s*(.+)$', caseSensitive: false).firstMatch(line);
        if (devMatch != null) {
          final device = devMatch.group(1)!.trim();
          if (device.isNotEmpty) {
            result.add(device);
          }
          isWifiPort = false;
        }
      }
    }
    return result;
  }
}
