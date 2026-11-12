import 'dart:convert';
import 'package:network_suite_shared/network_suite_shared.dart';

enum DiscoveryProtocol {
  lldp,
  cdp;

  String get label => switch (this) {
        DiscoveryProtocol.lldp => 'LLDP',
        DiscoveryProtocol.cdp => 'CDP',
      };
}

class TlvRecord {
  const TlvRecord({
    required this.type,
    required this.typeName,
    required this.length,
    required this.description,
    this.hexBytes = '',
  });

  final int type;
  final String typeName;
  final int length;
  final String description;
  final String hexBytes;

  Map<String, dynamic> toMap() => {
        'type': type,
        'typeName': typeName,
        'length': length,
        'description': description,
        'hexBytes': hexBytes,
      };

  factory TlvRecord.fromMap(Map<String, dynamic> map) => TlvRecord(
        type: map['type'] as int? ?? 0,
        typeName: map['typeName'] as String? ?? '',
        length: map['length'] as int? ?? 0,
        description: map['description'] as String? ?? '',
        hexBytes: map['hexBytes'] as String? ?? '',
      );
}

class SwitchPortDiscovery {
  const SwitchPortDiscovery({
    this.id,
    required this.timestamp,
    required this.protocol,
    required this.switchHostname,
    required this.portId,
    this.switchModel = 'Unknown Model',
    this.portDescription,
    this.vlanId,
    this.vlanName,
    this.managementIp,
    this.chassisId,
    this.ttl = 120,
    this.capabilities = const [],
    this.powerMdi,
    this.linkAggregation,
    this.mtu,
    this.duplex,
    this.vtpDomain,
    this.rawTlvs = const [],
    this.rawHex = '',
    this.rawBytes,
    this.interfaceName = 'unknown',
  });

  final int? id;
  final DateTime timestamp;
  final DiscoveryProtocol protocol;
  final String switchHostname;
  final String portId;
  final String switchModel;
  final String? portDescription;
  final int? vlanId;
  final String? vlanName;
  final String? managementIp;
  final String? chassisId;
  final int? ttl;
  final List<String> capabilities;
  final String? powerMdi;
  final String? linkAggregation;
  final int? mtu;
  final String? duplex;
  final String? vtpDomain;
  final List<TlvRecord> rawTlvs;
  final String rawHex;
  final List<int>? rawBytes;
  final String interfaceName;

  String get summaryDescription {
    final vlanPart = vlanId != null ? 'VLAN $vlanId' : 'Untagged';
    return '$switchHostname ($switchModel) • Port $portId • $vlanPart';
  }

  String get formattedVlan {
    if (vlanId == null) return 'N/A';
    if (vlanName != null && vlanName!.isNotEmpty) {
      return 'VLAN $vlanId ($vlanName)';
    }
    return 'VLAN $vlanId';
  }

  /// Resolves the canonical 6-byte MAC address of the switch from either
  /// its Chassis ID or the raw Ethernet frame header.
  String? get effectiveMacAddress {
    if (chassisId != null && SharedDevice.isValidMac(chassisId!)) {
      return SharedDevice.normalizeMac(chassisId!);
    }
    if (rawBytes != null && rawBytes!.length >= 12) {
      final mac = rawBytes!
          .sublist(6, 12)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':');
      if (SharedDevice.isValidMac(mac)) {
        return SharedDevice.normalizeMac(mac);
      }
    }
    return null;
  }

  /// Retrieves the custom friendly device name from [SharedDeviceDatabase] if set,
  /// otherwise returns the switch hostname.
  String get displayName {
    final mac = effectiveMacAddress;
    if (mac != null && SharedDeviceDatabase.instance.isInitialized) {
      try {
        final dev = SharedDeviceDatabase.instance.getDeviceByMac(mac);
        if (dev != null && dev.hasCustomName && dev.name.trim().isNotEmpty) {
          return dev.name.trim();
        }
      } catch (_) {}
    }
    return switchHostname;
  }

  /// Whether this switch has a user-defined custom friendly name in [SharedDeviceDatabase].
  bool get hasCustomName {
    final mac = effectiveMacAddress;
    if (mac != null && SharedDeviceDatabase.instance.isInitialized) {
      try {
        final dev = SharedDeviceDatabase.instance.getDeviceByMac(mac);
        return dev != null && dev.hasCustomName && dev.name.trim().isNotEmpty;
      } catch (_) {}
    }
    return false;
  }

  SwitchPortDiscovery copyWith({
    int? id,
    DateTime? timestamp,
    DiscoveryProtocol? protocol,
    String? switchHostname,
    String? portId,
    String? switchModel,
    String? portDescription,
    int? vlanId,
    String? vlanName,
    String? managementIp,
    String? chassisId,
    int? ttl,
    List<String>? capabilities,
    String? powerMdi,
    String? linkAggregation,
    int? mtu,
    String? duplex,
    String? vtpDomain,
    List<TlvRecord>? rawTlvs,
    String? rawHex,
    List<int>? rawBytes,
    String? interfaceName,
  }) {
    return SwitchPortDiscovery(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      protocol: protocol ?? this.protocol,
      switchHostname: switchHostname ?? this.switchHostname,
      portId: portId ?? this.portId,
      switchModel: switchModel ?? this.switchModel,
      portDescription: portDescription ?? this.portDescription,
      vlanId: vlanId ?? this.vlanId,
      vlanName: vlanName ?? this.vlanName,
      managementIp: managementIp ?? this.managementIp,
      chassisId: chassisId ?? this.chassisId,
      ttl: ttl ?? this.ttl,
      capabilities: capabilities ?? this.capabilities,
      powerMdi: powerMdi ?? this.powerMdi,
      linkAggregation: linkAggregation ?? this.linkAggregation,
      mtu: mtu ?? this.mtu,
      duplex: duplex ?? this.duplex,
      vtpDomain: vtpDomain ?? this.vtpDomain,
      rawTlvs: rawTlvs ?? this.rawTlvs,
      rawHex: rawHex ?? this.rawHex,
      rawBytes: rawBytes ?? this.rawBytes,
      interfaceName: interfaceName ?? this.interfaceName,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp_ms': timestamp.millisecondsSinceEpoch,
      'protocol': protocol.name,
      'switch_hostname': switchHostname,
      'port_id': portId,
      'switch_model': switchModel,
      'port_description': portDescription,
      'vlan_id': vlanId,
      'vlan_name': vlanName,
      'management_ip': managementIp,
      'chassis_id': chassisId,
      'ttl': ttl,
      'capabilities': jsonEncode(capabilities),
      'power_mdi': powerMdi,
      'link_aggregation': linkAggregation,
      'mtu': mtu,
      'duplex': duplex,
      'vtp_domain': vtpDomain,
      'raw_tlvs': jsonEncode(rawTlvs.map((t) => t.toMap()).toList()),
      'raw_hex': rawHex,
      'interface_name': interfaceName,
    };
  }

  factory SwitchPortDiscovery.fromMap(Map<String, dynamic> map, {List<int>? rawBytes}) {
    List<String> caps = [];
    if (map['capabilities'] != null) {
      try {
        final decoded = jsonDecode(map['capabilities'] as String);
        if (decoded is List) {
          caps = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    List<TlvRecord> tlvs = [];
    if (map['raw_tlvs'] != null) {
      try {
        final decoded = jsonDecode(map['raw_tlvs'] as String);
        if (decoded is List) {
          tlvs = decoded
              .map((e) => TlvRecord.fromMap(e as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    final protoStr = map['protocol'] as String? ?? 'lldp';
    final proto = protoStr.toLowerCase() == 'cdp'
        ? DiscoveryProtocol.cdp
        : DiscoveryProtocol.lldp;

    return SwitchPortDiscovery(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        map['timestamp_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      protocol: proto,
      switchHostname: map['switch_hostname'] as String? ?? 'Unknown Switch',
      portId: map['port_id'] as String? ?? 'Unknown Port',
      switchModel: map['switch_model'] as String? ?? 'Unknown Model',
      portDescription: map['port_description'] as String?,
      vlanId: map['vlan_id'] as int?,
      vlanName: map['vlan_name'] as String?,
      managementIp: map['management_ip'] as String?,
      chassisId: map['chassis_id'] as String?,
      ttl: map['ttl'] as int? ?? 120,
      capabilities: caps,
      powerMdi: map['power_mdi'] as String?,
      linkAggregation: map['link_aggregation'] as String?,
      mtu: map['mtu'] as int?,
      duplex: map['duplex'] as String?,
      vtpDomain: map['vtp_domain'] as String?,
      rawTlvs: tlvs,
      rawHex: map['raw_hex'] as String? ?? '',
      rawBytes: rawBytes,
      interfaceName: map['interface_name'] as String? ?? 'unknown',
    );
  }
}
