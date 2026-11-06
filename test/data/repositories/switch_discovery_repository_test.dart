import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/capture/capture_service.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
import 'package:socket_scout/data/services/export/export_service.dart';
import 'package:socket_scout/domain/models/discovery_filter.dart';
import 'package:socket_scout/domain/models/switch_port_discovery.dart';

void main() {
  group('SwitchDiscoveryRepository & Database', () {
    late SwitchDatabaseService dbService;
    late CaptureService captureService;
    late SwitchDiscoveryRepository repository;

    setUp(() async {
      dbService = SwitchDatabaseService();
      dbService.initInMemory();
      captureService = CaptureService();
      repository = SwitchDiscoveryRepository(
        dbService: dbService,
        captureService: captureService,
      );
    });

    tearDown(() {
      repository.dispose();
    });

    test('loads demo presets and stores discoveries in database', () {
      repository.loadDemoPresets();

      expect(repository.inMemoryDiscoveries.length, equals(5));
      expect(repository.latestDiscovery, isNotNull);

      // Verify Cisco Catalyst CDP & LLDP
      final cisco = repository.inMemoryDiscoveries.firstWhere(
        (d) => d.switchHostname.contains('SW-CAT9200'),
      );
      expect(cisco.portId, equals('GigabitEthernet1/0/14'));
      expect(cisco.vlanId, equals(20));
      expect(cisco.managementIp, equals('10.20.4.15'));

      // Verify database count
      final dbCount = dbService.countDiscoveries();
      expect(dbCount, equals(5));
    });

    test('filters discoveries by protocol and search query', () {
      repository.loadDemoPresets();

      // Filter by LLDP
      final lldpOnly = repository.getFiltered(
        filter: const DiscoveryFilter(protocol: DiscoveryProtocol.lldp),
      );
      expect(lldpOnly.length, equals(4));

      // Filter by CDP
      final cdpOnly = repository.getFiltered(
        filter: const DiscoveryFilter(protocol: DiscoveryProtocol.cdp),
      );
      expect(cdpOnly.length, equals(1));
      expect(cdpOnly.first.protocol, equals(DiscoveryProtocol.cdp));

      // Filter by search query "Netgear"
      final netgear = repository.getFiltered(
        filter: const DiscoveryFilter(searchQuery: 'Netgear'),
      );
      expect(netgear.length, equals(1));
      expect(netgear.first.switchHostname, contains('NETGEAR'));
      expect(netgear.first.vlanId, equals(100));

      // Filter by VLAN 10
      final vlan10 = repository.getFiltered(
        filter: const DiscoveryFilter(vlanId: 10),
      );
      expect(vlan10.length, equals(1));
      expect(vlan10.first.switchHostname, contains('aruba'));
    });

    test('exports records to CSV, JSON and text reports', () {
      repository.loadDemoPresets();

      final csv = ExportService.toCsv(repository.inMemoryDiscoveries);
      expect(csv, contains('Switch Hostname'));
      expect(csv, contains('SW-CAT9200-RACK04.corp.local'));

      final json = ExportService.toJson(repository.inMemoryDiscoveries);
      expect(json, contains('"switch_hostname": "SW-CAT9200-RACK04.corp.local"'));

      final report = ExportService.toTextReport(repository.inMemoryDiscoveries);
      expect(report, contains('SOCKET SCOUT - SWITCH PORT DISCOVERY REPORT'));
      expect(report, contains('Physical Port:   GigabitEthernet1/0/14'));
    });
  });
}
