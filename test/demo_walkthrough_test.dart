import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/capture/capture_service.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
import 'package:socket_scout/domain/models/network_adapter_info.dart';
import 'package:socket_scout/main.dart';
import 'package:socket_scout/ui/features/scout/view_models/socket_scout_view_model.dart';
import 'package:socket_scout/ui/theme/app_theme.dart';
import 'package:socket_scout/ui/widgets/guided_tour_overlay.dart';

void main() {
  late SwitchDatabaseService dbService;
  late SwitchDiscoveryRepository repository;
  late SocketScoutViewModel viewModel;

  setUp(() async {
    AppTheme.applyThemeMode('dark');
    await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
    dbService = SwitchDatabaseService()..initInMemory();
    repository = SwitchDiscoveryRepository(
      dbService: dbService,
      captureService: CaptureService(),
      sharedDb: SharedDeviceDatabase.instance,
    );
    viewModel = SocketScoutViewModel(
      repository: repository,
      initialAdapters: const [
        NetworkAdapterInfo.all,
        NetworkAdapterInfo(
          name: 'eth0',
          displayName: 'eth0',
          ipAddress: '192.168.1.100',
        ),
      ],
    );
    await viewModel.initFuture;
  });

  tearDown(() async {
    viewModel.dispose();
    AppTheme.applyThemeMode('dark');
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SocketScoutApp(
        viewModel: viewModel,
        database: SharedDeviceDatabase.instance,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Demo Walkthrough Spotlight & Auto-Clear', () {
    testWidgets(
      'Load Demo starts walkthrough, highlights Step 1, and toggles toolbar button to amber Exit Demo',
      (tester) async {
        await pumpApp(tester);

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.discoveries, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.byType(GuidedTourOverlay), findsOneWidget);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isTrue);
        expect(viewModel.discoveries.length, equals(5));
        expect(viewModel.selectedDiscovery, isNotNull);

        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
        expect(
          find.text('Zone 2: Physical Ethernet Interface Selector'),
          findsOneWidget,
        );
        expect(find.text('Exit Demo'), findsOneWidget);
        expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

        final stopIcon = tester.widget<Icon>(
          find.byIcon(Icons.stop_circle_outlined),
        );
        expect(stopIcon.color, AppTheme.warning);
      },
    );

    testWidgets(
      'Walkthrough steps 1..5 in order and Finish & Clear auto-clears demo discoveries',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(
          find.text('Zone 2: Physical Ethernet Interface Selector'),
          findsOneWidget,
        );

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);
        expect(
          find.text('Zone 3: Start Listening (LLDP / CDP)'),
          findsOneWidget,
        );

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 3 OF 5'), findsOneWidget);
        expect(find.text('Active Switch Port Summary Card'), findsOneWidget);

        // Clear selection to verify Step 4's onStepEnter auto-selects first discovery
        viewModel.selectDiscovery(null);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);
        expect(find.text('Captured Frame History Table'), findsOneWidget);
        expect(viewModel.selectedDiscovery, isNotNull);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 5 OF 5'), findsOneWidget);
        expect(find.text('TLV Attribute Inspector & Export'), findsOneWidget);
        expect(find.text('Finish & Clear'), findsOneWidget);

        // Verify Back navigation works from final step.
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Finish & Clear'), findsOneWidget);

        await tester.tap(find.text('Finish & Clear'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.discoveries, isEmpty);
        expect(viewModel.selectedDiscovery, isNull);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.text('Exit Demo'), findsNothing);
      },
    );

    testWidgets(
      'End Demo button and empty-state LOAD DEMO DATA respect walkthrough & auto-clear lifecycle',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('LOAD DEMO DATA'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isTrue);
        expect(viewModel.discoveries.length, equals(5));
        expect(find.text('End Demo'), findsOneWidget);

        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.discoveries, isEmpty);
        expect(find.text('LOAD DEMO DATA'), findsOneWidget);
      },
    );

    testWidgets(
      'Keyboard navigation supports ArrowRight, ArrowLeft, and Escape auto-clear',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.discoveries, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo walkthrough strictly isolates SharedDeviceDatabase without inserting devices',
      (tester) async {
        await pumpApp(tester);

        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);

        // Advance through every step and finish.
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
        }

        await tester.tap(find.text('Finish & Clear'));
        await tester.pumpAndSettle();
        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
      },
    );
  });
}
