import 'dart:async';
import 'dart:io';
import '../../../domain/models/discovery_filter.dart';
import '../../../domain/models/switch_port_discovery.dart';
import '../services/capture/capture_service.dart';
import '../services/database/switch_database_service.dart';
import '../services/generator/demo_l2_generator.dart';
import '../services/parser/pcap_binary_reader.dart';

class SwitchDiscoveryRepository {
  SwitchDiscoveryRepository({
    SwitchDatabaseService? dbService,
    CaptureService? captureService,
  })  : _dbService = dbService ?? SwitchDatabaseService(),
        _captureService = captureService ?? CaptureService() {
    _captureSub = _captureService.onDiscovery.listen(_handleDiscovery);
  }

  final SwitchDatabaseService _dbService;
  final CaptureService _captureService;
  StreamSubscription<SwitchPortDiscovery>? _captureSub;

  final _discoveryStreamController = StreamController<SwitchPortDiscovery>.broadcast();
  Stream<SwitchPortDiscovery> get onNewDiscovery => _discoveryStreamController.stream;

  final List<SwitchPortDiscovery> _inMemoryDiscoveries = [];
  List<SwitchPortDiscovery> get inMemoryDiscoveries => List.unmodifiable(_inMemoryDiscoveries);

  SwitchPortDiscovery? _latestDiscovery;
  SwitchPortDiscovery? get latestDiscovery => _latestDiscovery;

  CaptureService get captureService => _captureService;
  SwitchDatabaseService get dbService => _dbService;

  Future<void> init({String? dbPath}) async {
    await _dbService.init(customPath: dbPath);
    _reloadRecent();
  }

  void _reloadRecent() {
    _inMemoryDiscoveries.clear();
    final recents = _dbService.getDiscoveries(limit: 500);
    _inMemoryDiscoveries.addAll(recents);
    if (_inMemoryDiscoveries.isNotEmpty) {
      _latestDiscovery = _inMemoryDiscoveries.first;
    }
  }

  void _handleDiscovery(SwitchPortDiscovery discovery) {
    final insertedId = _dbService.insertDiscovery(discovery);
    final saved = discovery.copyWith(id: insertedId > 0 ? insertedId : null);

    _inMemoryDiscoveries.insert(0, saved);
    _latestDiscovery = saved;
    _discoveryStreamController.add(saved);
  }

  /// Injects built-in demo packets for immediate verification without a live switch.
  void loadDemoPresets() {
    final presets = [
      DemoL2Generator.ciscoCatalyst9200Cdp(),
      DemoL2Generator.ciscoCatalyst9200Lldp(),
      DemoL2Generator.netgearM4250Lldp(),
      DemoL2Generator.arubaCx6200Lldp(),
      DemoL2Generator.juniperEx4300Lldp(),
    ];

    for (final rawFrame in presets) {
      final discovery = CaptureService.dissectRawFrame(
        rawFrame,
        timestamp: DateTime.now(),
        interfaceName: 'eth0',
      );
      if (discovery != null) {
        _handleDiscovery(discovery);
      }
    }
  }

  /// Parses an imported PCAP or PCAPNG capture file.
  Future<int> importPcapFile(File file) async {
    final rawPackets = PcapBinaryReader.parseFile(file);
    int imported = 0;

    for (final pkt in rawPackets) {
      final discovery = CaptureService.dissectRawFrame(
        pkt.data,
        timestamp: pkt.timestamp,
        interfaceName: file.path.split(Platform.pathSeparator).last,
      );
      if (discovery != null) {
        _handleDiscovery(discovery);
        imported++;
      }
    }

    return imported;
  }

  List<SwitchPortDiscovery> getFiltered({DiscoveryFilter? filter}) {
    if (filter == null || !filter.isActive) {
      return List.unmodifiable(_inMemoryDiscoveries);
    }
    return _inMemoryDiscoveries.where((item) => filter.matches(item)).toList();
  }

  void clearAll() {
    _dbService.clearAll();
    _inMemoryDiscoveries.clear();
    _latestDiscovery = null;
  }

  void dispose() {
    _captureSub?.cancel();
    _captureService.dispose();
    _dbService.close();
    _discoveryStreamController.close();
  }
}
