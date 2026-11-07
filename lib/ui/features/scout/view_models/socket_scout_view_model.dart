import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../../domain/models/discovery_filter.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../../domain/models/switch_port_discovery.dart';
import '../../../../data/repositories/switch_discovery_repository.dart';
import '../../../../data/services/capture/capture_service.dart';
import '../../../../data/services/export/export_service.dart';
import '../../../../data/services/network/network_adapter_service.dart';

class SocketScoutViewModel extends ChangeNotifier {
  SocketScoutViewModel({
    SwitchDiscoveryRepository? repository,
    List<NetworkAdapterInfo>? initialAdapters,
  }) : _repository = repository ?? SwitchDiscoveryRepository() {
    if (initialAdapters != null) {
      _adapters = List.from(initialAdapters);
      if (_adapters.isNotEmpty) {
        _selectedAdapter = _adapters.first;
      }
    }
    initFuture = _init(skipAdapters: initialAdapters != null);
  }

  late final Future<void> initFuture;
  final SwitchDiscoveryRepository _repository;
  StreamSubscription<SwitchPortDiscovery>? _discoverySub;
  StreamSubscription<CaptureStatus>? _statusSub;
  Timer? _elapsedTimer;
  bool _isDisposed = false;

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

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  SwitchPortDiscovery? get latestDiscovery => _repository.latestDiscovery;

  List<SwitchPortDiscovery> get discoveries =>
      _repository.getFiltered(filter: _filter);

  int get totalDiscoveriesCount => _repository.inMemoryDiscoveries.length;

  int get framesReceived => _repository.captureService.framesReceived;

  String get generatedCommandLine =>
      _repository.captureService.generatedCommandLine;

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

    _statusSub = _repository.captureService.onStatusChanged.listen((status) {
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

    if (_repository.inMemoryDiscoveries.isNotEmpty) {
      _selectedDiscovery = _repository.inMemoryDiscoveries.first;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAdapters() async {
    _adapters = await NetworkAdapterService.getAvailableAdapters();
    if (_adapters.isNotEmpty) {
      if (_selectedAdapter == null || !_adapters.contains(_selectedAdapter)) {
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
    _selectedAdapter = adapter;
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
    _repository.loadDemoPresets();
    if (_repository.latestDiscovery != null) {
      _selectedDiscovery = _repository.latestDiscovery;
    }
    notifyListeners();
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
    _repository.clearAll();
    _selectedDiscovery = null;
    notifyListeners();
  }

  String exportCsv() => ExportService.toCsv(discoveries);
  String exportJson() => ExportService.toJson(discoveries);
  String exportReport() => ExportService.toTextReport(discoveries);

  @override
  void dispose() {
    _isDisposed = true;
    _stopTimer();
    _discoverySub?.cancel();
    _statusSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
