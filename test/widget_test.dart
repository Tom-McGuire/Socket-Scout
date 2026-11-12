import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/capture/capture_service.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
import 'package:socket_scout/domain/models/network_adapter_info.dart';
import 'package:socket_scout/ui/features/scout/view_models/socket_scout_view_model.dart';
import 'package:socket_scout/ui/features/scout/views/socket_scout_screen.dart';
import 'package:socket_scout/ui/theme/app_theme.dart';

class FakeCaptureService extends CaptureService {
  CaptureStatus _fakeStatus = CaptureStatus.idle;

  @override
  CaptureStatus get status => _fakeStatus;

  @override
  Future<bool> startCapture({required String interfaceName}) async {
    _fakeStatus = CaptureStatus.listening;
    protectedSetStatus(CaptureStatus.listening);
    return true;
  }

  @override
  Future<void> stopCapture() async {
    _fakeStatus = CaptureStatus.stopped;
    protectedSetStatus(CaptureStatus.stopped);
  }
}

void main() {
  testWidgets('SocketScoutScreen renders 5-tier layout and empty state',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dbService = SwitchDatabaseService();
    dbService.initInMemory();
    final captureService = FakeCaptureService();
    final repo = SwitchDiscoveryRepository(
      dbService: dbService,
      captureService: captureService,
    );
    final vm = SocketScoutViewModel(
      repository: repo,
      initialAdapters: const [
        NetworkAdapterInfo(name: 'eth0', displayName: 'eth0', ipAddress: '192.168.1.100'),
      ],
    );
    await vm.initFuture;
    addTearDown(() => vm.dispose());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ChangeNotifierProvider<SocketScoutViewModel>.value(
          value: vm,
          child: const SocketScoutScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SOCKET SCOUT'), findsOneWidget);
    expect(find.text('START LISTENING'), findsWidgets);
    expect(find.text('Device Library'), findsOneWidget);
    expect(find.text('Load Demo'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);

    // Click Load Demo to verify state updates
    await tester.tap(find.text('Load Demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SW-CAT9200-RACK04.corp.local'), findsWidgets);
    expect(find.text('GigabitEthernet1/0/14'), findsWidgets);
  });

  testWidgets('Center empty state displays active listening state and toggles in sync with top bar',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dbService = SwitchDatabaseService();
    dbService.initInMemory();
    final captureService = FakeCaptureService();
    final repo = SwitchDiscoveryRepository(
      dbService: dbService,
      captureService: captureService,
    );
    final vm = SocketScoutViewModel(
      repository: repo,
      initialAdapters: const [
        NetworkAdapterInfo(name: 'eth0', displayName: 'eth0', ipAddress: '192.168.1.100'),
      ],
    );
    await vm.initFuture;
    addTearDown(() => vm.dispose());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ChangeNotifierProvider<SocketScoutViewModel>.value(
          value: vm,
          child: const SocketScoutScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Initially idle: center button says START LISTENING
    expect(find.text('No Switch Discovery Packets Received'), findsOneWidget);
    expect(find.text('START LISTENING'), findsNWidgets(2)); // top bar + center

    // Toggle listening on (via center button)
    await tester.tap(find.text('START LISTENING').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // When listening: center text updates to "Listening for Switch Announcements..."
    // and both buttons update to "STOP LISTENING"
    expect(find.text('Listening for Switch Announcements...'), findsOneWidget);
    expect(find.text('STOP LISTENING'), findsNWidgets(2)); // top bar + center

    // Toggle listening off (via center button)
    await tester.tap(find.text('STOP LISTENING').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No Switch Discovery Packets Received'), findsOneWidget);
    expect(find.text('START LISTENING'), findsNWidgets(2));
  });

  testWidgets('Top control bar opens Device Library dialog and interacts cleanly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dbService = SwitchDatabaseService();
    dbService.initInMemory();
    final captureService = FakeCaptureService();
    final repo = SwitchDiscoveryRepository(
      dbService: dbService,
      captureService: captureService,
    );
    final vm = SocketScoutViewModel(
      repository: repo,
      initialAdapters: const [
        NetworkAdapterInfo(name: 'eth0', displayName: 'eth0', ipAddress: '192.168.1.100'),
      ],
    );
    await vm.initFuture;
    addTearDown(() => vm.dispose());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ChangeNotifierProvider<SocketScoutViewModel>.value(
          value: vm,
          child: const SocketScoutScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Tap Device Library button
    await tester.tap(find.text('Device Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Device Library dialog opens
    expect(find.text('Shared Device Library'), findsOneWidget);
    expect(find.text('Add Device'), findsOneWidget);

    // Tap Close icon to dismiss dialog
    await tester.tap(find.byTooltip('Close'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Shared Device Library'), findsNothing);
  });

  testWidgets('Right-clicking discovery row or hero card opens context menu and prefills EditDeviceDialog',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final dbService = SwitchDatabaseService();
    dbService.initInMemory();
    final captureService = FakeCaptureService();
    final repo = SwitchDiscoveryRepository(
      dbService: dbService,
      captureService: captureService,
    );
    final vm = SocketScoutViewModel(
      repository: repo,
      initialAdapters: const [
        NetworkAdapterInfo(name: 'eth0', displayName: 'eth0', ipAddress: '192.168.1.100'),
      ],
    );
    await vm.initFuture;
    addTearDown(() => vm.dispose());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ChangeNotifierProvider<SocketScoutViewModel>.value(
          value: vm,
          child: const SocketScoutScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Load demo data
    await tester.tap(find.text('Load Demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SW-CAT9200-RACK04.corp.local'), findsWidgets);

    // Right-click (secondary tap) on the table row containing the switch hostname
    final rowFinder = find.text('SW-CAT9200-RACK04.corp.local').last;
    final rowCenter = tester.getCenter(rowFinder);
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(rowCenter);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify context menu popped up with options
    expect(find.textContaining('Device Library'), findsWidgets);
    expect(find.textContaining('Copy Switch Hostname'), findsOneWidget);
    expect(find.textContaining('Copy Physical Port'), findsOneWidget);
    expect(find.textContaining('Copy All Switch Details'), findsOneWidget);

    // Tap "Add to Device Library..." / "Edit Device Identity..." in the context menu
    await tester.tap(find.byIcon(Icons.bookmark_add_outlined).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify EditDeviceDialog opened and is prefilled
    expect(find.text('FRIENDLY DEVICE NAME'), findsOneWidget);
    expect(find.text('MAC / CHASSIS ID'), findsOneWidget);
    expect(find.text('HARDWARE VENDOR'), findsOneWidget);
    expect(find.text('NOTES & DISCOVERY METADATA'), findsOneWidget);
    expect(find.text('Save to Device Library'), findsOneWidget);

    // Enter custom name
    final nameInput = find.widgetWithText(TextFormField, 'SW-CAT9200-RACK04.corp.local');
    expect(nameInput, findsOneWidget);
    await tester.enterText(nameInput, 'Custom Main Rack Switch');
    await tester.pump();

    // Tap Save to Device Library
    await tester.tap(find.text('Save to Device Library'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dialog dismissed and UI displays updated custom name with CUSTOM IDENTITY badge
    expect(find.text('Custom Main Rack Switch'), findsWidgets);
    expect(find.text('CUSTOM IDENTITY'), findsOneWidget);
  });
}
