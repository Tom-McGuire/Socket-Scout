import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/capture/capture_service.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
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
  });
}
