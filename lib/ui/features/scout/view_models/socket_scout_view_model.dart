import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../../domain/models/discovery_filter.dart';
import '../../../../domain/models/launch_adapter_config.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../../domain/models/switch_port_discovery.dart';
import '../../../../domain/models/wifi_ap_discovery.dart';
import '../../../../data/repositories/switch_discovery_repository.dart';
import '../../../../data/services/capture/capture_service.dart';
import '../../../../data/services/export/export_service.dart';
import '../../../../data/services/network/network_adapter_service.dart';
import '../../../../data/services/wifi/wifi_discovery_service.dart';

class SocketScoutViewModel extends ChangeNotifier {
  SocketScoutViewModel({
    SwitchDiscoveryRepository? repository,
    List<NetworkAdapterInfo>? initialAdapters,
    this.initialAdapterConfig,
    Future<List<NetworkAdapterInfo>> Function()? adapterProvider,
  })  : _repository = repository ?? SwitchDiscoveryRepository(),
        _adapterProvider =
            adapterProvider ?? NetworkAdapterService.getAvailableAdapters {
    if (initialAdapters != null) {
      _adapters = List.from(initialAdapters);
      if (_adapters.isNotEmpty) {
        _selectedAdapter =
            _applyInitialAdapterOverride(_adapters) ?? _adapters.first;
      }
    }
    initFuture = _init(skipAdapters: initialAdapters != null);
  }

  late final Future<void> initFuture;
  final SwitchDiscoveryRepository _repository;
  final LaunchAdapterConfig? initialAdapterConfig;
  final Future<List<NetworkAdapterInfo>> Function() _adapterProvider;
  bool _hasAppliedInitialAdapterOverride = false;
  bool _isDemoMode = false;
  StreamSubscription<SwitchPortDiscovery>? _discoverySub;
  StreamSubscription<CaptureStatus>? _statusSub;
  StreamSubscription<WifiApDiscovery>? _wifiDiscoverySub;
  StreamSubscription<WifiApDiscovery>? _wifiLiveSub;
  StreamSubscription<WifiScoutStatus>? _wifiStatusSub;
  Timer? _elapsedTimer;
  bool _isDisposed = false;

  bool get isDemoMode => _isDemoMode;

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  List<NetworkAdapterInfo> _adapters = [];
  List<NetworkAdapterInfo> get adapters => _adapters;

  NetworkAdapterInfo? _selectedAdapter;
  NetworkAdapterInfo? get selectedAdapter => _selectedAdapter;

  /// True when the currently selected network adapter is a Wi-Fi interface.
  bool get isWifiMode => _selectedAdapter?.isWifi ?? false;

  bool get isWifiPermissionBlocked =>
      isWifiMode && _repository.wifiService.isPermissionBlocked;

  bool _isListening = false;
  bool get isListening => _isListening;

  int _elapsedSeconds = 0;
  int get elapsedSeconds => _elapsedSeconds;

  String? _lastError;
  String? get lastError => _lastError;

  DiscoveryFilter _filter = const DiscoveryFilter();
  DiscoveryFilter get filter => _filter;

  SwitchPortDiscovery? _selectedDiscovery;
  SwitchPortDiscovery? get selectedDiscovery => _selectedDiscovery;

  WifiApDiscovery? _selectedWifiDiscovery;
  WifiApDiscovery? get selectedWifiDiscovery => _selectedWifiDiscovery;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  SwitchPortDiscovery? get latestDiscovery => _repository.latestDiscovery;

  WifiApDiscovery? get latestWifiDiscovery => _repository.latestWifiDiscovery;

  List<SwitchPortDiscovery> get discoveries =>
      _repository.getFiltered(filter: _filter);

  List<WifiApDiscovery> get wifiDiscoveries =>
      _repository.getFilteredWifi(filter: _filter);

  int get totalDiscoveriesCount => _repository.inMemoryDiscoveries.length;

  int get totalWifiDiscoveriesCount =>
      _repository.inMemoryWifiDiscoveries.length;

  int get framesReceived => _repository.captureService.framesReceived;

  int get wifiPollsCompleted => _repository.wifiService.pollsCompleted;

  String get generatedCommandLine => isWifiMode
      ? _repository.wifiService.generatedCommandLine
      : _repository.captureService.generatedCommandLine;

  Future<void> _init({bool skipAdapters = false}) async {
    _isLoading = true;
    notifyListeners();

    await _repository.init();
    if (!skipAdapters) {
      await refreshAdapters();
    }

    _discoverySub = _repository.onNewDiscovery.listen((discovery) {
      _selectedDiscovery ??= discovery;
      notifyListeners();
    });

    _wifiDiscoverySub = _repository.onNewWifiDiscovery.listen((discovery) {
      _selectedWifiDiscovery = discovery;
      notifyListeners();
    });

    _wifiLiveSub = _repository.onWifiLiveUpdate.listen((telemetry) {
      if (_selectedWifiDiscovery == null ||
          _selectedWifiDiscovery!.normalizedBssid ==
              telemetry.normalizedBssid) {
        _selectedWifiDiscovery = telemetry;
      }
      notifyListeners();
    });

    _statusSub = _repository.captureService.onStatusChanged.listen((status) {
      if (isWifiMode) return;
      final running = status == CaptureStatus.listening;
      if (running != _isListening) {
        _isListening = running;
        if (_isListening) {
          _startTimer();
        } else {
          _stopTimer();
        }
      }
      _lastError = _repository.captureService.lastError;
      notifyListeners();
    });

    _wifiStatusSub = _repository.wifiService.onStatusChanged.listen((status) {
      if (!isWifiMode) return;
      final running = status == WifiScoutStatus.scouting;
      if (running != _isListening) {
        _isListening = running;
        if (_isListening) {
          _startTimer();
        } else {
          _stopTimer();
        }
      }
      _lastError = _repository.wifiService.lastError;
      notifyListeners();
    });

    if (_repository.inMemoryDiscoveries.isNotEmpty) {
      _selectedDiscovery = _repository.inMemoryDiscoveries.first;
    }
    if (_repository.inMemoryWifiDiscoveries.isNotEmpty) {
      _selectedWifiDiscovery = _repository.inMemoryWifiDiscoveries.first;
    }

    _isLoading = false;
    notifyListeners();
  }

  NetworkAdapterInfo? _applyInitialAdapterOverride(
    List<NetworkAdapterInfo> adapters,
  ) {
    if (_hasAppliedInitialAdapterOverride) return null;
    _hasAppliedInitialAdapterOverride = true;
    return initialAdapterConfig?.matchAdapter(adapters);
  }

  Future<void> refreshAdapters() async {
    _adapters = await _adapterProvider();
    if (_isDisposed) return;
    if (_adapters.isNotEmpty) {
      final matched = _applyInitialAdapterOverride(_adapters);
      if (matched != null) {
        _selectedAdapter = matched;
      } else if (_selectedAdapter == null ||
          !_adapters.contains(_selectedAdapter)) {
        // Prefer first real adapter over 'any' if available
        if (_adapters.length > 1) {
          _selectedAdapter = _adapters[1];
        } else {
          _selectedAdapter = _adapters.first;
        }
      }
    }
    notifyListeners();
  }

  void selectAdapter(NetworkAdapterInfo? adapter) {
    if (adapter == null || _selectedAdapter == adapter) return;
    final wasListening = _isListening;
    if (wasListening) {
      unawaited(stopListening());
    }
    _selectedAdapter = adapter;
    _lastError = null;
    notifyListeners();
  }

  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  Future<void> startListening() async {
    if (_isListening) return;
    if (_selectedAdapter == null) return;
    _lastError = null;
    _elapsedSeconds = 0;
    notifyListeners();

    if (isWifiMode) {
      final success = await _repository.wifiService.startScouting(
        interfaceName: _selectedAdapter!.name,
      );
      if (!success) {
        _lastError = _repository.wifiService.lastError;
        _isListening = false;
      } else {
        _isListening = true;
        _lastError = _repository.wifiService.lastError;
        _startTimer();
      }
      notifyListeners();
      return;
    }

    final success = await _repository.captureService.startCapture(
      interfaceName: _selectedAdapter!.name,
    );

    if (!success) {
      _lastError = _repository.captureService.lastError;
      _isListening = false;
    } else {
      _isListening = true;
      _startTimer();
    }
    notifyListeners();
  }

  Future<void> stopListening() async {
    await _repository.captureService.stopCapture();
    await _repository.wifiService.stopScouting();
    _isListening = false;
    _stopTimer();
    notifyListeners();
  }

  void _startTimer() {
    _stopTimer();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void _stopTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void loadDemoData() {
    if (isWifiMode) {
      _repository.loadWifiDemoPresets(
        interfaceName: _selectedAdapter?.name ?? 'demo-wlan0',
      );
      if (_repository.latestWifiDiscovery != null) {
        _selectedWifiDiscovery = _repository.latestWifiDiscovery;
      }
      notifyListeners();
      return;
    }

    _repository.loadDemoPresets();
    if (_repository.latestDiscovery != null) {
      _selectedDiscovery = _repository.latestDiscovery;
    }
    notifyListeners();
  }

  /// Starts demo mode by loading in-memory demo packets/AP presets and activating the guided tour.
  void startDemoWalkthrough() {
    if (_isListening) return;
    _isDemoMode = true;
    loadDemoData();
  }

  /// Ends demo mode and automatically clears demo discovery data.
  void endDemoWalkthrough() {
    _isDemoMode = false;
    clearAll();
  }

  Future<int> importPcapFile(File file) async {
    final count = await _repository.importPcapFile(file);
    if (_repository.latestDiscovery != null) {
      _selectedDiscovery = _repository.latestDiscovery;
    }
    notifyListeners();
    return count;
  }

  void selectDiscovery(SwitchPortDiscovery? discovery) {
    _selectedDiscovery = discovery;
    notifyListeners();
  }

  void selectWifiDiscovery(WifiApDiscovery? discovery) {
    _selectedWifiDiscovery = discovery;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _filter = _filter.copyWith(searchQuery: query);
    notifyListeners();
  }

  void setProtocolFilter(DiscoveryProtocol? protocol) {
    if (protocol == null) {
      _filter = _filter.copyWith(clearProtocol: true);
    } else {
      _filter = _filter.copyWith(protocol: protocol);
    }
    notifyListeners();
  }

  void setWifiBandFilter(WifiBand? band) {
    if (band == null) {
      _filter = _filter.copyWith(clearWifiBand: true);
    } else {
      _filter = _filter.copyWith(wifiBand: band);
    }
    notifyListeners();
  }

  void setVlanFilter(int? vlanId) {
    if (vlanId == null) {
      _filter = _filter.copyWith(clearVlan: true);
    } else {
      _filter = _filter.copyWith(vlanId: vlanId);
    }
    notifyListeners();
  }

  void clearFilters() {
    _filter = const DiscoveryFilter();
    notifyListeners();
  }

  void clearAll() {
    _isDemoMode = false;
    if (isWifiMode) {
      _repository.clearWifiAll();
      _selectedWifiDiscovery = null;
    } else {
      _repository.clearAll();
      _selectedDiscovery = null;
      _selectedWifiDiscovery = null;
    }
    notifyListeners();
  }

  /// Alias for clearing all captured/demo frames or Wi-Fi roaming history.
  void clearFrames() => clearAll();

  /// Notifies UI when a device record or custom name is updated in the Shared Device Library.
  void notifyDeviceUpdated() {
    notifyListeners();
  }

  String exportCsv() => isWifiMode
      ? ExportService.wifiToCsv(wifiDiscoveries)
      : ExportService.toCsv(discoveries);

  String exportJson() => isWifiMode
      ? ExportService.wifiToJson(wifiDiscoveries)
      : ExportService.toJson(discoveries);

  String exportReport() => isWifiMode
      ? ExportService.wifiToTextReport(wifiDiscoveries)
      : ExportService.toTextReport(discoveries);

  @override
  void dispose() {
    _isDisposed = true;
    _stopTimer();
    _discoverySub?.cancel();
    _statusSub?.cancel();
    _wifiDiscoverySub?.cancel();
    _wifiLiveSub?.cancel();
    _wifiStatusSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
