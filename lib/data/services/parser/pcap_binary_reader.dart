import 'dart:io';
import 'dart:typed_data';

class RawCapturedPacket {
  const RawCapturedPacket({
    required this.packetNo,
    required this.timestamp,
    required this.linkType,
    required this.data,
  });

  final int packetNo;
  final DateTime timestamp;
  final int linkType; // 1 = Ethernet II
  final Uint8List data;
}

class PcapBinaryReader {
  static const int pcapMagicBe = 0xA1B2C3D4;
  static const int pcapMagicLe = 0xD4C3B2A1;
  static const int pcapNanoMagicBe = 0xA1B23C4D;
  static const int pcapNanoMagicLe = 0x4D3CB2A1;
  static const int pcapNgShb = 0x0A0D0D0A;

  /// Parses complete PCAP or PCAPNG buffer into raw captured packets.
  static List<RawCapturedPacket> parseBytes(Uint8List bytes) {
    if (bytes.length < 24) return [];

    final bd = ByteData.sublistView(bytes);
    final magicBe = bd.getUint32(0, Endian.big);

    if (magicBe == pcapMagicBe ||
        magicBe == pcapMagicLe ||
        magicBe == pcapNanoMagicBe ||
        magicBe == pcapNanoMagicLe) {
      return _parseClassicPcap(bytes);
    } else if (magicBe == pcapNgShb) {
      return _parsePcapNg(bytes);
    }

    return [];
  }

  static List<RawCapturedPacket> parseFile(File file) {
    if (!file.existsSync()) return [];
    final bytes = file.readAsBytesSync();
    return parseBytes(bytes);
  }

  static List<RawCapturedPacket> _parseClassicPcap(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final magic = bd.getUint32(0, Endian.big);
    final isNano = magic == pcapNanoMagicBe || magic == pcapNanoMagicLe;
    final endian = (magic == pcapMagicBe || magic == pcapNanoMagicBe)
        ? Endian.big
        : Endian.little;

    final linkType = bd.getUint32(20, endian);
    int offset = 24;
    int packetNo = 1;
    final packets = <RawCapturedPacket>[];

    while (offset + 16 <= bytes.length) {
      final tsSec = bd.getUint32(offset, endian);
      final tsFraction = bd.getUint32(offset + 4, endian);
      final inclLen = bd.getUint32(offset + 8, endian);
      offset += 16;

      if (offset + inclLen > bytes.length) break;

      final packetData = bytes.sublist(offset, offset + inclLen);
      offset += inclLen;

      final tsMicro = isNano
          ? (tsSec * 1000000 + (tsFraction ~/ 1000))
          : (tsSec * 1000000 + tsFraction);

      packets.add(
        RawCapturedPacket(
          packetNo: packetNo++,
          timestamp: DateTime.fromMicrosecondsSinceEpoch(tsMicro),
          linkType: linkType,
          data: packetData,
        ),
      );
    }

    return packets;
  }

  static List<RawCapturedPacket> _parsePcapNg(Uint8List bytes) {
    final packets = <RawCapturedPacket>[];
    int offset = 0;
    int packetNo = 1;
    Endian endian = Endian.little;

    while (offset + 8 <= bytes.length) {
      final bd = ByteData.sublistView(bytes, offset, 8);
      final blockType = bd.getUint32(0, endian);
      final blockLength = bd.getUint32(4, endian);

      if (blockLength < 12 || offset + blockLength > bytes.length) break;

      if (blockType == pcapNgShb) {
        if (offset + 12 <= bytes.length) {
          final magic = ByteData.sublistView(bytes, offset + 8, 4).getUint32(0, Endian.big);
          endian = (magic == 0x1A2B3C4D) ? Endian.big : Endian.little;
        }
      } else if (blockType == 0x00000006) {
        // Enhanced Packet Block (EPB)
        if (offset + 32 <= bytes.length) {
          final epbBd = ByteData.sublistView(bytes, offset, 32);
          final tsHigh = epbBd.getUint32(12, endian);
          final tsLow = epbBd.getUint32(16, endian);
          final capLen = epbBd.getUint32(20, endian);

          final rawTs = (tsHigh << 32) | tsLow;
          final tsMicro = rawTs; // Standard default 1us resolution

          if (offset + 28 + capLen <= bytes.length) {
            final packetData = bytes.sublist(offset + 28, offset + 28 + capLen);
            packets.add(
              RawCapturedPacket(
                packetNo: packetNo++,
                timestamp: DateTime.fromMicrosecondsSinceEpoch(tsMicro),
                linkType: 1, // Ethernet
                data: packetData,
              ),
            );
          }
        }
      }

      final pad = (4 - (blockLength % 4)) % 4;
      offset += blockLength + pad;
    }

    return packets;
  }
}

/// Helper for streaming PCAP data chunks from stdout of tcpdump / tshark.
class StreamingPcapParser {
  final List<int> _buffer = [];
  bool _headerParsed = false;
  Endian _endian = Endian.little;
  bool _isNano = false;
  int _linkType = 1;
  int _packetNo = 1;

  List<RawCapturedPacket> appendChunk(List<int> chunk) {
    _buffer.addAll(chunk);
    final results = <RawCapturedPacket>[];

    if (!_headerParsed) {
      if (_buffer.length < 24) return results;
      final headerBytes = Uint8List.fromList(_buffer.sublist(0, 24));
      final bd = ByteData.sublistView(headerBytes);
      final magic = bd.getUint32(0, Endian.big);

      if (magic == PcapBinaryReader.pcapMagicBe ||
          magic == PcapBinaryReader.pcapNanoMagicBe) {
        _endian = Endian.big;
        _isNano = magic == PcapBinaryReader.pcapNanoMagicBe;
      } else if (magic == PcapBinaryReader.pcapMagicLe ||
          magic == PcapBinaryReader.pcapNanoMagicLe) {
        _endian = Endian.little;
        _isNano = magic == PcapBinaryReader.pcapNanoMagicLe;
      } else {
        // Unknown or raw frames - clear and abort header parse
        _buffer.clear();
        return results;
      }

      _linkType = bd.getUint32(20, _endian);
      _buffer.removeRange(0, 24);
      _headerParsed = true;
    }

    while (_buffer.length >= 16) {
      final headerBytes = Uint8List.fromList(_buffer.sublist(0, 16));
      final bd = ByteData.sublistView(headerBytes);
      final tsSec = bd.getUint32(0, _endian);
      final tsFraction = bd.getUint32(4, _endian);
      final inclLen = bd.getUint32(8, _endian);

      if (inclLen > 65535 || inclLen <= 0) {
        // Out of sync - clear buffer
        _buffer.clear();
        break;
      }

      if (_buffer.length < 16 + inclLen) {
        // Wait for next chunk to complete packet
        break;
      }

      final packetData = Uint8List.fromList(_buffer.sublist(16, 16 + inclLen));
      _buffer.removeRange(0, 16 + inclLen);

      final tsMicro = _isNano
          ? (tsSec * 1000000 + (tsFraction ~/ 1000))
          : (tsSec * 1000000 + tsFraction);

      results.add(
        RawCapturedPacket(
          packetNo: _packetNo++,
          timestamp: DateTime.fromMicrosecondsSinceEpoch(
            tsMicro > 0 ? tsMicro : DateTime.now().microsecondsSinceEpoch,
          ),
          linkType: _linkType,
          data: packetData,
        ),
      );
    }

    return results;
  }

  void reset() {
    _buffer.clear();
    _headerParsed = false;
    _packetNo = 1;
  }
}
