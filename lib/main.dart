import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'data/repositories/switch_discovery_repository.dart';
import 'data/services/capture/capture_service.dart';
import 'data/services/database/switch_database_service.dart';
import 'ui/features/scout/view_models/socket_scout_view_model.dart';
import 'ui/features/scout/views/socket_scout_screen.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (!SharedDeviceDatabase.instance.isInitialized) {
      await SharedDeviceDatabase.instance.init();
    }
  } catch (e) {
    debugPrint('SharedDeviceDatabase init warning: $e');
  }

  final dbService = SwitchDatabaseService();
  final captureService = CaptureService();
  final repository = SwitchDiscoveryRepository(
    dbService: dbService,
    captureService: captureService,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => SocketScoutViewModel(repository: repository),
        ),
      ],
      child: const SocketScoutApp(),
    ),
  );
}

class SocketScoutApp extends StatelessWidget {
  const SocketScoutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Socket Scout - Switch Port Identifier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      home: const SocketScoutScreen(),
    );
  }
}
