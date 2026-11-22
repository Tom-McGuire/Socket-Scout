import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
import 'package:socket_scout/data/services/export/export_service.dart';
import 'package:socket_scout/data/services/network/network_adapter_service.dart';
import 'package:socket_scout/domain/models/network_adapter_info.dart';
import 'package:socket_scout/domain/models/wifi_ap_discovery.dart';
import 'package:socket_scout/ui/features/scout/view_models/socket_scout_view_model.dart';
import 'package:socket_scout/ui/features/scout/views/dialogs/edit_device_dialog.dart';
import 'package:socket_scout/ui/features/scout/views/socket_scout_screen.dart';
import 'package:socket_scout/ui/theme/app_theme.dart';

void main() {
  group('AdapterKind & OS Wi-Fi adapter detection', () {
    test('classifies wired, wifi, and any interfaces accurately', () {
      expect(
        NetworkAdapterService.classifyAdapterKind('any'),
        AdapterKind.any,
      );
      expect(
        NetworkAdapterService.classifyAdapterKind('eth0'),
        AdapterKind.wired,
      );
      expect(
        NetworkAdapterService.classifyAdapterKind('enp3s0'),
        AdapterKind.wired,
      );
      expect(
        NetworkAdapterService.classifyAdapterKind('wlan0'),
        AdapterKind.wifi,
      );
      expect(
        NetworkAdapterService.classifyAdapterKind('wlp2s0'),
        AdapterKind.wifi,
      );
      expect(
        NetworkAdapterService.classifyAdapterKind(
          'en0',
          osWifiNames: const {'en0'},
        ),
        AdapterKind.wifi,
      );
      expect(
        NetworkAdapterService.classifyAdapterKind(
          'eth9',
          hasLinuxWirelessDir: true,
        ),
        AdapterKind.wifi,
      );
    });

    test('parses Windows netsh and macOS networksetup Wi-Fi names', () {
      const winOut = '''
    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6E AX211 160MHz
''';
      final winNames = NetworkAdapterService.parseWindowsWifiAdapterNames(winOut);
      expect(winNames, contains('Wi-Fi'));
      expect(winNames, contains('Intel(R) Wi-Fi 6E AX211 160MHz'));

      const macOut = '''
Hardware Port: Ethernet Adapter (en4)
Device: en4
Ethernet Address: 00:11:22:33:44:55

Hardware Port: Wi-Fi
Device: en0
Ethernet Address: aa:bb:cc:dd:ee:ff
''';
      final macDevices = NetworkAdapterService.parseMacOsWifiDevices(macOut);
      expect(macDevices, equals({'en0'}));
    });
  });

  group('SwitchDiscoveryRepository Wi-Fi AP persistence & Shared DB sync', () {
    late SwitchDatabaseService dbService;
    late SwitchDiscoveryRepository repository;

    setUp(() async {
      dbService = SwitchDatabaseService()..initInMemory();
      SharedDeviceDatabase.instance.close();
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      repository = SwitchDiscoveryRepository(
        dbService: dbService,
        sharedDb: SharedDeviceDatabase.instance,
      );
    });

    tearDown(() {
      repository.dispose();
      SharedDeviceDatabase.instance.close();
    });

    test('syncs genuine Wi-Fi AP to SharedDeviceDatabase with deviceType ap', () {
      final ap = WifiApDiscovery(
        timestamp: DateTime.now(),
        interfaceName: 'wlan0',
        ssid: 'CORP-5G',
        bssid: '00:18:0a:44:55:66',
        apHostname: 'AP-CONF-01',
        band: WifiBand.band5,
        channel: 36,
        rssiDbm: -55,
        securityType: 'WPA3-Enterprise',
        isDemo: false,
      );

      repository.recordWifiDiscovery(ap);

      expect(dbService.countWifiDiscoveries(), 1);
      final stored = SharedDeviceDatabase.instance
          .getDeviceByMac('00:18:0A:44:55:66');
      expect(stored, isNotNull);
      expect(stored!.deviceType, DeviceCategory.accessPoint.key);
      expect(stored.deviceType, 'ap');
      expect(stored.name, 'AP-CONF-01');
      expect(stored.notes, contains('SSID: CORP-5G'));
      expect(stored.notes, contains('Band: 5 GHz'));
      expect(stored.notes, contains('Ch: 36'));
    });

    test('strictly excludes Wi-Fi demo presets from SharedDeviceDatabase', () {
      repository.loadWifiDemoPresets(interfaceName: 'wlan0');

      expect(repository.inMemoryWifiDiscoveries.length, 3);
      expect(dbService.countWifiDiscoveries(), 3);
      // Shared DB must remain completely empty!
      expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
    });

    test('exports Wi-Fi AP discoveries to CSV, JSON, and Text Report', () {
      repository.loadWifiDemoPresets(interfaceName: 'wlan0');
      final records = repository.inMemoryWifiDiscoveries;

      final csv = ExportService.wifiToCsv(records);
      expect(csv, contains('BSSID'));
      expect(csv, contains('CORP-HQ-WIFI'));

      final json = ExportService.wifiToJson(records);
      expect(json, contains('"bssid"'));
      expect(json, contains('94:B4:0F:77:88:99'));

      final report = ExportService.wifiToTextReport(records);
      expect(report, contains('WI-FI ACCESS POINT DISCOVERY REPORT'));
      expect(report, contains('AP-FL3-ENG-655'));
    });
  });

  group('Wi-Fi AP Scout UI & Mode Switching', () {
    setUp(() async {
      AppTheme.isDark = true;
      SharedDeviceDatabase.instance.close();
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
    });

    tearDown(() {
      SharedDeviceDatabase.instance.close();
    });

    testWidgets(
      'switches automatically between Wired and Wi-Fi modes, filters bands, and opens prefilled AP EditDeviceDialog on right-click',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final dbService = SwitchDatabaseService()..initInMemory();
        final repo = SwitchDiscoveryRepository(
          dbService: dbService,
          sharedDb: SharedDeviceDatabase.instance,
        );

        const wiredAdapter = NetworkAdapterInfo(
          name: 'eth0',
          displayName: 'eth0',
          ipAddress: '192.168.1.50',
          kind: AdapterKind.wired,
        );
        const wifiAdapter = NetworkAdapterInfo(
          name: 'wlan0',
          displayName: 'wlan0',
          ipAddress: '192.168.1.88',
          kind: AdapterKind.wifi,
        );

        final vm = SocketScoutViewModel(
          repository: repo,
          initialAdapters: const [wiredAdapter, wifiAdapter],
        );
        addTearDown(vm.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<SocketScoutViewModel>.value(
            value: vm,
            child: MaterialApp(
              theme: AppTheme.darkTheme(),
              home: const SocketScoutScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially in Wired mode
        expect(vm.isWifiMode, isFalse);
        expect(find.text('Switch Port Identifier (LLDP / CDP)'), findsOneWidget);
        expect(find.text('ALL PROTOCOLS'), findsOneWidget);
        expect(find.text('Open PCAP'), findsOneWidget);

        // Switch Zone 2 adapter to Wi-Fi
        vm.selectAdapter(wifiAdapter);
        await tester.pumpAndSettle();

        expect(vm.isWifiMode, isTrue);
        expect(find.text('Wi-Fi Access Point Scout (BSSID / RF)'), findsOneWidget);
        expect(find.text('ALL BANDS'), findsOneWidget);
        expect(find.text('5 GHz'), findsOneWidget);
        expect(find.text('6 GHz'), findsOneWidget);
        expect(find.text('Open PCAP'), findsNothing);
        expect(find.text('Wi-Fi Access Point Scout Mode Ready'), findsOneWidget);

        // Load Wi-Fi demo presets
        vm.loadDemoData();
        await tester.pumpAndSettle();

        expect(find.text('AP-FL3-ENG-655'), findsWidgets);
        expect(find.text('DEMO PRESET'), findsOneWidget);
        expect(find.text('NEIGHBOR APs (3)'), findsOneWidget);

        // Filter to 5 GHz band only
        await tester.tap(find.text('5 GHz').first);
        await tester.pumpAndSettle();
        expect(vm.wifiDiscoveries.length, 1);
        expect(vm.wifiDiscoveries.first.apHostname, 'AP-FL2-CONF-MR46');

        // Reset filter
        vm.clearFilters();
        await tester.pumpAndSettle();
        expect(vm.wifiDiscoveries.length, 3);

        // Right-click Hero AP Card to open context menu & EditDeviceDialog
        final heroFinder = find.text('DEMO PRESET');
        final center = tester.getCenter(heroFinder);
        await tester.tapAt(center, buttons: kSecondaryMouseButton);
        await tester.pumpAndSettle();

        expect(find.textContaining('Add Demo AP to Shared Library'), findsOneWidget);
        expect(find.textContaining('Copy BSSID'), findsOneWidget);

        await tester.tap(find.textContaining('Add Demo AP to Shared Library'));
        await tester.pumpAndSettle();

        expect(find.byType(EditDeviceDialog), findsOneWidget);
        expect(find.text('Add Access Point to Shared Library'), findsOneWidget);

        // Close dialog & switch back to Wired mode cleanly
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        vm.selectAdapter(wiredAdapter);
        await tester.pumpAndSettle();
        expect(vm.isWifiMode, isFalse);
        expect(find.text('ALL PROTOCOLS'), findsOneWidget);
      },
    );

    testWidgets(
      'renders Wi-Fi AP Scout workspace cleanly in Light Mode',
      (WidgetTester tester) async {
        AppTheme.isDark = false;
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          AppTheme.isDark = true;
          tester.view.resetPhysicalSize();
        });

        final dbService = SwitchDatabaseService()..initInMemory();
        final repo = SwitchDiscoveryRepository(
          dbService: dbService,
          sharedDb: SharedDeviceDatabase.instance,
        );

        const wifiAdapter = NetworkAdapterInfo(
          name: 'wlan0',
          displayName: 'wlan0',
          kind: AdapterKind.wifi,
        );

        final vm = SocketScoutViewModel(
          repository: repo,
          initialAdapters: const [wifiAdapter],
        );
        addTearDown(vm.dispose);

        await tester.pumpWidget(
          ChangeNotifierProvider<SocketScoutViewModel>.value(
            value: vm,
            child: MaterialApp(
              theme: AppTheme.lightTheme(),
              home: const SocketScoutScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        vm.loadDemoData();
        await tester.pumpAndSettle();

        expect(find.text('Wi-Fi Access Point Scout (BSSID / RF)'), findsOneWidget);
        expect(find.text('AP-FL3-ENG-655'), findsWidgets);
      },
    );
  });
}
