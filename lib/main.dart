import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'data/repositories/switch_discovery_repository.dart';
import 'data/services/capture/capture_service.dart';
import 'data/services/database/switch_database_service.dart';
import 'domain/models/launch_adapter_config.dart';
import 'ui/features/scout/view_models/socket_scout_view_model.dart';
import 'ui/features/scout/views/socket_scout_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchAdapterConfig = LaunchAdapterConfig.fromArgs(args);

  try {
    if (!SharedDeviceDatabase.instance.isInitialized) {
      await SharedDeviceDatabase.instance.init();
    }
    final mode = await SharedDeviceDatabase.instance.getThemeMode();
    AppTheme.applyThemeMode(mode);
  } catch (e) {
    debugPrint('SharedDeviceDatabase init warning: $e');
  }

  runApp(SocketScoutApp(launchAdapterConfig: launchAdapterConfig));
}

class SocketScoutApp extends StatefulWidget {
  const SocketScoutApp({
    super.key,
    this.launchAdapterConfig,
    this.viewModel,
    this.database,
  });

  final LaunchAdapterConfig? launchAdapterConfig;
  final SocketScoutViewModel? viewModel;
  final SharedDeviceDatabase? database;

  @override
  State<SocketScoutApp> createState() => _SocketScoutAppState();
}

class _SocketScoutAppState extends State<SocketScoutApp> {
  late ThemeMode _themeMode;
  StreamSubscription<void>? _dbSubscription;
  Timer? _pollTimer;

  SharedDeviceDatabase get _db =>
      widget.database ?? SharedDeviceDatabase.instance;

  ThemeMode get _currentThemeMode =>
      AppTheme.isDark ? ThemeMode.dark : ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _themeMode = _currentThemeMode;
    _syncTheme();
    _dbSubscription = _db.onDatabaseChanged.listen((_) => _syncTheme());
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _syncTheme(),
      );
    }
  }

  Future<void> _syncTheme() async {
    try {
      final modeStr = await _db.getThemeMode();
      AppTheme.applyThemeMode(modeStr);
      final nextMode = _currentThemeMode;
      if (mounted && _themeMode != nextMode) {
        setState(() {
          _themeMode = nextMode;
        });
      }
    } catch (_) {
      // Ignore if shared database is unavailable during startup or tests.
    }
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Socket Scout - Switch Port Identifier',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const SocketScoutScreen(),
      ),
    );

    if (widget.viewModel != null) {
      return ChangeNotifierProvider<SocketScoutViewModel>.value(
        value: widget.viewModel!,
        child: app,
      );
    }

    return ChangeNotifierProvider<SocketScoutViewModel>(
      create: (_) {
        final dbService = SwitchDatabaseService();
        final captureService = CaptureService();
        final repository = SwitchDiscoveryRepository(
          dbService: dbService,
          captureService: captureService,
          sharedDb: _db,
        );
        return SocketScoutViewModel(
          repository: repository,
          initialAdapterConfig: widget.launchAdapterConfig,
        );
      },
      child: app,
    );
  }
}
