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
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    expect(find.text('DEMO PRESETS'), findsOneWidget);

    // Click DEMO PRESETS to verify state updates
    await tester.tap(find.text('DEMO PRESETS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('SW-CAT9200-RACK04.corp.local'), findsWidgets);
    expect(find.text('GigabitEthernet1/0/14'), findsWidgets);
  });

  testWidgets('Center empty state displays active listening state and toggles in sync with top bar',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
}
