import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/capture/capture_service.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
import 'package:socket_scout/domain/models/launch_adapter_config.dart';
import 'package:socket_scout/domain/models/network_adapter_info.dart';
import 'package:socket_scout/domain/models/switch_port_discovery.dart';
import 'package:socket_scout/ui/features/scout/view_models/socket_scout_view_model.dart';

void main() {
  group('SocketScoutViewModel', () {
    late SwitchDatabaseService dbService;
    late CaptureService captureService;
    late SwitchDiscoveryRepository repository;
    late SocketScoutViewModel viewModel;

    setUp(() async {
      dbService = SwitchDatabaseService();
      dbService.initInMemory();
      captureService = CaptureService();
      repository = SwitchDiscoveryRepository(
        dbService: dbService,
        captureService: captureService,
      );
      viewModel = SocketScoutViewModel(
        repository: repository,
        initialAdapters: const [
          NetworkAdapterInfo(name: 'eth0', displayName: 'eth0', ipAddress: '192.168.1.100'),
        ],
      );
      await viewModel.initFuture;
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('initializes with empty discoveries and idle state', () {
      expect(viewModel.isListening, isFalse);
      expect(viewModel.discoveries, isEmpty);
      expect(viewModel.totalDiscoveriesCount, equals(0));
      expect(viewModel.selectedDiscovery, isNull);
    });

    test('loading demo data populates latestDiscovery and selectedDiscovery', () {
      viewModel.loadDemoData();

      expect(viewModel.totalDiscoveriesCount, equals(5));
      expect(viewModel.discoveries.length, equals(5));
      expect(viewModel.latestDiscovery, isNotNull);
      expect(viewModel.selectedDiscovery, isNotNull);
    });

    test('search query and protocol filters update view model discoveries', () {
      viewModel.loadDemoData();

      viewModel.setProtocolFilter(DiscoveryProtocol.cdp);
      expect(viewModel.discoveries.length, equals(1));
      expect(viewModel.discoveries.first.protocol, equals(DiscoveryProtocol.cdp));

      viewModel.clearFilters();
      expect(viewModel.discoveries.length, equals(5));

      viewModel.setSearchQuery('Juniper');
      expect(viewModel.discoveries.length, equals(1));
      expect(viewModel.discoveries.first.switchHostname, contains('JUNIPER'));
    });

    test('clearAll wipes discovery history', () {
      viewModel.loadDemoData();
      expect(viewModel.totalDiscoveriesCount, equals(5));

      viewModel.clearAll();
      expect(viewModel.totalDiscoveriesCount, equals(0));
      expect(viewModel.discoveries, isEmpty);
      expect(viewModel.selectedDiscovery, isNull);
    });

    test('startDemoWalkthrough and endDemoWalkthrough manage demo lifecycle', () {
      expect(viewModel.isDemoMode, isFalse);

      viewModel.startDemoWalkthrough();
      expect(viewModel.isDemoMode, isTrue);
      expect(viewModel.totalDiscoveriesCount, equals(5));
      expect(viewModel.selectedDiscovery, isNotNull);

      viewModel.endDemoWalkthrough();
      expect(viewModel.isDemoMode, isFalse);
      expect(viewModel.totalDiscoveriesCount, equals(0));
      expect(viewModel.selectedDiscovery, isNull);

      viewModel.loadDemoData();
      expect(viewModel.totalDiscoveriesCount, equals(5));
      viewModel.clearFrames();
      expect(viewModel.totalDiscoveriesCount, equals(0));
    });
  });

  group('SocketScoutViewModel LaunchAdapterConfig startup override', () {
    const adapterList = [
      NetworkAdapterInfo.all,
      NetworkAdapterInfo(
        name: 'eth0',
        displayName: 'Ethernet Primary',
        ipAddress: '192.168.1.50',
      ),
      NetworkAdapterInfo(
        name: 'enp3s0',
        displayName: 'USB-C Gigabit',
        ipAddress: '10.20.30.40',
      ),
    ];

    Future<SocketScoutViewModel> createWithConfig(
      LaunchAdapterConfig config,
    ) async {
      final db = SwitchDatabaseService()..initInMemory();
      final repo = SwitchDiscoveryRepository(
        dbService: db,
        captureService: CaptureService(),
      );
      final vm = SocketScoutViewModel(
        repository: repo,
        initialAdapterConfig: config,
        adapterProvider: () async => adapterList,
      );
      await vm.initFuture;
      return vm;
    }

    test('pre-selects matching adapter by IPv4 (Priority 1) over name', () async {
      final vm = await createWithConfig(
        const LaunchAdapterConfig(
          adapterIp: '10.20.30.40',
          adapterName: 'eth0',
        ),
      );
      addTearDown(vm.dispose);

      expect(vm.selectedAdapter?.name, equals('enp3s0'));
      expect(vm.selectedAdapter?.ipAddress, equals('10.20.30.40'));
    });

    test('falls back to case-insensitive name match (Priority 2)', () async {
      final vm = await createWithConfig(
        const LaunchAdapterConfig(
          adapterIp: '172.16.0.99',
          adapterName: 'usb-c gigabit',
        ),
      );
      addTearDown(vm.dispose);

      expect(vm.selectedAdapter?.name, equals('enp3s0'));
    });

    test('falls back to default adapter when neither IP nor name matches', () async {
      final vm = await createWithConfig(
        const LaunchAdapterConfig(
          adapterIp: '172.16.0.99',
          adapterName: 'wlan99',
        ),
      );
      addTearDown(vm.dispose);

      // Default skips NetworkAdapterInfo.all and chooses index 1 ('eth0')
      expect(vm.selectedAdapter?.name, equals('eth0'));
    });

    test('applies startup override only once and preserves subsequent manual selection', () async {
      final vm = await createWithConfig(
        const LaunchAdapterConfig(adapterIp: '10.20.30.40'),
      );
      addTearDown(vm.dispose);

      expect(vm.selectedAdapter?.name, equals('enp3s0'));

      // User manually switches to eth0
      vm.selectAdapter(adapterList[1]);
      expect(vm.selectedAdapter?.name, equals('eth0'));

      // Subsequent adapter refresh must NOT reset back to CLI override
      await vm.refreshAdapters();
      expect(vm.selectedAdapter?.name, equals('eth0'));
    });
  });
}
