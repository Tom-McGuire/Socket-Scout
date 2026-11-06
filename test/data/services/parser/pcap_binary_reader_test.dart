import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/services/generator/demo_l2_generator.dart';
import 'package:socket_scout/data/services/parser/pcap_binary_reader.dart';

void main() {
  group('PcapBinaryReader & StreamingPcapParser', () {
    test('streaming parser processes PCAP stream chunks seamlessly', () {
      final parser = StreamingPcapParser();

      // Build simulated classic PCAP stream with magic 0xa1b2c3d4
      final globalHeader = Uint8List(24);
      final gBd = ByteData.sublistView(globalHeader);
      gBd.setUint32(0, 0xa1b2c3d4, Endian.big); // Magic
      gBd.setUint16(4, 2, Endian.big); // Major
      gBd.setUint16(6, 4, Endian.big); // Minor
      gBd.setUint32(20, 1, Endian.big); // LinkType Ethernet (1)

      final packet1 = DemoL2Generator.ciscoCatalyst9200Lldp();

      final pktHeader = Uint8List(16);
      final pBd = ByteData.sublistView(pktHeader);
      pBd.setUint32(0, 1700000000, Endian.big); // sec
      pBd.setUint32(4, 500000, Endian.big); // usec
      pBd.setUint32(8, packet1.length, Endian.big); // incl_len
      pBd.setUint32(12, packet1.length, Endian.big); // orig_len

      final streamBytes = <int>[
        ...globalHeader,
        ...pktHeader,
        ...packet1,
      ];

      // Feed in small arbitrary chunk fragments
      final chunk1 = streamBytes.sublist(0, 30);
      final chunk2 = streamBytes.sublist(30, 80);
      final chunk3 = streamBytes.sublist(80);

      final res1 = parser.appendChunk(chunk1);
      expect(res1, isEmpty);

      final res2 = parser.appendChunk(chunk2);
      expect(res2, isEmpty);

      final res3 = parser.appendChunk(chunk3);
      expect(res3.length, equals(1));
      expect(res3.first.linkType, equals(1));
      expect(res3.first.data.length, equals(packet1.length));
    });
  });
}
