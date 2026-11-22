import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../domain/models/discovery_filter.dart';
import '../../../domain/models/switch_port_discovery.dart';
import '../../../domain/models/wifi_ap_discovery.dart';
import '../services/capture/capture_service.dart';
import '../services/database/switch_database_service.dart';
import '../services/generator/demo_l2_generator.dart';
import '../services/generator/demo_wifi_generator.dart';
import '../services/wifi/wifi_discovery_service.dart';

class SwitchDiscoveryRepository {
  SwitchDiscoveryRepository({
    SwitchDatabaseService? dbService,
    CaptureService? captureService,
    WifiDiscoveryService? wifiService,
    SharedDeviceDatabase? sharedDb,
  })  : _dbService = dbService ?? SwitchDatabaseService(),
        _captureService = captureService ?? CaptureService(),
        _wifiService = wifiService ?? WifiDiscoveryService(),
        _sharedDb = sharedDb ?? SharedDeviceDatabase.instance {
    _captureSub = _captureService.onDiscovery.listen(_handleDiscovery);
    _wifiSub = _wifiService.onDiscovery.listen(_handleWifiDiscovery);
    _wifiLiveSub = _wifiService.onLiveTelemetry.listen(_handleWifiLiveTelemetry);
  }

  final SwitchDatabaseService _dbService;
  final CaptureService _captureService;
  final WifiDiscoveryService _wifiService;
  final SharedDeviceDatabase _sharedDb;
  StreamSubscription<SwitchPortDiscovery>? _captureSub;
  StreamSubscription<WifiApDiscovery>? _wifiSub;
  StreamSubscription<WifiApDiscovery>? _wifiLiveSub;

  final _discoveryStreamController = StreamController<SwitchPortDiscovery>.broadcast();
  Stream<SwitchPortDiscovery> get onNewDiscovery => _discoveryStreamController.stream;

  final _wifiDiscoveryStreamController = StreamController<WifiApDiscovery>.broadcast();
  Stream<WifiApDiscovery> get onNewWifiDiscovery => _wifiDiscoveryStreamController.stream;

  final _wifiLiveStreamController = StreamController<WifiApDiscovery>.broadcast();
  Stream<WifiApDiscovery> get onWifiLiveUpdate => _wifiLiveStreamController.stream;

  final List<SwitchPortDiscovery> _inMemoryDiscoveries = [];
  List<SwitchPortDiscovery> get inMemoryDiscoveries => List.unmodifiable(_inMemoryDiscoveries);

  SwitchPortDiscovery? _latestDiscovery;
  SwitchPortDiscovery? get latestDiscovery => _latestDiscovery;

  final List<WifiApDiscovery> _inMemoryWifiDiscoveries = [];
  List<WifiApDiscovery> get inMemoryWifiDiscoveries =>
      List.unmodifiable(_inMemoryWifiDiscoveries);

  WifiApDiscovery? _latestWifiDiscovery;
  WifiApDiscovery? get latestWifiDiscovery => _latestWifiDiscovery;

  CaptureService get captureService => _captureService;
  WifiDiscoveryService get wifiService => _wifiService;
  SwitchDatabaseService get dbService => _dbService;
  SharedDeviceDatabase get sharedDb => _sharedDb;

  Future<void> init({String? dbPath, String? sharedDbPath}) async {
    await _dbService.init(customPath: dbPath);
    try {
      if (!_sharedDb.isInitialized) {
        await _sharedDb.init(dbPath: sharedDbPath);
      }
    } catch (e) {
      debugPrint('SwitchDiscoveryRepository: sharedDb init warning: $e');
    }
    _reloadRecent();
    _syncAllExistingToSharedDatabase();
  }

  void _reloadRecent() {
    _inMemoryDiscoveries.clear();
    final recents = _dbService.getDiscoveries(limit: 500);
    _inMemoryDiscoveries.addAll(recents);
    if (_inMemoryDiscoveries.isNotEmpty) {
      _latestDiscovery = _inMemoryDiscoveries.first;
    }

    _inMemoryWifiDiscoveries.clear();
    final recentWifi = _dbService.getWifiDiscoveries(limit: 500);
    _inMemoryWifiDiscoveries.addAll(recentWifi);
    if (_inMemoryWifiDiscoveries.isNotEmpty) {
      _latestWifiDiscovery = _inMemoryWifiDiscoveries.first;
    }
  }

  void _handleDiscovery(SwitchPortDiscovery discovery, {bool isDemo = false}) {
    final effectiveIsDemo = isDemo || discovery.isDemo;
    final toSave = discovery.copyWith(isDemo: effectiveIsDemo);

    final insertedId = _dbService.insertDiscovery(toSave);
    final saved = toSave.copyWith(id: insertedId > 0 ? insertedId : null);

    // Demo data is strictly ignored and never synced to the Shared Device Database.
    if (!effectiveIsDemo) {
      _syncToSharedDatabase(saved);
    }

    _inMemoryDiscoveries.insert(0, saved);
    _latestDiscovery = saved;
    _discoveryStreamController.add(saved);
  }

  /// Synchronizes a discovered switch into the Network Suite Shared Device Database
  /// (shared_devices.db) marked with deviceType: 'switch'.
  ///
  /// This enables companion applications such as Net Route Scout to automatically
  /// identify the node as an active network switch, display switch topology icons,
  /// and map connected host ports.
  void _syncToSharedDatabase(SwitchPortDiscovery discovery) {
    // Explicit guard: Demo data is strictly ignored and must not touch the shared database.
    if (discovery.isDemo) {
      return;
    }

    if (!_sharedDb.isInitialized) {
      return;
    }

    final rawMac = discovery.effectiveMacAddress;
    if (rawMac == null || !SharedDevice.isValidMac(rawMac)) {
      return;
    }

    final normalizedMac = SharedDevice.normalizeMac(rawMac);

    // 1. Resolve vendor via OUI or switch model heuristics
    String? vendor;
    try {
      vendor = OuiLookup.lookupVendor(normalizedMac);
    } catch (_) {}

    if (vendor == null || vendor.isEmpty || vendor.toLowerCase().contains('unknown')) {
      final modelLower = discovery.switchModel.toLowerCase();
      if (modelLower.contains('cisco')) {
        vendor = 'Cisco Systems, Inc.';
      } else if (modelLower.contains('netgear')) {
        vendor = 'Netgear Inc.';
      } else if (modelLower.contains('aruba') || modelLower.contains('procurve')) {
        vendor = 'Aruba / HPE';
      } else if (modelLower.contains('juniper')) {
        vendor = 'Juniper Networks, Inc.';
      } else if (modelLower.contains('mikrotik')) {
        vendor = 'MikroTik';
      } else if (discovery.protocol == DiscoveryProtocol.cdp) {
        vendor = 'Cisco Systems, Inc.';
      }
    }

    // 2. Build structured informative notes for Route Scout and Network Suite apps
    final notesParts = <String>[];
    if (discovery.managementIp != null && discovery.managementIp!.trim().isNotEmpty) {
      notesParts.add('Mgmt IP: ${discovery.managementIp!.trim()}');
    }
    if (discovery.portId.trim().isNotEmpty && !discovery.portId.toLowerCase().startsWith('unknown')) {
      final portDesc = (discovery.portDescription != null && discovery.portDescription!.trim().isNotEmpty)
          ? ' (${discovery.portDescription!.trim()})'
          : '';
      notesParts.add('Port: ${discovery.portId.trim()}$portDesc');
    }
    if (discovery.vlanId != null) {
      notesParts.add('VLAN: ${discovery.vlanId}');
    }
    if (discovery.switchModel.trim().isNotEmpty &&
        discovery.switchModel != 'Unknown Model' &&
        !discovery.switchModel.toLowerCase().startsWith('unknown')) {
      notesParts.add('Model: ${discovery.switchModel.trim()}');
    }
    notesParts.add('Via: ${discovery.protocol.label}');
    final notes = notesParts.join(' | ');

    // 3. Upsert device into SharedDeviceDatabase
    try {
      final existing = _sharedDb.getDeviceByMac(normalizedMac);
      final rawHostname = discovery.switchHostname.trim();
      final hasRealHostname = rawHostname.isNotEmpty &&
          !rawHostname.toLowerCase().startsWith('unknown');

      // Preserve existing custom name configured by user, if any
      final devName = (existing != null && existing.hasCustomName)
          ? existing.name
          : (hasRealHostname ? rawHostname : (existing?.name ?? 'Switch $normalizedMac'));

      final devVendor = (existing?.vendor != null && existing!.vendor!.isNotEmpty)
          ? existing.vendor
          : vendor;

      final device = SharedDevice(
        macAddress: normalizedMac,
        name: devName,
        vendor: devVendor,
        deviceType: 'switch', // Explicitly stored as switch for Net Route Scout
        notes: notes,
        sourceApp: 'socket_scout',
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _sharedDb.upsertDevice(device);
    } catch (e) {
      debugPrint('SwitchDiscoveryRepository: shared DB upsert error: $e');
    }
  }

  /// Synchronizes all existing historical discoveries into the shared database.
  void _syncAllExistingToSharedDatabase() {
    for (final discovery in _inMemoryDiscoveries) {
      if (!discovery.isDemo) {
        _syncToSharedDatabase(discovery);
      }
    }
    for (final wifi in _inMemoryWifiDiscoveries) {
      if (!wifi.isDemo) {
        _syncWifiToSharedDatabase(wifi);
      }
    }
  }

  /// Records a new Wi-Fi AP association or roaming event.
  void recordWifiDiscovery(WifiApDiscovery discovery, {bool isDemo = false}) {
    _handleWifiDiscovery(discovery, isDemo: isDemo);
  }

  void _handleWifiDiscovery(WifiApDiscovery discovery, {bool isDemo = false}) {
    final effectiveIsDemo = isDemo || discovery.isDemo;
    final toSave = discovery.copyWith(isDemo: effectiveIsDemo);

    final insertedId = _dbService.insertWifiDiscovery(toSave);
    final saved = toSave.copyWith(id: insertedId > 0 ? insertedId : null);

    // Demo data is strictly ignored and never synced to the Shared Device Database.
    if (!effectiveIsDemo) {
      _syncWifiToSharedDatabase(saved);
    }

    _inMemoryWifiDiscoveries.insert(0, saved);
    _latestWifiDiscovery = saved;
    if (!_wifiDiscoveryStreamController.isClosed) {
      _wifiDiscoveryStreamController.add(saved);
    }
  }

  void _handleWifiLiveTelemetry(WifiApDiscovery telemetry) {
    if (_latestWifiDiscovery != null &&
        _latestWifiDiscovery!.normalizedBssid == telemetry.normalizedBssid) {
      final updated = telemetry.copyWith(
        id: _latestWifiDiscovery!.id,
        isDemo: _latestWifiDiscovery!.isDemo,
      );
      _latestWifiDiscovery = updated;
      if (_inMemoryWifiDiscoveries.isNotEmpty &&
          _inMemoryWifiDiscoveries.first.normalizedBssid ==
              telemetry.normalizedBssid) {
        _inMemoryWifiDiscoveries[0] = updated;
      }
      if (!_wifiLiveStreamController.isClosed) {
        _wifiLiveStreamController.add(updated);
      }
    }
  }

  /// Synchronizes a genuine Wi-Fi AP discovery into the Network Suite Shared Device Database
  /// (`shared_devices.db`) marked with `deviceType: 'ap'`.
  void _syncWifiToSharedDatabase(WifiApDiscovery discovery) {
    // Explicit guard: Demo data is strictly ignored and must not touch the shared database.
    if (discovery.isDemo) {
      return;
    }

    if (!_sharedDb.isInitialized) {
      return;
    }

    final rawMac = discovery.bssid;
    if (!SharedDevice.isValidMac(rawMac)) {
      return;
    }

    final normalizedMac = SharedDevice.normalizeMac(rawMac);
    final vendor = discovery.resolvedVendor;

    final notesParts = <String>[];
    if (discovery.ssid.trim().isNotEmpty) {
      notesParts.add('SSID: ${discovery.ssid.trim()}');
    }
    if (discovery.band != WifiBand.unknown) {
      notesParts.add('Band: ${discovery.band.label}');
    }
    if (discovery.channel != null) {
      notesParts.add('Ch: ${discovery.channel}');
    }
    if (discovery.securityType != null &&
        discovery.securityType!.trim().isNotEmpty) {
      notesParts.add('Security: ${discovery.securityType!.trim()}');
    }
    if (discovery.wifiStandard != null &&
        discovery.wifiStandard!.trim().isNotEmpty) {
      notesParts.add('PHY: ${discovery.wifiStandard!.trim()}');
    }
    notesParts.add('Via: Wi-Fi AP Scout');
    final notes = notesParts.join(' | ');

    try {
      final existing = _sharedDb.getDeviceByMac(normalizedMac);
      final apHost = discovery.apHostname?.trim();
      final hasApHost = apHost != null && apHost.isNotEmpty;
      final defaultName = hasApHost
          ? apHost
          : (discovery.ssid.trim().isNotEmpty &&
                  discovery.ssid != '<Hidden SSID>'
              ? 'AP ${discovery.ssid.trim()} ($normalizedMac)'
              : 'Access Point $normalizedMac');

      // Preserve any existing custom name configured by the user
      final devName = (existing != null && existing.hasCustomName)
          ? existing.name
          : defaultName;

      final devVendor =
          (existing?.vendor != null && existing!.vendor!.isNotEmpty)
              ? existing.vendor
              : vendor;

      final device = SharedDevice(
        macAddress: normalizedMac,
        name: devName,
        vendor: devVendor,
        deviceType: DeviceCategory.accessPoint.key, // 'ap'
        notes: notes,
        sourceApp: 'socket_scout',
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _sharedDb.upsertDevice(device);
    } catch (e) {
      debugPrint('SwitchDiscoveryRepository: Wi-Fi shared DB upsert error: $e');
    }
  }

  /// Retrieves a device from the shared database by MAC, if initialized and present.
  SharedDevice? getRegisteredSharedDevice(String rawMac) {
    if (!_sharedDb.isInitialized) return null;
    final normalized = SharedDevice.normalizeMac(rawMac);
    try {
      return _sharedDb.getDeviceByMac(normalized);
    } catch (_) {
      return null;
    }
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
        interfaceName: 'demo',
      );
      if (discovery != null) {
        _handleDiscovery(discovery.copyWith(isDemo: true), isDemo: true);
      }
    }
  }

  /// Injects built-in Wi-Fi AP demo presets for immediate verification without a live AP.
  void loadWifiDemoPresets({String interfaceName = 'demo-wlan0'}) {
    final presets = DemoWifiGenerator.presets(interfaceName: interfaceName);
    for (final preset in presets) {
      _handleWifiDiscovery(preset.copyWith(isDemo: true), isDemo: true);
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

  List<WifiApDiscovery> getFilteredWifi({DiscoveryFilter? filter}) {
    if (filter == null || !filter.isActive) {
      return List.unmodifiable(_inMemoryWifiDiscoveries);
    }
    return _inMemoryWifiDiscoveries
        .where((item) => filter.matchesWifi(item))
        .toList();
  }

  void clearWifiAll() {
    _dbService.clearWifiDiscoveries();
    _inMemoryWifiDiscoveries.clear();
    _latestWifiDiscovery = null;
  }

  void clearAll() {
    _dbService.clearAll();
    _inMemoryDiscoveries.clear();
    _latestDiscovery = null;
    _inMemoryWifiDiscoveries.clear();
    _latestWifiDiscovery = null;
  }

  void dispose() {
    _captureSub?.cancel();
    _wifiSub?.cancel();
    _wifiLiveSub?.cancel();
    _captureService.dispose();
    _wifiService.dispose();
    _dbService.close();
    _discoveryStreamController.close();
    _wifiDiscoveryStreamController.close();
    _wifiLiveStreamController.close();
  }
}
