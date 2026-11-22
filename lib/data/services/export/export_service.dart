import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import '../../../domain/models/switch_port_discovery.dart';
import '../../../domain/models/wifi_ap_discovery.dart';

class ExportService {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  static String toCsv(List<SwitchPortDiscovery> records) {
    final rows = <List<dynamic>>[
      [
        'Timestamp',
        'Protocol',
        'Switch Hostname',
        'Model',
        'Port ID',
        'Port Description',
        'VLAN ID',
        'VLAN Name',
        'Management IP',
        'Chassis ID (MAC)',
        'TTL',
        'Capabilities',
        'PoE / Power',
        'Duplex',
        'Interface',
      ],
    ];

    for (final r in records) {
      rows.add([
        _dateFormat.format(r.timestamp),
        r.protocol.label,
        r.switchHostname,
        r.switchModel,
        r.portId,
        r.portDescription ?? '',
        r.vlanId?.toString() ?? '',
        r.vlanName ?? '',
        r.managementIp ?? '',
        r.chassisId ?? '',
        r.ttl?.toString() ?? '',
        r.capabilities.join('; '),
        r.powerMdi ?? '',
        r.duplex ?? '',
        r.interfaceName,
      ]);
    }

    return Csv().encode(rows);
  }

  static String toJson(List<SwitchPortDiscovery> records) {
    final list = records.map((r) => r.toMap()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  static String toTextReport(List<SwitchPortDiscovery> records) {
    final buffer = StringBuffer();
    buffer.writeln('================================================================');
    buffer.writeln(' SOCKET SCOUT - SWITCH PORT DISCOVERY REPORT');
    buffer.writeln(' Generated: ${_dateFormat.format(DateTime.now())}');
    buffer.writeln(' Total Discoveries: ${records.length}');
    buffer.writeln('================================================================\n');

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      buffer.writeln('[#${i + 1}] ${r.switchHostname} (${r.protocol.label})');
      buffer.writeln('  Timestamp:       ${_dateFormat.format(r.timestamp)}');
      buffer.writeln('  Physical Port:   ${r.portId}${r.portDescription != null ? ' ("${r.portDescription}")' : ''}');
      buffer.writeln('  Switch Model:    ${r.switchModel}');
      buffer.writeln('  Active VLAN:     ${r.formattedVlan}');
      buffer.writeln('  Management IP:   ${r.managementIp ?? 'N/A'}');
      buffer.writeln('  Chassis ID:      ${r.chassisId ?? 'N/A'}');
      buffer.writeln('  Capabilities:    ${r.capabilities.join(', ')}');
      if (r.powerMdi != null) {
        buffer.writeln('  Power (PoE):     ${r.powerMdi}');
      }
      if (r.duplex != null) {
        buffer.writeln('  Duplex / PHY:    ${r.duplex}');
      }
      buffer.writeln('  Local Adapter:   ${r.interfaceName}');
      buffer.writeln('----------------------------------------------------------------');
    }

    return buffer.toString();
  }

  static String wifiToCsv(List<WifiApDiscovery> records) {
    final rows = <List<dynamic>>[
      [
        'Timestamp',
        'AP Name',
        'SSID',
        'BSSID',
        'Vendor',
        'Band',
        'Channel',
        'Frequency (MHz)',
        'Width (MHz)',
        'RSSI (dBm)',
        'Signal (%)',
        'Tx Rate (Mbps)',
        'Rx Rate (Mbps)',
        'Wi-Fi Standard',
        'Security',
        'Interface',
      ],
    ];

    for (final r in records) {
      rows.add([
        _dateFormat.format(r.timestamp),
        r.displayName,
        r.ssid,
        r.normalizedBssid,
        r.resolvedVendor ?? '',
        r.band.label,
        r.channel?.toString() ?? '',
        r.frequencyMhz?.toString() ?? '',
        r.channelWidthMhz?.toString() ?? '',
        r.rssiDbm?.toString() ?? '',
        r.effectiveSignalPercent?.toString() ?? '',
        r.txRateMbps?.toString() ?? '',
        r.rxRateMbps?.toString() ?? '',
        r.wifiStandard ?? '',
        r.securityType ?? '',
        r.interfaceName,
      ]);
    }

    return Csv().encode(rows);
  }

  static String wifiToJson(List<WifiApDiscovery> records) {
    final list = records.map((r) => r.toMap()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  static String wifiToTextReport(List<WifiApDiscovery> records) {
    final buffer = StringBuffer();
    buffer.writeln('================================================================');
    buffer.writeln(' SOCKET SCOUT - WI-FI ACCESS POINT DISCOVERY REPORT');
    buffer.writeln(' Generated: ${_dateFormat.format(DateTime.now())}');
    buffer.writeln(' Total AP Associations / Roams: ${records.length}');
    buffer.writeln('================================================================\n');

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      buffer.writeln('[#${i + 1}] ${r.displayName} (${r.band.label})');
      buffer.writeln('  Timestamp:       ${_dateFormat.format(r.timestamp)}');
      buffer.writeln('  SSID:            ${r.ssid}');
      buffer.writeln('  BSSID (AP MAC):  ${r.normalizedBssid}');
      buffer.writeln('  Vendor:          ${r.resolvedVendor ?? 'Unknown'}');
      buffer.writeln('  RF Channel:      ${r.formattedChannel}');
      buffer.writeln('  Signal (RSSI):   ${r.formattedRssi} (${r.signalQualityLabel})');
      buffer.writeln('  PHY Link Speed:  ${r.formattedLinkSpeed}');
      if (r.wifiStandard != null) {
        buffer.writeln('  Wi-Fi Standard:  ${r.wifiStandard}');
      }
      if (r.securityType != null) {
        buffer.writeln('  Security:        ${r.securityType}');
      }
      buffer.writeln('  Neighbors Seen:  ${r.neighbors.length}');
      buffer.writeln('  Local Adapter:   ${r.interfaceName}');
      buffer.writeln('----------------------------------------------------------------');
    }

    return buffer.toString();
  }
}
