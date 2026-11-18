import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;
import 'package:socket_scout/data/repositories/switch_discovery_repository.dart';
import 'package:socket_scout/data/services/capture/capture_service.dart';
import 'package:socket_scout/data/services/database/switch_database_service.dart';
import 'package:socket_scout/domain/models/network_adapter_info.dart';
import 'package:socket_scout/main.dart';
import 'package:socket_scout/ui/features/scout/view_models/socket_scout_view_model.dart';
import 'package:socket_scout/ui/theme/app_theme.dart';

void main() {
  tearDown(() async {
    AppTheme.applyThemeMode('dark');
    if (SharedDeviceDatabase.instance.isInitialized) {
      await SharedDeviceDatabase.instance.setThemeMode('dark');
    }
  });

  group('AppTheme Palette & SharedDeviceDatabase Persistence', () {
    test('AppTheme switches accurately between Dark and Light palettes', () {
      AppTheme.applyThemeMode('dark');
      expect(AppTheme.isDark, isTrue);
      expect(AppTheme.themeMode, 'dark');
      expect(AppTheme.scaffoldBg, const Color(0xFF141414));
      expect(AppTheme.surface, const Color(0xFF1E1E1E));
      expect(AppTheme.surfaceHigh, const Color(0xFF252526));
      expect(AppTheme.surfaceElevated, const Color(0xFF2D2D2D));
      expect(AppTheme.border, const Color(0xFF2C2C2C));
      expect(AppTheme.textPrimary, const Color(0xFFE0E0E0));
      expect(AppTheme.textSecondary, const Color(0xFF9E9E9E));
      expect(AppTheme.textMuted, const Color(0xFF6E6E6E));
      expect(AppTheme.accent, const Color(0xFF007ACC));
      expect(AppTheme.success, const Color(0xFF10B981));
      expect(AppTheme.error, const Color(0xFFEF4444));
      expect(AppTheme.warning, const Color(0xFFF59E0B));
      expect(AppTheme.info, const Color(0xFF3B82F6));

      AppTheme.applyThemeMode('light');
      expect(AppTheme.isDark, isFalse);
      expect(AppTheme.themeMode, 'light');
      expect(AppTheme.scaffoldBg, const Color(0xFFF3F4F6));
      expect(AppTheme.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.surfaceHigh, const Color(0xFFF9FAFB));
      expect(AppTheme.surfaceElevated, const Color(0xFFFFFFFF));
      expect(AppTheme.border, const Color(0xFFE5E7EB));
      expect(AppTheme.textPrimary, const Color(0xFF111827));
      expect(AppTheme.textSecondary, const Color(0xFF4B5563));
      expect(AppTheme.textMuted, const Color(0xFF6B7280));
      expect(AppTheme.accent, const Color(0xFF0284C7));
      expect(AppTheme.success, const Color(0xFF059669));
      expect(AppTheme.error, const Color(0xFFDC2626));
      expect(AppTheme.warning, const Color(0xFFD97706));
      expect(AppTheme.info, const Color(0xFF2563EB));
    });

    test(
      'lightTheme and darkTheme produce Material 3 ThemeData without mutating AppTheme.isDark',
      () {
        AppTheme.applyThemeMode('dark');
        final light = AppTheme.lightTheme();
        expect(AppTheme.isDark, isTrue);
        expect(light.brightness, Brightness.light);
        expect(light.scaffoldBackgroundColor, const Color(0xFFF3F4F6));

        AppTheme.applyThemeMode('light');
        final dark = AppTheme.darkTheme();
        expect(AppTheme.isDark, isFalse);
        expect(dark.brightness, Brightness.dark);
        expect(dark.scaffoldBackgroundColor, const Color(0xFF141414));
      },
    );

    test(
      'SharedDeviceDatabaseThemeExt persists theme mode across instances on disk',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'socket_scout_theme_test_',
        );
        try {
          final dbPath = p.join(tempDir.path, 'shared_devices.db');

          final dbWriter = SharedDeviceDatabase();
          await dbWriter.init(dbPath: dbPath);
          expect(await dbWriter.getThemeMode(), 'dark');

          await dbWriter.setThemeMode('light');
          expect(await dbWriter.getThemeMode(), 'light');

          final dbReader = SharedDeviceDatabase();
          await dbReader.init(dbPath: dbPath);
          expect(await dbReader.getThemeMode(), 'light');

          await dbWriter.setThemeMode('dark');
          expect(await dbReader.getThemeMode(), 'dark');
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  group('SocketScoutApp Light & Dark Mode Widget Rendering', () {
    late SwitchDatabaseService dbService;
    late SwitchDiscoveryRepository repository;
    late SocketScoutViewModel viewModel;

    setUp(() async {
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
    });

    testWidgets(
      'Starts cleanly in Light Mode and renders UI & Demo Overlay without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await SharedDeviceDatabase.instance.setThemeMode('light');
        AppTheme.applyThemeMode('light');

        await tester.pumpWidget(
          SocketScoutApp(
            viewModel: viewModel,
            database: SharedDeviceDatabase.instance,
          ),
        );
        await tester.pumpAndSettle();

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.themeMode, ThemeMode.light);

        final titleText = tester.widget<Text>(find.text('SOCKET SCOUT'));
        expect(titleText.style?.color, const Color(0xFF111827));

        // Verify demo walkthrough renders cleanly in Light Mode too.
        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);

        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();
        expect(viewModel.discoveries, isEmpty);
      },
    );

    testWidgets('Starts cleanly in Dark Mode with dark palette tokens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await SharedDeviceDatabase.instance.setThemeMode('dark');
      AppTheme.applyThemeMode('dark');

      await tester.pumpWidget(
        SocketScoutApp(
          viewModel: viewModel,
          database: SharedDeviceDatabase.instance,
        ),
      );
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(materialApp.themeMode, ThemeMode.dark);

      final titleText = tester.widget<Text>(find.text('SOCKET SCOUT'));
      expect(titleText.style?.color, const Color(0xFFE0E0E0));
    });

    testWidgets('Reacts live when theme mode changes via SharedDeviceDatabase', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await SharedDeviceDatabase.instance.setThemeMode('dark');
      AppTheme.applyThemeMode('dark');

      await tester.pumpWidget(
        SocketScoutApp(
          viewModel: viewModel,
          database: SharedDeviceDatabase.instance,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(
        tester.widget<Text>(find.text('SOCKET SCOUT')).style?.color,
        const Color(0xFFE0E0E0),
      );

      // Simulate Net-App-Launcher toggling theme mode to 'light'
      await SharedDeviceDatabase.instance.setThemeMode('light');
      await tester.pumpAndSettle();

      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(
        tester.widget<Text>(find.text('SOCKET SCOUT')).style?.color,
        const Color(0xFF111827),
      );
    });
  });
}
