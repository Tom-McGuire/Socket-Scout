import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/services/generator/demo_l2_generator.dart';
import 'package:socket_scout/data/services/parser/cdp_dissector.dart';
import 'package:socket_scout/domain/models/switch_port_discovery.dart';

void main() {
  group('CdpDissector', () {
    test('identifies CDP frames correctly', () {
      final cdpPacket = DemoL2Generator.ciscoCatalyst9200Cdp();
      expect(CdpDissector.isCdpFrame(cdpPacket), isTrue);

      final lldpPacket = DemoL2Generator.ciscoCatalyst9200Lldp();
      expect(CdpDissector.isCdpFrame(lldpPacket), isFalse);
    });

    test('dissects Cisco Catalyst 9200 CDP frame accurately', () {
      final packet = DemoL2Generator.ciscoCatalyst9200Cdp();
      final discovery = CdpDissector.dissect(packet: packet);

      expect(discovery, isNotNull);
      expect(discovery!.protocol, equals(DiscoveryProtocol.cdp));
      expect(discovery.switchHostname, equals('SW-CAT9200-RACK04.corp.local'));
      expect(discovery.portId, equals('GigabitEthernet1/0/14'));
      expect(discovery.switchModel, equals('cisco Catalyst 9200-24P'));
      expect(discovery.managementIp, equals('10.20.4.15'));
      expect(discovery.vlanId, equals(20));
      expect(discovery.vtpDomain, equals('CORP-SWITCHING'));
      expect(discovery.duplex, equals('Full Duplex'));
      expect(discovery.powerMdi, contains('15.4W'));
      expect(discovery.capabilities, contains('Switch'));
      expect(discovery.capabilities, contains('Router'));
      expect(discovery.rawTlvs.length, greaterThanOrEqualTo(7));
    });
  });
}
