import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
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
    SharedDeviceDatabase? sharedDb,
  })  : _dbService = dbService ?? SwitchDatabaseService(),
        _captureService = captureService ?? CaptureService(),
        _sharedDb = sharedDb ?? SharedDeviceDatabase.instance {
    _captureSub = _captureService.onDiscovery.listen(_handleDiscovery);
  }

  final SwitchDatabaseService _dbService;
  final CaptureService _captureService;
  final SharedDeviceDatabase _sharedDb;
  StreamSubscription<SwitchPortDiscovery>? _captureSub;

  final _discoveryStreamController = StreamController<SwitchPortDiscovery>.broadcast();
  Stream<SwitchPortDiscovery> get onNewDiscovery => _discoveryStreamController.stream;

  final List<SwitchPortDiscovery> _inMemoryDiscoveries = [];
  List<SwitchPortDiscovery> get inMemoryDiscoveries => List.unmodifiable(_inMemoryDiscoveries);

  SwitchPortDiscovery? _latestDiscovery;
  SwitchPortDiscovery? get latestDiscovery => _latestDiscovery;

  CaptureService get captureService => _captureService;
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
  }

  void _handleDiscovery(SwitchPortDiscovery discovery) {
    final insertedId = _dbService.insertDiscovery(discovery);
    final saved = discovery.copyWith(id: insertedId > 0 ? insertedId : null);

    _syncToSharedDatabase(saved);

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
      _syncToSharedDatabase(discovery);
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
