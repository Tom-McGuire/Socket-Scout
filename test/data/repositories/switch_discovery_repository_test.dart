import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
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
    late SharedDeviceDatabase sharedDb;
    late SwitchDiscoveryRepository repository;

    setUp(() async {
      dbService = SwitchDatabaseService();
      dbService.initInMemory();
      captureService = CaptureService();
      sharedDb = SharedDeviceDatabase();
      await sharedDb.init(dbPath: ':memory:');
      repository = SwitchDiscoveryRepository(
        dbService: dbService,
        captureService: captureService,
        sharedDb: sharedDb,
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

    test('synchronizes discovered switches into SharedDeviceDatabase with deviceType switch', () {
      repository.loadDemoPresets();

      // Cisco Catalyst 9200
      final ciscoMac = SharedDevice.normalizeMac('58:0A:20:4A:11:80');
      final ciscoDevice = sharedDb.getDeviceByMac(ciscoMac);
      expect(ciscoDevice, isNotNull);
      expect(ciscoDevice!.deviceType, equals('switch'));
      expect(ciscoDevice.name, equals('SW-CAT9200-RACK04.corp.local'));
      expect(ciscoDevice.vendor, equals('Cisco Systems, Inc.'));
      expect(ciscoDevice.notes, contains('Mgmt IP: 10.20.4.15'));
      expect(ciscoDevice.notes, contains('Port: GigabitEthernet1/0/14'));
      expect(ciscoDevice.notes, contains('VLAN: 20'));
      expect(ciscoDevice.sourceApp, equals('socket_scout'));

      // Netgear M4250
      final netgearMac = SharedDevice.normalizeMac('9C:34:26:88:99:AA');
      final netgearDevice = sharedDb.getDeviceByMac(netgearMac);
      expect(netgearDevice, isNotNull);
      expect(netgearDevice!.deviceType, equals('switch'));
      expect(netgearDevice.name, equals('NETGEAR-M4250-AUDITORIUM'));
      expect(netgearDevice.vendor, contains('Netgear'));
      expect(netgearDevice.notes, contains('VLAN: 100'));

      // Aruba CX
      final arubaMac = SharedDevice.normalizeMac('B0:8B:CF:12:34:56');
      final arubaDevice = sharedDb.getDeviceByMac(arubaMac);
      expect(arubaDevice, isNotNull);
      expect(arubaDevice!.deviceType, equals('switch'));
      expect(arubaDevice.name, equals('aruba-cx-floor3-east'));

      // All 4 distinct switch MACs are registered in shared DB
      final allSwitches = sharedDb.getAllDevices(deviceType: 'switch');
      expect(allSwitches.length, equals(4));
    });

    test('preserves user custom names in SharedDeviceDatabase on subsequent discoveries', () {
      // User has already set a custom friendly name in Shared Device Library
      final ciscoMac = SharedDevice.normalizeMac('58:0A:20:4A:11:80');
      sharedDb.upsertDevice(SharedDevice(
        macAddress: ciscoMac,
        name: 'Core Distribution Switch (Room 204)',
        deviceType: 'switch',
        sourceApp: 'user_custom',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // New discovery announcement arrives
      repository.loadDemoPresets();

      final updated = sharedDb.getDeviceByMac(ciscoMac);
      expect(updated, isNotNull);
      // Custom name is preserved
      expect(updated!.name, equals('Core Distribution Switch (Room 204)'));
      // Device type remains 'switch'
      expect(updated.deviceType, equals('switch'));
      // Notes are enriched with latest discovery telemetry
      expect(updated.notes, contains('Mgmt IP: 10.20.4.15'));
      expect(updated.notes, contains('Port: GigabitEthernet1/0/14'));
    });
  });
}
