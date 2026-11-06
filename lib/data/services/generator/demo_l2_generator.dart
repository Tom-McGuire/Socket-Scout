import 'dart:convert';
import 'dart:typed_data';

class DemoL2Generator {
  /// Generates a binary LLDP packet with realistic switch TLVs.
  static Uint8List createLldpPacket({
    required String srcMac,
    required String systemName,
    required String systemDescription,
    required String portId,
    required String portDescription,
    required String managementIp,
    int vlanId = 1,
    int ttl = 120,
    int powerWatts = 30,
  }) {
    final bytes = <int>[];

    // Ethernet Header (14 bytes)
    // Dest MAC: 01:80:C2:00:00:0E
    bytes.addAll([0x01, 0x80, 0xC2, 0x00, 0x00, 0x0E]);
    // Src MAC
    bytes.addAll(_parseMac(srcMac));
    // EtherType: 0x88CC
    bytes.addAll([0x88, 0xCC]);

    // TLV 1: Chassis ID (Subtype 4: MAC address)
    final macBytes = _parseMac(srcMac);
    _appendTlv(bytes, 1, [0x04, ...macBytes]);

    // TLV 2: Port ID (Subtype 5: Interface Name)
    final portBytes = utf8.encode(portId);
    _appendTlv(bytes, 2, [0x05, ...portBytes]);

    // TLV 3: Time To Live (2 bytes)
    _appendTlv(bytes, 3, [(ttl >> 8) & 0xFF, ttl & 0xFF]);

    // TLV 4: Port Description
    if (portDescription.isNotEmpty) {
      _appendTlv(bytes, 4, utf8.encode(portDescription));
    }

    // TLV 5: System Name
    if (systemName.isNotEmpty) {
      _appendTlv(bytes, 5, utf8.encode(systemName));
    }

    // TLV 6: System Description
    if (systemDescription.isNotEmpty) {
      _appendTlv(bytes, 6, utf8.encode(systemDescription));
    }

    // TLV 7: System Capabilities (Bridge=0x0004, Router=0x0010)
    // System caps (2 bytes) + Enabled caps (2 bytes)
    _appendTlv(bytes, 7, [0x00, 0x14, 0x00, 0x14]);

    // TLV 8: Management Address (IPv4: Subtype 1, len 4)
    final ipParts = managementIp.split('.').map(int.parse).toList();
    _appendTlv(bytes, 8, [
      0x05, // Address string length (subtype + 4 bytes)
      0x01, // Subtype 1: IPv4
      ipParts[0], ipParts[1], ipParts[2], ipParts[3],
      0x02, // Interface numbering subtype (ifIndex)
      0x00, 0x00, 0x00, 0x01, // ifIndex 1
      0x00, // OID length 0
    ]);

    // TLV 127: IEEE 802.1 Port VLAN ID (Subtype 1)
    _appendTlv(bytes, 127, [
      0x00, 0x80, 0xC2, // IEEE 802.1 OUI
      0x01, // Subtype 1: PVID
      (vlanId >> 8) & 0xFF, vlanId & 0xFF,
    ]);

    // TLV 127: IEEE 802.3 Power Via MDI (PoE PSE)
    _appendTlv(bytes, 127, [
      0x00, 0x12, 0x0F, // IEEE 802.3 OUI
      0x02, // Subtype 2: Power via MDI
      0x03, // MDI power support & enabled
      0x01, // PSE pairs
      0x04, // Class 4 (30W)
    ]);

    // TLV 127: IEEE 802.3 Max Frame Size (MTU 1518)
    _appendTlv(bytes, 127, [
      0x00, 0x12, 0x0F,
      0x04,
      0x05, 0xEE, // 1518 bytes
    ]);

    // TLV 0: End of LLDPDU
    _appendTlv(bytes, 0, []);

    // Pad to minimum Ethernet frame size if needed (60 bytes before FCS)
    while (bytes.length < 60) {
      bytes.add(0x00);
    }

    return Uint8List.fromList(bytes);
  }

  /// Generates a binary CDP packet with realistic Cisco switch TLVs.
  static Uint8List createCdpPacket({
    required String srcMac,
    required String deviceId,
    required String platform,
    required String portId,
    required String softwareVersion,
    required String managementIp,
    int nativeVlan = 1,
    int ttl = 180,
    int powerMw = 15400,
    String vtpDomain = 'CORP-HQ',
  }) {
    final cdpPayload = <int>[];

    // CDP Header: Version 2, TTL, Checksum
    cdpPayload.add(0x02);
    cdpPayload.add(ttl);
    cdpPayload.addAll([0x00, 0x00]); // Checksum placeholder

    // TLV 0x0001: Device ID
    _appendCdpTlv(cdpPayload, 0x0001, utf8.encode(deviceId));

    // TLV 0x0002: Address (IPv4)
    final ipParts = managementIp.split('.').map(int.parse).toList();
    final addrVal = <int>[
      0x00, 0x00, 0x00, 0x01, // 1 address
      0x01, // Protocol type: NLPID
      0x01, // Protocol length: 1
      0xCC, // NLPID IPv4
      0x00, 0x04, // Address length: 4
      ipParts[0], ipParts[1], ipParts[2], ipParts[3],
    ];
    _appendCdpTlv(cdpPayload, 0x0002, addrVal);

    // TLV 0x0003: Port ID
    _appendCdpTlv(cdpPayload, 0x0003, utf8.encode(portId));

    // TLV 0x0004: Capabilities (Router=0x01, Transparent Bridge=0x02, Switch=0x08, IGMP=0x20)
    // 0x0000002B
    _appendCdpTlv(cdpPayload, 0x0004, [0x00, 0x00, 0x00, 0x2B]);

    // TLV 0x0005: Software Version
    _appendCdpTlv(cdpPayload, 0x0005, utf8.encode(softwareVersion));

    // TLV 0x0006: Platform
    _appendCdpTlv(cdpPayload, 0x0006, utf8.encode(platform));

    // TLV 0x0009: VTP Management Domain
    _appendCdpTlv(cdpPayload, 0x0009, utf8.encode(vtpDomain));

    // TLV 0x000A: Native VLAN
    _appendCdpTlv(cdpPayload, 0x000A, [(nativeVlan >> 8) & 0xFF, nativeVlan & 0xFF]);

    // TLV 0x000B: Duplex (1 = Full)
    _appendCdpTlv(cdpPayload, 0x000B, [0x01]);

    // TLV 0x0010: Power Consumption (mW)
    _appendCdpTlv(cdpPayload, 0x0010, [(powerMw >> 8) & 0xFF, powerMw & 0xFF]);

    // Frame assembly: 802.3 Header + LLC/SNAP + CDP
    final frame = <int>[];
    // Dest MAC: 01:00:0C:CC:CC:CC
    frame.addAll([0x01, 0x00, 0x0C, 0xCC, 0xCC, 0xCC]);
    // Src MAC
    frame.addAll(_parseMac(srcMac));

    final llcSnapCdpLen = 8 + cdpPayload.length;
    frame.addAll([(llcSnapCdpLen >> 8) & 0xFF, llcSnapCdpLen & 0xFF]);

    // LLC: DSAP AA, SSAP AA, Control 03
    frame.addAll([0xAA, 0xAA, 0x03]);
    // SNAP: Cisco OUI 00-00-0C, Protocol 0x2000 (CDP)
    frame.addAll([0x00, 0x00, 0x0C, 0x20, 0x00]);

    // Append CDP Payload
    frame.addAll(cdpPayload);

    while (frame.length < 60) {
      frame.add(0x00);
    }

    return Uint8List.fromList(frame);
  }

  static void _appendTlv(List<int> buffer, int type, List<int> value) {
    final header = ((type & 0x7F) << 9) | (value.length & 0x01FF);
    buffer.add((header >> 8) & 0xFF);
    buffer.add(header & 0xFF);
    buffer.addAll(value);
  }

  static void _appendCdpTlv(List<int> buffer, int type, List<int> value) {
    final length = 4 + value.length;
    buffer.add((type >> 8) & 0xFF);
    buffer.add(type & 0xFF);
    buffer.add((length >> 8) & 0xFF);
    buffer.add(length & 0xFF);
    buffer.addAll(value);
  }

  static List<int> _parseMac(String mac) {
    return mac
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
        .replaceAllMapped(RegExp(r'.{2}'), (m) => '${m.group(0)} ')
        .trim()
        .split(' ')
        .map((s) => int.parse(s, radix: 16))
        .toList();
  }

  /// Preset 1: Cisco Catalyst 9200-24P (CDP)
  static Uint8List ciscoCatalyst9200Cdp() {
    return createCdpPacket(
      srcMac: '58:0A:20:4A:11:80',
      deviceId: 'SW-CAT9200-RACK04.corp.local',
      platform: 'cisco Catalyst 9200-24P',
      portId: 'GigabitEthernet1/0/14',
      softwareVersion: 'Cisco IOS Software [Cupertino], C9200 Software (C9200-UNIVERSALK9-M), Version 17.6.4, RELEASE SOFTWARE (fc2)',
      managementIp: '10.20.4.15',
      nativeVlan: 20,
      vtpDomain: 'CORP-SWITCHING',
      powerMw: 15400,
    );
  }

  /// Preset 2: Cisco Catalyst 9200-24P (LLDP equivalent on same port)
  static Uint8List ciscoCatalyst9200Lldp() {
    return createLldpPacket(
      srcMac: '58:0A:20:4A:11:80',
      systemName: 'SW-CAT9200-RACK04.corp.local',
      systemDescription: 'Cisco IOS Software, C9200 Software (C9200-UNIVERSALK9-M), Version 17.6.4, RELEASE SOFTWARE (fc2)',
      portId: 'GigabitEthernet1/0/14',
      portDescription: 'Access Drop Room 204B (Workstation)',
      managementIp: '10.20.4.15',
      vlanId: 20,
      ttl: 120,
      powerWatts: 30,
    );
  }

  /// Preset 3: Netgear M4250-26G4F-PoE+ AV Line (LLDP)
  static Uint8List netgearM4250Lldp() {
    return createLldpPacket(
      srcMac: '9C:34:26:88:99:AA',
      systemName: 'NETGEAR-M4250-AUDITORIUM',
      systemDescription: 'NETGEAR M4250-26G4F-PoE+ ProAV Switch, Firmware v13.0.4.19',
      portId: 'Port 7',
      portDescription: 'AV-Over-IP Dante Primary Trunk',
      managementIp: '192.168.100.254',
      vlanId: 100,
      ttl: 120,
      powerWatts: 30,
    );
  }

  /// Preset 4: Aruba CX 6200F 24G (LLDP)
  static Uint8List arubaCx6200Lldp() {
    return createLldpPacket(
      srcMac: 'B0:8B:CF:12:34:56',
      systemName: 'aruba-cx-floor3-east',
      systemDescription: 'ArubaOS-CX JL678A 6200F 24G 4SFP+ Switch, Version FL.10.10.1020',
      portId: '1/1/24',
      portDescription: 'Conference Room Core Uplink',
      managementIp: '172.16.30.1',
      vlanId: 10,
      ttl: 120,
      powerWatts: 370,
    );
  }

  /// Preset 5: Juniper Networks EX4300-48T (LLDP)
  static Uint8List juniperEx4300Lldp() {
    return createLldpPacket(
      srcMac: '84:B5:9C:A1:B2:C3',
      systemName: 'CORE-SW-JUNIPER-01',
      systemDescription: 'Juniper Networks, Inc. ex4300-48t, version 21.4R3-S5.4',
      portId: 'ge-0/0/47',
      portDescription: 'Trunk to Server Rack 02',
      managementIp: '10.250.0.1',
      vlanId: 500,
      ttl: 120,
      powerWatts: 0,
    );
  }
}
