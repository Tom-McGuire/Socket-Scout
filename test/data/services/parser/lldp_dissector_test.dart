import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/services/generator/demo_l2_generator.dart';
import 'package:socket_scout/data/services/parser/lldp_dissector.dart';
import 'package:socket_scout/domain/models/switch_port_discovery.dart';

void main() {
  group('LldpDissector', () {
    test('identifies LLDP frames correctly', () {
      final packet = DemoL2Generator.ciscoCatalyst9200Lldp();
      expect(LldpDissector.isLldpFrame(packet), isTrue);

      final cdpPacket = DemoL2Generator.ciscoCatalyst9200Cdp();
      expect(LldpDissector.isLldpFrame(cdpPacket), isFalse);
    });

    test('dissects Cisco Catalyst 9200 LLDP frame accurately', () {
      final packet = DemoL2Generator.ciscoCatalyst9200Lldp();
      final discovery = LldpDissector.dissect(packet: packet);

      expect(discovery, isNotNull);
      expect(discovery!.protocol, equals(DiscoveryProtocol.lldp));
      expect(discovery.switchHostname, equals('SW-CAT9200-RACK04.corp.local'));
      expect(discovery.portId, equals('GigabitEthernet1/0/14'));
      expect(discovery.portDescription, contains('Access Drop Room 204B'));
      expect(discovery.switchModel, equals('Cisco Catalyst 9200'));
      expect(discovery.vlanId, equals(20));
      expect(discovery.managementIp, equals('10.20.4.15'));
      expect(discovery.ttl, equals(120));
      expect(discovery.capabilities, contains('Bridge/Switch'));
      expect(discovery.powerMdi, contains('PSE Supported: true'));
      expect(discovery.rawTlvs.length, greaterThanOrEqualTo(8));
    });

    test('dissects Netgear M4250 ProAV switch LLDP frame with VLAN 100', () {
      final packet = DemoL2Generator.netgearM4250Lldp();
      final discovery = LldpDissector.dissect(packet: packet);

      expect(discovery, isNotNull);
      expect(discovery!.switchHostname, equals('NETGEAR-M4250-AUDITORIUM'));
      expect(discovery.portId, equals('Port 7'));
      expect(discovery.vlanId, equals(100));
      expect(discovery.switchModel, equals('Netgear M4250 AV Line'));
      expect(discovery.managementIp, equals('192.168.100.254'));
    });

    test('dissects Aruba CX 6200F LLDP frame', () {
      final packet = DemoL2Generator.arubaCx6200Lldp();
      final discovery = LldpDissector.dissect(packet: packet);

      expect(discovery, isNotNull);
      expect(discovery!.switchHostname, equals('aruba-cx-floor3-east'));
      expect(discovery.portId, equals('1/1/24'));
      expect(discovery.vlanId, equals(10));
      expect(discovery.switchModel, equals('Aruba CX / ProCurve'));
    });
  });
}
