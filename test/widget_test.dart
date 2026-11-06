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

void main() {
  testWidgets('SocketScoutScreen renders 5-tier layout and empty state',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final dbService = SwitchDatabaseService();
    dbService.initInMemory();
    final captureService = CaptureService();
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
}
