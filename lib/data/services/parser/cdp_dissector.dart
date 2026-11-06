import 'dart:convert';
import 'dart:typed_data';
import '../../../domain/models/switch_port_discovery.dart';

class CdpDissector {
  static const int snapProtoCdp = 0x2000;

  static bool isCdpFrame(Uint8List packet) {
    if (packet.length < 22) return false;

    // Check Destination MAC: 01:00:0c:cc:cc:cc
    final isCdpMac = packet[0] == 0x01 &&
        packet[1] == 0x00 &&
        packet[2] == 0x0C &&
        packet[3] == 0xCC &&
        packet[4] == 0xCC &&
        packet[5] == 0xCC;

    // Check SNAP Protocol 0x2000
    // LLC is at 14, 15, 16 (0xAA, 0xAA, 0x03), SNAP OUI is 17, 18, 19 (0x00, 0x00, 0x0C), Protocol ID 20, 21 (0x20, 0x00)
    final isSnapCdp = packet.length >= 22 &&
        packet[14] == 0xAA &&
        packet[15] == 0xAA &&
        packet[16] == 0x03 &&
        packet[20] == 0x20 &&
        packet[21] == 0x00;

    return isCdpMac || isSnapCdp;
  }

  static SwitchPortDiscovery? dissect({
    required Uint8List packet,
    DateTime? timestamp,
    String interfaceName = 'eth0',
  }) {
    if (!isCdpFrame(packet)) return null;

    int cdpHeaderOffset = 22;
    if (packet.length < cdpHeaderOffset + 4) return null;

    final version = packet[cdpHeaderOffset];
    final ttl = packet[cdpHeaderOffset + 1];
    // Checksum at cdpHeaderOffset + 2, 3

    String switchHostname = 'Unknown Cisco Switch';
    String portId = 'Unknown Port';
    String switchModel = 'Cisco Switch (CDP v$version)';
    String? portDescription;
    int? vlanId;
    String? managementIp;
    String? chassisId;
    final capabilities = <String>[];
    String? powerMdi;
    String? duplex;
    String? vtpDomain;

    // Extract switch source MAC from Ethernet header as chassisId
    if (packet.length >= 12) {
      chassisId = packet
          .sublist(6, 12)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toUpperCase();
    }

    final rawTlvs = <TlvRecord>[];
    int offset = cdpHeaderOffset + 4;

    while (offset + 4 <= packet.length) {
      final type = (packet[offset] << 8) | packet[offset + 1];
      final length = (packet[offset + 2] << 8) | packet[offset + 3];

      if (length < 4 || offset + length > packet.length) {
        break;
      }

      final valLen = length - 4;
      final valBytes = packet.sublist(offset + 4, offset + length);
      final tlvFullBytes = packet.sublist(offset, offset + length);
      offset += length;

      final hexBytes = _bytesToHex(tlvFullBytes);
      String typeName = 'Type 0x${type.toRadixString(16).padLeft(4, '0')}';
      String description = '';

      switch (type) {
        case 0x0001: // Device ID
          typeName = 'Device ID';
          switchHostname = _safeAsciiString(valBytes);
          description = switchHostname;
          break;

        case 0x0002: // Address
          typeName = 'Addresses';
          final parsedIps = _parseAddressesTlv(valBytes);
          if (parsedIps.isNotEmpty) {
            managementIp = parsedIps.first;
            description = 'IP: ${parsedIps.join(', ')}';
          } else {
            description = 'Address block ($valLen bytes)';
          }
          break;

        case 0x0003: // Port ID
          typeName = 'Port ID';
          portId = _safeAsciiString(valBytes);
          description = portId;
          break;

        case 0x0004: // Capabilities
          typeName = 'Capabilities';
          if (valBytes.length >= 4) {
            final caps = (valBytes[0] << 24) |
                (valBytes[1] << 16) |
                (valBytes[2] << 8) |
                valBytes[3];
            capabilities.addAll(_decodeCdpCapabilities(caps));
            description = capabilities.join(', ');
          }
          break;

        case 0x0005: // Software Version
          typeName = 'Software Version';
          final fullVersion = _safeAsciiString(valBytes);
          description = fullVersion.split(RegExp(r'[\r\n]+')).first.trim();
          break;

        case 0x0006: // Platform
          typeName = 'Platform';
          switchModel = _safeAsciiString(valBytes);
          description = switchModel;
          break;

        case 0x0009: // VTP Management Domain
          typeName = 'VTP Management Domain';
          vtpDomain = _safeAsciiString(valBytes);
          description = vtpDomain;
          break;

        case 0x000A: // Native VLAN
          typeName = 'Native VLAN';
          if (valBytes.length >= 2) {
            vlanId = (valBytes[0] << 8) | valBytes[1];
            description = 'VLAN $vlanId';
          }
          break;

        case 0x000B: // Duplex
          typeName = 'Duplex';
          if (valBytes.isNotEmpty) {
            final isFull = valBytes[0] == 0x01;
            duplex = isFull ? 'Full Duplex' : 'Half Duplex';
            description = duplex;
          }
          break;

        case 0x0010: // Power Consumption
          typeName = 'Power Consumption';
          if (valBytes.length >= 2) {
            final mw = (valBytes[0] << 8) | valBytes[1];
            final watts = (mw / 1000.0).toStringAsFixed(1);
            powerMdi = '${watts}W ($mw mW)';
            description = powerMdi;
          }
          break;

        case 0x0016: // Management Address
          typeName = 'Management Address';
          final mgmtIps = _parseAddressesTlv(valBytes);
          if (mgmtIps.isNotEmpty) {
            managementIp = mgmtIps.first;
            description = 'Mgmt IP: ${mgmtIps.join(', ')}';
          }
          break;

        default:
          description = '$valLen bytes';
      }

      rawTlvs.add(TlvRecord(
        type: type,
        typeName: typeName,
        length: length,
        description: description,
        hexBytes: hexBytes,
      ));
    }

    final rawHex = _formatHexDump(packet);

    return SwitchPortDiscovery(
      timestamp: timestamp ?? DateTime.now(),
      protocol: DiscoveryProtocol.cdp,
      switchHostname: switchHostname.isNotEmpty ? switchHostname : 'Unknown Cisco Switch',
      portId: portId.isNotEmpty ? portId : 'Unknown Port',
      switchModel: switchModel,
      portDescription: portDescription,
      vlanId: vlanId,
      vlanName: vtpDomain != null ? 'VTP: $vtpDomain' : null,
      managementIp: managementIp,
      chassisId: chassisId,
      ttl: ttl,
      capabilities: capabilities,
      powerMdi: powerMdi,
      duplex: duplex,
      vtpDomain: vtpDomain,
      rawTlvs: rawTlvs,
      rawHex: rawHex,
      rawBytes: packet,
      interfaceName: interfaceName,
    );
  }

  static List<String> _parseAddressesTlv(Uint8List valBytes) {
    final ips = <String>[];
    if (valBytes.length < 4) return ips;

    final numAddrs = (valBytes[0] << 24) |
        (valBytes[1] << 16) |
        (valBytes[2] << 8) |
        valBytes[3];

    int offset = 4;
    for (int i = 0; i < numAddrs && offset + 5 <= valBytes.length; i++) {
      final protoType = valBytes[offset]; // 0x01 = NLPID
      final protoLen = valBytes[offset + 1]; // 1
      offset += 2;

      if (offset + protoLen > valBytes.length) break;
      final proto = valBytes[offset]; // 0xCC for IPv4
      offset += protoLen;

      if (offset + 2 > valBytes.length) break;
      final addrLen = (valBytes[offset] << 8) | valBytes[offset + 1];
      offset += 2;

      if (offset + addrLen > valBytes.length) break;
      if (protoType == 0x01 && proto == 0xCC && addrLen == 4) {
        final ip = '${valBytes[offset]}.${valBytes[offset + 1]}.${valBytes[offset + 2]}.${valBytes[offset + 3]}';
        ips.add(ip);
      }
      offset += addrLen;
    }

    return ips;
  }

  static List<String> _decodeCdpCapabilities(int caps) {
    final list = <String>[];
    if ((caps & 0x01) != 0) list.add('Router');
    if ((caps & 0x02) != 0) list.add('Transparent Bridge');
    if ((caps & 0x04) != 0) list.add('Source Route Bridge');
    if ((caps & 0x08) != 0) list.add('Switch');
    if ((caps & 0x10) != 0) list.add('Host');
    if ((caps & 0x20) != 0) list.add('IGMP');
    if ((caps & 0x40) != 0) list.add('Repeater');
    return list;
  }

  static String _safeAsciiString(List<int> bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: true).trim();
    } catch (_) {
      return String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127)).trim();
    }
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
  }

  static String _formatHexDump(Uint8List bytes) {
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 16) {
      final chunkLen = (i + 16 <= bytes.length) ? 16 : (bytes.length - i);
      final chunk = bytes.sublist(i, i + chunkLen);

      final offsetHex = i.toRadixString(16).padLeft(4, '0');
      final hexPart = chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final paddedHex = hexPart.padRight(48, ' ');

      final asciiPart = chunk.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();

      buffer.writeln('$offsetHex   $paddedHex   $asciiPart');
    }
    return buffer.toString().trimRight();
  }
}
