import 'dart:convert';
import 'dart:typed_data';
import '../../../domain/models/switch_port_discovery.dart';

class LldpDissector {
  static const int etherTypeLldp = 0x88CC;

  static bool isLldpFrame(Uint8List packet) {
    if (packet.length < 14) return false;
    int ethType = (packet[12] << 8) | packet[13];
    if (ethType == 0x8100 && packet.length >= 18) {
      // 802.1Q tagged
      ethType = (packet[16] << 8) | packet[17];
    }
    return ethType == etherTypeLldp;
  }

  static SwitchPortDiscovery? dissect({
    required Uint8List packet,
    DateTime? timestamp,
    String interfaceName = 'eth0',
  }) {
    if (packet.length < 14) return null;

    int payloadOffset = 14;
    int ethType = (packet[12] << 8) | packet[13];
    if (ethType == 0x8100 && packet.length >= 18) {
      ethType = (packet[16] << 8) | packet[17];
      payloadOffset = 18;
    }

    if (ethType != etherTypeLldp) return null;

    String switchHostname = 'Unknown Switch';
    String portId = 'Unknown Port';
    String switchModel = 'LLDP Switch';
    String? portDescription;
    int? vlanId;
    String? vlanName;
    String? managementIp;
    String? chassisId;
    int ttl = 120;
    final capabilities = <String>[];
    String? powerMdi;
    String? linkAggregation;
    int? mtu;
    String? duplex;

    final rawTlvs = <TlvRecord>[];
    int offset = payloadOffset;

    while (offset + 2 <= packet.length) {
      final tlvHeader = (packet[offset] << 8) | packet[offset + 1];
      final type = (tlvHeader >> 9) & 0x7F;
      final length = tlvHeader & 0x01FF;
      offset += 2;

      if (offset + length > packet.length) {
        break;
      }

      final tlvBytes = packet.sublist(offset, offset + length);
      offset += length;

      final hexBytes = _bytesToHex(tlvBytes);
      String typeName = 'Type $type';
      String description = '';

      switch (type) {
        case 0: // End of LLDPDU
          typeName = 'End of LLDPDU';
          description = 'End of LLDPDU marker (0 bytes)';
          rawTlvs.add(TlvRecord(
            type: type,
            typeName: typeName,
            length: length,
            description: description,
            hexBytes: hexBytes,
          ));
          // Break out of TLV loop
          offset = packet.length;
          break;

        case 1: // Chassis ID
          typeName = 'Chassis ID';
          if (tlvBytes.isNotEmpty) {
            final subtype = tlvBytes[0];
            final dataBytes = tlvBytes.sublist(1);
            chassisId = _decodeChassisOrPort(subtype, dataBytes);
            description = 'Subtype $subtype: $chassisId';
          }
          break;

        case 2: // Port ID
          typeName = 'Port ID';
          if (tlvBytes.isNotEmpty) {
            final subtype = tlvBytes[0];
            final dataBytes = tlvBytes.sublist(1);
            portId = _decodeChassisOrPort(subtype, dataBytes);
            description = 'Subtype $subtype: $portId';
          }
          break;

        case 3: // Time to Live
          typeName = 'Time To Live (TTL)';
          if (tlvBytes.length >= 2) {
            ttl = (tlvBytes[0] << 8) | tlvBytes[1];
            description = '$ttl seconds';
          }
          break;

        case 4: // Port Description
          typeName = 'Port Description';
          portDescription = _safeAsciiString(tlvBytes);
          description = portDescription;
          break;

        case 5: // System Name
          typeName = 'System Name';
          switchHostname = _safeAsciiString(tlvBytes);
          description = switchHostname;
          break;

        case 6: // System Description
          typeName = 'System Description';
          final fullDesc = _safeAsciiString(tlvBytes);
          description = fullDesc;
          switchModel = _extractModelFromDescription(fullDesc);
          break;

        case 7: // System Capabilities
          typeName = 'System Capabilities';
          if (tlvBytes.length >= 4) {
            final sysCaps = (tlvBytes[0] << 8) | tlvBytes[1];
            final enabledCaps = (tlvBytes[2] << 8) | tlvBytes[3];
            capabilities.addAll(_decodeCapabilities(enabledCaps));
            description = 'Enabled: ${capabilities.join(', ')} (System: ${_decodeCapabilities(sysCaps).join(', ')})';
          }
          break;

        case 8: // Management Address
          typeName = 'Management Address';
          if (tlvBytes.length >= 2) {
            final addrSubtype = tlvBytes[1];
            if (addrSubtype == 1 && tlvBytes.length >= 6) {
              // IPv4
              managementIp = '${tlvBytes[2]}.${tlvBytes[3]}.${tlvBytes[4]}.${tlvBytes[5]}';
              description = 'IPv4: $managementIp';
            } else if (addrSubtype == 2 && tlvBytes.length >= 18) {
              // IPv6
              managementIp = _decodeIpv6(tlvBytes.sublist(2, 18));
              description = 'IPv6: $managementIp';
            } else {
              description = 'Subtype $addrSubtype';
            }
          }
          break;

        case 127: // Organizationally Specific
          typeName = 'Organizationally Specific (TLV 127)';
          if (tlvBytes.length >= 4) {
            final oui = (tlvBytes[0] << 16) | (tlvBytes[1] << 8) | tlvBytes[2];
            final subtype = tlvBytes[3];
            final orgPayload = tlvBytes.sublist(4);

            if (oui == 0x0080C2) {
              // IEEE 802.1
              switch (subtype) {
                case 1: // Port VLAN ID (PVID)
                  if (orgPayload.length >= 2) {
                    vlanId = (orgPayload[0] << 8) | orgPayload[1];
                    description = 'IEEE 802.1 Port VLAN ID (PVID): $vlanId';
                  }
                  break;
                case 3: // VLAN Name
                  if (orgPayload.length >= 3) {
                    final vId = (orgPayload[0] << 8) | orgPayload[1];
                    final nameLen = orgPayload[2];
                    if (orgPayload.length >= 3 + nameLen) {
                      vlanName = _safeAsciiString(orgPayload.sublist(3, 3 + nameLen));
                      vlanId ??= vId;
                      description = 'IEEE 802.1 VLAN Name: VLAN $vId "$vlanName"';
                    }
                  }
                  break;
                default:
                  description = 'IEEE 802.1 Subtype $subtype';
              }
            } else if (oui == 0x00120F) {
              // IEEE 802.3
              switch (subtype) {
                case 1: // MAC / PHY Config
                  if (orgPayload.isNotEmpty) {
                    final autoNeg = orgPayload[0];
                    final supported = (autoNeg & 0x01) != 0;
                    final enabled = (autoNeg & 0x02) != 0;
                    duplex = enabled ? 'Auto-Negotiation Enabled' : 'Fixed Duplex';
                    description = 'IEEE 802.3 MAC/PHY (AutoNeg: sup=$supported, en=$enabled)';
                  }
                  break;
                case 2: // Power Via MDI (PoE)
                  if (orgPayload.length >= 3) {
                    final pwrFlags = orgPayload[0];
                    final pwrClass = orgPayload[2];
                    final pseSupported = (pwrFlags & 0x01) != 0;
                    final pseEnabled = (pwrFlags & 0x02) != 0;
                    powerMdi = 'PSE Supported: $pseSupported (En: $pseEnabled, Class $pwrClass)';
                    description = 'IEEE 802.3 Power Via MDI: $powerMdi';
                  }
                  break;
                case 3: // Link Aggregation
                  if (orgPayload.length >= 5) {
                    final aggStatus = orgPayload[0];
                    final aggPortId = (orgPayload[1] << 24) |
                        (orgPayload[2] << 16) |
                        (orgPayload[3] << 8) |
                        orgPayload[4];
                    final isAggregated = (aggStatus & 0x02) != 0;
                    linkAggregation = isAggregated
                        ? 'Aggregated (Port $aggPortId)'
                        : 'Not Aggregated';
                    description = 'IEEE 802.3 Link Aggregation: $linkAggregation';
                  }
                  break;
                case 4: // Maximum Frame Size
                  if (orgPayload.length >= 2) {
                    mtu = (orgPayload[0] << 8) | orgPayload[1];
                    description = 'IEEE 802.3 Max Frame Size (MTU): $mtu bytes';
                  }
                  break;
                default:
                  description = 'IEEE 802.3 Subtype $subtype';
              }
            } else if (oui == 0x0012BB) {
              // TIA LLDP-MED
              description = 'TIA TR-41 LLDP-MED Subtype $subtype';
            } else {
              final ouiHex = _bytesToHex(tlvBytes.sublist(0, 3));
              description = 'OUI: $ouiHex Subtype: $subtype';
            }
          }
          break;

        default:
          description = 'Length: $length bytes';
      }

      if (type != 0) {
        rawTlvs.add(TlvRecord(
          type: type,
          typeName: typeName,
          length: length,
          description: description,
          hexBytes: hexBytes,
        ));
      }
    }

    final rawHex = _formatHexDump(packet);

    return SwitchPortDiscovery(
      timestamp: timestamp ?? DateTime.now(),
      protocol: DiscoveryProtocol.lldp,
      switchHostname: switchHostname.isNotEmpty ? switchHostname : 'Unknown LLDP Switch',
      portId: portId.isNotEmpty ? portId : 'Unknown Port',
      switchModel: switchModel,
      portDescription: portDescription,
      vlanId: vlanId,
      vlanName: vlanName,
      managementIp: managementIp,
      chassisId: chassisId,
      ttl: ttl,
      capabilities: capabilities,
      powerMdi: powerMdi,
      linkAggregation: linkAggregation,
      mtu: mtu,
      duplex: duplex,
      rawTlvs: rawTlvs,
      rawHex: rawHex,
      rawBytes: packet,
      interfaceName: interfaceName,
    );
  }

  static String _decodeChassisOrPort(int subtype, Uint8List data) {
    if (subtype == 4 || subtype == 3) {
      // Often MAC address if 6 bytes
      if (data.length == 6) {
        return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
      }
    }
    final text = _safeAsciiString(data);
    if (text.isNotEmpty && text.runes.every((r) => r >= 32 && r < 127)) {
      return text;
    }
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }

  static List<String> _decodeCapabilities(int caps) {
    final list = <String>[];
    if ((caps & 0x0001) != 0) list.add('Other');
    if ((caps & 0x0002) != 0) list.add('Repeater');
    if ((caps & 0x0004) != 0) list.add('Bridge/Switch');
    if ((caps & 0x0008) != 0) list.add('WLAN Access Point');
    if ((caps & 0x0010) != 0) list.add('Router');
    if ((caps & 0x0020) != 0) list.add('Telephone');
    if ((caps & 0x0040) != 0) list.add('DOCSIS Cable Device');
    if ((caps & 0x0080) != 0) list.add('Station Only');
    return list;
  }

  static String _extractModelFromDescription(String desc) {
    final firstLine = desc.split(RegExp(r'[\r\n]+')).first.trim();
    if (firstLine.isEmpty) return 'LLDP Managed Switch';

    // Check for common switch patterns
    if (desc.contains('C9200') || desc.contains('Catalyst 9200')) {
      return 'Cisco Catalyst 9200';
    } else if (desc.contains('M4250')) {
      return 'Netgear M4250 AV Line';
    } else if (desc.contains('Aruba') || desc.contains('ProCurve')) {
      return 'Aruba CX / ProCurve';
    } else if (desc.contains('Juniper') || desc.contains('JUNOS')) {
      return 'Juniper Junos OS';
    } else if (desc.contains('MikroTik') || desc.contains('RouterOS')) {
      return 'MikroTik RouterOS / SwitchOS';
    }

    if (firstLine.length > 45) {
      return '${firstLine.substring(0, 42)}...';
    }
    return firstLine;
  }

  static String _decodeIpv6(Uint8List bytes) {
    final parts = <String>[];
    for (int i = 0; i < 16; i += 2) {
      final val = (bytes[i] << 8) | bytes[i + 1];
      parts.add(val.toRadixString(16));
    }
    return parts.join(':');
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
