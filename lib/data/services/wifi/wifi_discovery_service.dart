import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../domain/models/wifi_ap_discovery.dart';

typedef WifiProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

enum WifiScoutStatus {
  idle,
  scouting,
  error,
}

class WifiPollResult {
  const WifiPollResult({
    this.discovery,
    this.error,
    this.isPermissionBlocked = false,
    this.commandUsed = '',
  });

  final WifiApDiscovery? discovery;
  final String? error;
  final bool isPermissionBlocked;
  final String commandUsed;
}

/// Cross-platform OS Wi-Fi Access Point (BSSID & RF telemetry) discovery service.
///
/// Polls OS wireless telemetry without requiring monitor mode:
/// - Linux: `iw dev <iface> link`, `iw dev <iface> scan`, and `nmcli` fallback
/// - Windows: `netsh wlan show interfaces` and `netsh wlan show networks mode=bssid`
/// - macOS: `wdutil info` and `system_profiler SPAirPortDataType`
class WifiDiscoveryService {
  WifiDiscoveryService({
    WifiProcessRunner? processRunner,
    this.platformOverride,
  }) : _processRunner = processRunner ?? _defaultProcessRunner;

  final WifiProcessRunner _processRunner;
  final String? platformOverride;

  static Future<ProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments,
  ) {
    return Process.run(executable, arguments)
        .timeout(const Duration(seconds: 4));
  }

  final _discoveryController = StreamController<WifiApDiscovery>.broadcast();
  final _liveTelemetryController =
      StreamController<WifiApDiscovery>.broadcast();
  final _statusController = StreamController<WifiScoutStatus>.broadcast();

  /// Emits a new discovery on initial association or whenever BSSID changes (roaming).
  Stream<WifiApDiscovery> get onDiscovery => _discoveryController.stream;

  /// Emits live telemetry on every successful poll (for Hero card RSSI/Tx/Rx refresh).
  Stream<WifiApDiscovery> get onLiveTelemetry =>
      _liveTelemetryController.stream;

  Stream<WifiScoutStatus> get onStatusChanged => _statusController.stream;

  WifiScoutStatus _status = WifiScoutStatus.idle;
  WifiScoutStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  bool _isPermissionBlocked = false;
  bool get isPermissionBlocked => _isPermissionBlocked;

  int _pollsCompleted = 0;
  int get pollsCompleted => _pollsCompleted;

  String _generatedCommandLine = '';
  String get generatedCommandLine => _generatedCommandLine;

  Timer? _pollTimer;
  String? _activeInterface;
  String? _lastConnectedBssid;
  List<WifiNeighborAp> _cachedNeighbors = const [];
  DateTime? _lastNeighborScanAt;
  bool _isPolling = false;

  bool get _isLinux =>
      platformOverride != null ? platformOverride == 'linux' : Platform.isLinux;
  bool get _isWindows => platformOverride != null
      ? platformOverride == 'windows'
      : Platform.isWindows;
  bool get _isMacOS =>
      platformOverride != null ? platformOverride == 'macos' : Platform.isMacOS;

  Future<bool> startScouting({
    required String interfaceName,
    Duration pollInterval = const Duration(seconds: 3),
  }) async {
    await stopScouting();

    _activeInterface = interfaceName;
    _lastConnectedBssid = null;
    _cachedNeighbors = const [];
    _lastNeighborScanAt = null;
    _lastError = null;
    _isPermissionBlocked = false;
    _pollsCompleted = 0;
    _generatedCommandLine = _defaultCommandForPlatform(interfaceName);

    _setStatus(WifiScoutStatus.scouting);

    // Run immediate first poll
    await pollOnce(interfaceName: interfaceName, forceNeighborScan: true);

    if (_status == WifiScoutStatus.scouting) {
      _pollTimer = Timer.periodic(pollInterval, (_) {
        if (_activeInterface != null && !_isPolling) {
          pollOnce(interfaceName: _activeInterface!);
        }
      });
    }

    return _status == WifiScoutStatus.scouting;
  }

  Future<void> stopScouting() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _activeInterface = null;
    _isPolling = false;
    _setStatus(WifiScoutStatus.idle);
  }

  void _setStatus(WifiScoutStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  String _defaultCommandForPlatform(String iface) {
    if (_isLinux) return 'iw dev $iface link';
    if (_isWindows) return 'netsh wlan show interfaces';
    if (_isMacOS) return 'system_profiler SPAirPortDataType';
    return 'iw dev $iface link';
  }

  /// Performs a single OS telemetry poll and emits discovery/live events if associated.
  Future<WifiPollResult> pollOnce({
    required String interfaceName,
    bool forceNeighborScan = false,
  }) async {
    if (_isPolling) {
      return const WifiPollResult();
    }
    _isPolling = true;
    try {
      final result = await _collectPlatformTelemetry(
        interfaceName: interfaceName,
        shouldScanNeighbors: forceNeighborScan ||
            _lastNeighborScanAt == null ||
            DateTime.now().difference(_lastNeighborScanAt!) >=
                const Duration(seconds: 15),
      );

      _pollsCompleted++;
      if (result.commandUsed.isNotEmpty) {
        _generatedCommandLine = result.commandUsed;
      }

      _isPermissionBlocked = result.isPermissionBlocked;
      _lastError = result.error;

      if (result.discovery != null) {
        final disc = result.discovery!;
        if (!_liveTelemetryController.isClosed) {
          _liveTelemetryController.add(disc);
        }

        final currentBssid = disc.normalizedBssid;
        if (_lastConnectedBssid == null || _lastConnectedBssid != currentBssid) {
          _lastConnectedBssid = currentBssid;
          if (!_discoveryController.isClosed) {
            _discoveryController.add(disc);
          }
        }
      } else if (result.isPermissionBlocked) {
        _setStatus(WifiScoutStatus.error);
      }

      // Notify listeners of updated error / poll state
      if (!_statusController.isClosed) {
        _statusController.add(_status);
      }

      return result;
    } catch (e) {
      _lastError = 'Wi-Fi telemetry poll failed: $e';
      debugPrint(_lastError);
      return WifiPollResult(error: _lastError);
    } finally {
      _isPolling = false;
    }
  }

  Future<WifiPollResult> _collectPlatformTelemetry({
    required String interfaceName,
    required bool shouldScanNeighbors,
  }) async {
    if (_isLinux) {
      return _pollLinux(
        interfaceName: interfaceName,
        shouldScanNeighbors: shouldScanNeighbors,
      );
    }
    if (_isWindows) {
      return _pollWindows(
        interfaceName: interfaceName,
        shouldScanNeighbors: shouldScanNeighbors,
      );
    }
    if (_isMacOS) {
      return _pollMacOS(interfaceName: interfaceName);
    }
    return const WifiPollResult(
      error: 'Wi-Fi AP Scout is unsupported on this operating system.',
    );
  }

  Future<WifiPollResult> _pollLinux({
    required String interfaceName,
    required bool shouldScanNeighbors,
  }) async {
    final cmd = 'iw dev $interfaceName link';
    WifiApDiscovery? discovery;
    String rawOutput = '';

    try {
      final res = await _processRunner('iw', ['dev', interfaceName, 'link']);
      if (res.exitCode == 0) {
        rawOutput = res.stdout.toString();
        discovery = parseLinuxIwLink(
          rawOutput,
          interfaceName: interfaceName,
        );
      }
    } catch (_) {}

    // Enrich or fall back with nmcli
    try {
      final nmRes = await _processRunner('nmcli', [
        '-t',
        '-f',
        'ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY',
        'dev',
        'wifi',
        'list',
        'ifname',
        interfaceName,
      ]);
      if (nmRes.exitCode == 0) {
        final nmOut = nmRes.stdout.toString();
        final nmDisc = parseLinuxNmcliWifi(
          nmOut,
          interfaceName: interfaceName,
        );
        if (discovery == null && nmDisc != null) {
          discovery = nmDisc;
          rawOutput = nmOut;
        } else if (discovery != null && nmDisc != null) {
          discovery = discovery.copyWith(
            securityType: discovery.securityType ?? nmDisc.securityType,
            signalPercent: discovery.signalPercent ?? nmDisc.signalPercent,
            channel: discovery.channel ?? nmDisc.channel,
            neighbors: nmDisc.neighbors.isNotEmpty
                ? nmDisc.neighbors
                : discovery.neighbors,
          );
        }
      }
    } catch (_) {}

    // Periodic neighbor & Vendor-IE scan via `iw dev <iface> scan`
    if (discovery != null && shouldScanNeighbors) {
      try {
        final scanRes =
            await _processRunner('iw', ['dev', interfaceName, 'scan']);
        if (scanRes.exitCode == 0) {
          _lastNeighborScanAt = DateTime.now();
          final scanned = parseLinuxIwScan(
            scanRes.stdout.toString(),
            connectedBssid: discovery.normalizedBssid,
          );
          if (scanned.isNotEmpty) {
            _cachedNeighbors = scanned;
          }
        }
      } catch (_) {}
    }

    if (discovery != null) {
      final neighbors = _cachedNeighbors.isNotEmpty
          ? _cachedNeighbors
          : discovery.neighbors;
      // Extract enterprise AP hostname from matching connected neighbor if available
      String? apName = discovery.apHostname;
      if (apName == null) {
        for (final n in neighbors) {
          if (n.normalizedBssid == discovery.normalizedBssid &&
              n.apHostname != null &&
              n.apHostname!.isNotEmpty) {
            apName = n.apHostname;
            break;
          }
        }
      }
      discovery = discovery.copyWith(
        neighbors: neighbors,
        apHostname: apName,
      );
      return WifiPollResult(
        discovery: discovery,
        commandUsed: cmd,
      );
    }

    return WifiPollResult(
      error: rawOutput.toLowerCase().contains('not connected')
          ? 'Wi-Fi adapter $interfaceName is not associated with an Access Point.'
          : 'Waiting for Wi-Fi association on $interfaceName...',
      commandUsed: cmd,
    );
  }

  Future<WifiPollResult> _pollWindows({
    required String interfaceName,
    required bool shouldScanNeighbors,
  }) async {
    const cmd = 'netsh wlan show interfaces';
    try {
      final res = await _processRunner('netsh', ['wlan', 'show', 'interfaces']);
      final combined = '${res.stdout}\n${res.stderr}';
      final parsed = parseWindowsNetshInterfaces(
        combined,
        interfaceName: interfaceName,
      );

      if (parsed.discovery != null && shouldScanNeighbors) {
        try {
          final scanRes = await _processRunner(
            'netsh',
            ['wlan', 'show', 'networks', 'mode=bssid'],
          );
          if (scanRes.exitCode == 0) {
            _lastNeighborScanAt = DateTime.now();
            _cachedNeighbors = parseWindowsNetshNetworks(
              scanRes.stdout.toString(),
              connectedBssid: parsed.discovery!.normalizedBssid,
            );
          }
        } catch (_) {}
      }

      if (parsed.discovery != null && _cachedNeighbors.isNotEmpty) {
        return WifiPollResult(
          discovery: parsed.discovery!.copyWith(neighbors: _cachedNeighbors),
          commandUsed: cmd,
        );
      }

      return parsed;
    } catch (e) {
      return WifiPollResult(
        error: 'Failed to run netsh wlan: $e',
        commandUsed: cmd,
      );
    }
  }

  Future<WifiPollResult> _pollMacOS({
    required String interfaceName,
  }) async {
    // Try system_profiler first (does not require sudo), then wdutil info
    const spCmd = 'system_profiler SPAirPortDataType';
    try {
      final res =
          await _processRunner('system_profiler', ['SPAirPortDataType']);
      if (res.exitCode == 0) {
        final parsed = parseMacOsSystemProfiler(
          res.stdout.toString(),
          interfaceName: interfaceName,
        );
        if (parsed.discovery != null || parsed.isPermissionBlocked) {
          return parsed;
        }
      }
    } catch (_) {}

    try {
      final res = await _processRunner('wdutil', ['info']);
      if (res.exitCode == 0) {
        return parseMacOsWdutil(
          res.stdout.toString(),
          interfaceName: interfaceName,
        );
      }
    } catch (_) {}

    return const WifiPollResult(
      error: 'Unable to read macOS Wi-Fi telemetry.',
      commandUsed: spCmd,
    );
  }

  // ---------------------------------------------------------------------------
  // Static Cross-Platform Parsers (Unit-Testable)
  // ---------------------------------------------------------------------------

  /// Maps 802.11 center frequency in MHz to channel number (2.4 / 5 / 6 GHz).
  static int? frequencyToChannel(int? freqMhz) {
    if (freqMhz == null) return null;
    if (freqMhz == 2484) return 14;
    if (freqMhz >= 2412 && freqMhz <= 2472) {
      return ((freqMhz - 2407) ~/ 5);
    }
    if (freqMhz >= 5000 && freqMhz <= 5925) {
      return ((freqMhz - 5000) ~/ 5);
    }
    if (freqMhz >= 5955 && freqMhz <= 7115) {
      return ((freqMhz - 5950) ~/ 5);
    }
    return null;
  }

  static String? _inferWifiStandardFromBitrateLine(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('EHT-MCS')) return 'Wi-Fi 7 (802.11be)';
    if (upper.contains('HE-MCS')) return 'Wi-Fi 6 (802.11ax)';
    if (upper.contains('VHT-MCS')) return 'Wi-Fi 5 (802.11ac)';
    if (upper.contains('MCS ')) return 'Wi-Fi 4 (802.11n)';
    return null;
  }

  static int? _extractChannelWidthMhz(String text) {
    final m = RegExp(r'\b(20|40|80|160|320)\s*MHz\b', caseSensitive: false)
        .firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  /// Parses `iw dev <iface> link` output on Linux.
  static WifiApDiscovery? parseLinuxIwLink(
    String output, {
    required String interfaceName,
    DateTime? timestamp,
  }) {
    if (output.trim().isEmpty ||
        output.toLowerCase().contains('not connected')) {
      return null;
    }

    final bssidMatch = RegExp(
      r'Connected to\s+([0-9a-fA-F:]{17})',
      caseSensitive: false,
    ).firstMatch(output);
    if (bssidMatch == null) return null;

    final bssid = SharedDevice.normalizeMac(bssidMatch.group(1)!);
    String ssid = '<Hidden SSID>';
    int? freqMhz;
    int? rssiDbm;
    double? txMbps;
    double? rxMbps;
    int? widthMhz;
    String? standard;

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.startsWith('SSID:')) {
        final v = line.substring(5).trim();
        if (v.isNotEmpty) ssid = v;
      } else if (line.startsWith('freq:')) {
        final v = double.tryParse(line.substring(5).trim());
        if (v != null) freqMhz = v.round();
      } else if (line.startsWith('signal:')) {
        final m = RegExp(r'(-?\d+)\s*dBm').firstMatch(line);
        if (m != null) rssiDbm = int.tryParse(m.group(1)!);
      } else if (line.startsWith('tx bitrate:')) {
        final m = RegExp(r'([\d.]+)\s*MBit/s', caseSensitive: false)
            .firstMatch(line);
        if (m != null) txMbps = double.tryParse(m.group(1)!);
        widthMhz ??= _extractChannelWidthMhz(line);
        standard ??= _inferWifiStandardFromBitrateLine(line);
      } else if (line.startsWith('rx bitrate:')) {
        final m = RegExp(r'([\d.]+)\s*MBit/s', caseSensitive: false)
            .firstMatch(line);
        if (m != null) rxMbps = double.tryParse(m.group(1)!);
        widthMhz ??= _extractChannelWidthMhz(line);
        standard ??= _inferWifiStandardFromBitrateLine(line);
      }
    }

    final band = WifiBand.fromFrequencyMhz(freqMhz);
    final channel = frequencyToChannel(freqMhz);
    if (band == WifiBand.band6 && standard == 'Wi-Fi 6 (802.11ax)') {
      standard = 'Wi-Fi 6E (802.11ax)';
    }

    return WifiApDiscovery(
      timestamp: timestamp ?? DateTime.now(),
      interfaceName: interfaceName,
      ssid: ssid,
      bssid: bssid,
      band: band,
      channel: channel,
      frequencyMhz: freqMhz,
      channelWidthMhz: widthMhz,
      rssiDbm: rssiDbm,
      txRateMbps: txMbps,
      rxRateMbps: rxMbps,
      wifiStandard: standard,
      rawTelemetry: output.trim(),
    );
  }

  /// Parses `iw dev <iface> scan` output into a list of nearby APs and extracts
  /// optional enterprise AP Name vendor IEs when present.
  static List<WifiNeighborAp> parseLinuxIwScan(
    String output, {
    String? connectedBssid,
  }) {
    final neighbors = <WifiNeighborAp>[];
    final normalizedConnected =
        connectedBssid != null ? SharedDevice.normalizeMac(connectedBssid) : null;

    String? currentBssid;
    String? currentSsid;
    int? currentFreq;
    int? currentChannel;
    int? currentRssi;
    String? currentApName;
    String? currentSecurity;

    void flush() {
      final bssid = currentBssid;
      if (bssid == null) return;
      final norm = SharedDevice.normalizeMac(bssid);
      final band = currentFreq != null
          ? WifiBand.fromFrequencyMhz(currentFreq)
          : WifiBand.fromChannel(currentChannel);
      neighbors.add(WifiNeighborAp(
        bssid: norm,
        ssid: currentSsid,
        band: band,
        channel: currentChannel ?? frequencyToChannel(currentFreq),
        frequencyMhz: currentFreq,
        rssiDbm: currentRssi,
        apHostname: currentApName,
        securityType: currentSecurity,
        isConnected: normalizedConnected != null && norm == normalizedConnected,
      ));
    }

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final bssMatch = RegExp(r'^BSS\s+([0-9a-fA-F:]{17})', caseSensitive: false)
          .firstMatch(rawLine.trim());
      if (bssMatch != null) {
        flush();
        currentBssid = bssMatch.group(1);
        currentSsid = null;
        currentFreq = null;
        currentChannel = null;
        currentRssi = null;
        currentApName = null;
        currentSecurity = null;
        continue;
      }

      if (currentBssid == null) continue;
      final line = rawLine.trim();

      if (line.startsWith('freq:')) {
        final v = double.tryParse(line.substring(5).trim());
        if (v != null) currentFreq = v.round();
      } else if (line.startsWith('signal:')) {
        final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*dBm').firstMatch(line);
        if (m != null) currentRssi = double.tryParse(m.group(1)!)?.round();
      } else if (line.startsWith('SSID:')) {
        final v = line.substring(5).trim();
        currentSsid = v.isEmpty ? '<Hidden SSID>' : v;
      } else if (line.startsWith('DS Parameter set: channel')) {
        final m = RegExp(r'channel\s+(\d+)').firstMatch(line);
        if (m != null) currentChannel = int.tryParse(m.group(1)!);
      } else if (line.contains('RSN:')) {
        currentSecurity ??= 'WPA2/WPA3';
      } else if (line.contains('SAE')) {
        currentSecurity = 'WPA3 (SAE)';
      } else if (line.contains('802.1X')) {
        currentSecurity = 'WPA2/WPA3-Enterprise';
      } else if (line.contains('AP Name:')) {
        final idx = line.indexOf('AP Name:');
        final name = line.substring(idx + 8).trim();
        if (name.isNotEmpty) currentApName = name;
      }
    }
    flush();

    // Sort strongest signal first
    neighbors.sort((a, b) => (b.rssiDbm ?? -999).compareTo(a.rssiDbm ?? -999));
    return neighbors;
  }

  /// Parses `nmcli -t -f ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY dev wifi list`.
  static WifiApDiscovery? parseLinuxNmcliWifi(
    String output, {
    required String interfaceName,
    DateTime? timestamp,
  }) {
    final neighbors = <WifiNeighborAp>[];
    WifiApDiscovery? active;

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Split on unescaped colons (nmcli escapes MAC colons as `\:` )
      final fields = _splitNmcliEscapedLine(line);
      if (fields.length < 8) continue;

      final isActive = fields[0].toLowerCase() == 'yes';
      final ssid = fields[1].isEmpty ? '<Hidden SSID>' : fields[1];
      final bssidRaw = fields[2].replaceAll(r'\:', ':');
      if (!SharedDevice.isValidMac(bssidRaw)) continue;
      final bssid = SharedDevice.normalizeMac(bssidRaw);
      final channel = int.tryParse(fields[3]);
      final freqMatch = RegExp(r'(\d+)').firstMatch(fields[4]);
      final freqMhz =
          freqMatch != null ? int.tryParse(freqMatch.group(1)!) : null;
      final rateMatch = RegExp(r'([\d.]+)').firstMatch(fields[5]);
      final rateMbps =
          rateMatch != null ? double.tryParse(rateMatch.group(1)!) : null;
      final signalPct = int.tryParse(fields[6]);
      final security = fields[7].isEmpty ? 'Open' : fields[7];
      final band = freqMhz != null
          ? WifiBand.fromFrequencyMhz(freqMhz)
          : WifiBand.fromChannel(channel);
      final approxRssi =
          signalPct != null ? ((signalPct / 2).round() - 100) : null;

      neighbors.add(WifiNeighborAp(
        bssid: bssid,
        ssid: ssid,
        band: band,
        channel: channel,
        frequencyMhz: freqMhz,
        rssiDbm: approxRssi,
        signalPercent: signalPct,
        securityType: security,
        isConnected: isActive,
      ));

      if (isActive) {
        active = WifiApDiscovery(
          timestamp: timestamp ?? DateTime.now(),
          interfaceName: interfaceName,
          ssid: ssid,
          bssid: bssid,
          band: band,
          channel: channel,
          frequencyMhz: freqMhz,
          rssiDbm: approxRssi,
          signalPercent: signalPct,
          txRateMbps: rateMbps,
          securityType: security,
          rawTelemetry: output.trim(),
        );
      }
    }

    if (active != null) {
      neighbors.sort(
        (a, b) => (b.signalPercent ?? -1).compareTo(a.signalPercent ?? -1),
      );
      return active.copyWith(neighbors: neighbors);
    }
    return null;
  }

  static List<String> _splitNmcliEscapedLine(String line) {
    final result = <String>[];
    final buf = StringBuffer();
    bool escaped = false;
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (escaped) {
        buf.write(ch);
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == ':') {
        result.add(buf.toString());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    result.add(buf.toString());
    return result;
  }

  /// Parses Windows `netsh wlan show interfaces` output.
  static WifiPollResult parseWindowsNetshInterfaces(
    String output, {
    required String interfaceName,
    DateTime? timestamp,
  }) {
    const cmd = 'netsh wlan show interfaces';
    final lower = output.toLowerCase();

    if (lower.contains('location permission') ||
        lower.contains('location services') ||
        lower.contains('requires location') ||
        lower.contains('access is denied')) {
      return const WifiPollResult(
        error:
            'Windows Location Services permission is required to read Wi-Fi BSSID. '
            'Enable Settings → Privacy & security → Location → Let desktop apps access your location.',
        isPermissionBlocked: true,
        commandUsed: cmd,
      );
    }

    String? state;
    String? ssid;
    String? bssid;
    String? radioType;
    String? auth;
    String? bandStr;
    int? channel;
    double? rxRate;
    double? txRate;
    int? signalPct;

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final sepIdx = line.indexOf(':');
      if (sepIdx <= 0) continue;
      final key = line.substring(0, sepIdx).trim().toLowerCase();
      final val = line.substring(sepIdx + 1).trim();

      if (key == 'state') {
        state = val.toLowerCase();
      } else if (key == 'ssid') {
        ssid = val;
      } else if (key == 'bssid' || key == 'ap bssid') {
        bssid = val;
      } else if (key == 'radio type') {
        radioType = val;
      } else if (key == 'authentication') {
        auth = val;
      } else if (key == 'band') {
        bandStr = val;
      } else if (key == 'channel') {
        channel = int.tryParse(val);
      } else if (key.startsWith('receive rate')) {
        rxRate = double.tryParse(val);
      } else if (key.startsWith('transmit rate')) {
        txRate = double.tryParse(val);
      } else if (key == 'signal') {
        signalPct = int.tryParse(val.replaceAll('%', '').trim());
      }
    }

    if (state != null && state.contains('disconnected')) {
      return WifiPollResult(
        error: 'Wi-Fi adapter $interfaceName is disconnected.',
        commandUsed: cmd,
      );
    }

    if (bssid == null || !SharedDevice.isValidMac(bssid)) {
      return WifiPollResult(
        error: 'No active Wi-Fi BSSID detected on $interfaceName.',
        commandUsed: cmd,
      );
    }

    final band = bandStr != null
        ? WifiBand.fromString(bandStr)
        : WifiBand.fromChannel(channel);
    final approxRssi =
        signalPct != null ? ((signalPct / 2).round() - 100) : null;

    return WifiPollResult(
      discovery: WifiApDiscovery(
        timestamp: timestamp ?? DateTime.now(),
        interfaceName: interfaceName,
        ssid: (ssid == null || ssid.isEmpty) ? '<Hidden SSID>' : ssid,
        bssid: SharedDevice.normalizeMac(bssid),
        band: band,
        channel: channel,
        rssiDbm: approxRssi,
        signalPercent: signalPct,
        txRateMbps: txRate,
        rxRateMbps: rxRate,
        wifiStandard: radioType,
        securityType: auth,
        rawTelemetry: output.trim(),
      ),
      commandUsed: cmd,
    );
  }

  /// Parses Windows `netsh wlan show networks mode=bssid` output into neighbors.
  static List<WifiNeighborAp> parseWindowsNetshNetworks(
    String output, {
    String? connectedBssid,
  }) {
    final neighbors = <WifiNeighborAp>[];
    final normalizedConnected =
        connectedBssid != null ? SharedDevice.normalizeMac(connectedBssid) : null;

    String? currentSsid;
    String? currentAuth;
    String? currentBssid;
    int? currentSignalPct;
    int? currentChannel;
    String? currentBandStr;

    void flush() {
      final bssid = currentBssid;
      if (bssid == null || !SharedDevice.isValidMac(bssid)) {
        return;
      }
      final norm = SharedDevice.normalizeMac(bssid);
      final band = currentBandStr != null
          ? WifiBand.fromString(currentBandStr)
          : WifiBand.fromChannel(currentChannel);
      final sigPct = currentSignalPct;
      final approxRssi = sigPct != null ? ((sigPct / 2).round() - 100) : null;
      neighbors.add(WifiNeighborAp(
        bssid: norm,
        ssid: currentSsid,
        band: band,
        channel: currentChannel,
        rssiDbm: approxRssi,
        signalPercent: currentSignalPct,
        securityType: currentAuth,
        isConnected: normalizedConnected != null && norm == normalizedConnected,
      ));
    }

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final sepIdx = line.indexOf(':');
      if (sepIdx <= 0) continue;
      final key = line.substring(0, sepIdx).trim().toLowerCase();
      final val = line.substring(sepIdx + 1).trim();

      if (key.startsWith('ssid ')) {
        flush();
        currentBssid = null;
        currentSignalPct = null;
        currentChannel = null;
        currentBandStr = null;
        currentSsid = val.isEmpty ? '<Hidden SSID>' : val;
      } else if (key == 'authentication') {
        currentAuth = val;
      } else if (key.startsWith('bssid ')) {
        flush();
        currentBssid = val;
        currentSignalPct = null;
        currentChannel = null;
        currentBandStr = null;
      } else if (key == 'signal') {
        currentSignalPct = int.tryParse(val.replaceAll('%', '').trim());
      } else if (key == 'channel') {
        currentChannel = int.tryParse(val);
      } else if (key == 'band') {
        currentBandStr = val;
      }
    }
    flush();

    neighbors.sort(
      (a, b) => (b.signalPercent ?? -1).compareTo(a.signalPercent ?? -1),
    );
    return neighbors;
  }

  /// Parses macOS `wdutil info` output.
  static WifiPollResult parseMacOsWdutil(
    String output, {
    required String interfaceName,
    DateTime? timestamp,
  }) {
    const cmd = 'wdutil info';
    String? ssid;
    String? bssid;
    int? rssi;
    int? noise;
    double? txRate;
    String? security;
    String? phyMode;
    int? channel;
    WifiBand band = WifiBand.unknown;
    int? widthMhz;

    for (final rawLine in output.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final sepIdx = line.indexOf(':');
      if (sepIdx <= 0) continue;
      final key = line.substring(0, sepIdx).trim().toLowerCase();
      final val = line.substring(sepIdx + 1).trim();

      if (key == 'ssid') {
        ssid = val;
      } else if (key == 'bssid') {
        bssid = val;
      } else if (key == 'rssi') {
        final m = RegExp(r'(-?\d+)').firstMatch(val);
        if (m != null) rssi = int.tryParse(m.group(1)!);
      } else if (key == 'noise') {
        final m = RegExp(r'(-?\d+)').firstMatch(val);
        if (m != null) noise = int.tryParse(m.group(1)!);
      } else if (key == 'tx rate') {
        final m = RegExp(r'([\d.]+)').firstMatch(val);
        if (m != null) txRate = double.tryParse(m.group(1)!);
      } else if (key == 'security') {
        security = val;
      } else if (key == 'phy mode') {
        phyMode = val;
      } else if (key == 'channel') {
        // e.g. "5g36/80" or "6g37/160" or "2g6/20"
        final m =
            RegExp(r'^(2|5|6)g(\d+)(?:/(\d+))?', caseSensitive: false)
                .firstMatch(val);
        if (m != null) {
          final b = m.group(1)!;
          band = b == '2'
              ? WifiBand.band24
              : (b == '6' ? WifiBand.band6 : WifiBand.band5);
          channel = int.tryParse(m.group(2)!);
          if (m.group(3) != null) widthMhz = int.tryParse(m.group(3)!);
        } else {
          final chM = RegExp(r'(\d+)').firstMatch(val);
          if (chM != null) channel = int.tryParse(chM.group(1)!);
        }
      }
    }

    if ((bssid != null && bssid.toLowerCase().contains('redacted')) ||
        (ssid != null && ssid.toLowerCase().contains('redacted'))) {
      return const WifiPollResult(
        error:
            'macOS redacted Wi-Fi SSID/BSSID. Enable Location Services for Socket Scout in '
            'System Settings → Privacy & Security → Location Services.',
        isPermissionBlocked: true,
        commandUsed: cmd,
      );
    }

    if (bssid == null || !SharedDevice.isValidMac(bssid)) {
      return WifiPollResult(
        error: 'No active Wi-Fi BSSID reported by wdutil on $interfaceName.',
        commandUsed: cmd,
      );
    }

    return WifiPollResult(
      discovery: WifiApDiscovery(
        timestamp: timestamp ?? DateTime.now(),
        interfaceName: interfaceName,
        ssid: (ssid == null || ssid.isEmpty) ? '<Hidden SSID>' : ssid,
        bssid: SharedDevice.normalizeMac(bssid),
        band: band == WifiBand.unknown ? WifiBand.fromChannel(channel) : band,
        channel: channel,
        channelWidthMhz: widthMhz,
        rssiDbm: rssi,
        noiseDbm: noise,
        snrDb: (rssi != null && noise != null) ? (rssi - noise) : null,
        txRateMbps: txRate,
        wifiStandard: phyMode,
        securityType: security,
        rawTelemetry: output.trim(),
      ),
      commandUsed: cmd,
    );
  }

  /// Parses macOS `system_profiler SPAirPortDataType` output.
  static WifiPollResult parseMacOsSystemProfiler(
    String output, {
    required String interfaceName,
    DateTime? timestamp,
  }) {
    const cmd = 'system_profiler SPAirPortDataType';
    final lines = output.split(RegExp(r'\r?\n'));

    bool inCurrentNetwork = false;
    String? ssid;
    String? bssid;
    String? phyMode;
    String? security;
    int? channel;
    WifiBand band = WifiBand.unknown;
    int? widthMhz;
    int? rssi;
    int? noise;
    double? txRate;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.startsWith('Current Network Information:')) {
        inCurrentNetwork = true;
        continue;
      }
      if (!inCurrentNetwork) continue;
      if (line.startsWith('Other Local Wi-Fi Networks:') ||
          line.startsWith('awdl0:')) {
        break;
      }

      if (ssid == null && line.endsWith(':') && !line.contains(': ')) {
        ssid = line.substring(0, line.length - 1).trim();
        continue;
      }

      final sepIdx = line.indexOf(':');
      if (sepIdx <= 0) continue;
      final key = line.substring(0, sepIdx).trim().toLowerCase();
      final val = line.substring(sepIdx + 1).trim();

      if (key == 'bssid') {
        bssid = val;
      } else if (key == 'phy mode') {
        phyMode = val;
      } else if (key == 'security') {
        security = val;
      } else if (key == 'channel') {
        // e.g. "36 (5GHz, 80MHz)"
        final chM = RegExp(r'^(\d+)').firstMatch(val);
        if (chM != null) channel = int.tryParse(chM.group(1)!);
        band = WifiBand.fromString(val);
        widthMhz = _extractChannelWidthMhz(val);
      } else if (key == 'signal / noise') {
        // e.g. "-54 dBm / -92 dBm"
        final matches = RegExp(r'(-?\d+)\s*dBm').allMatches(val).toList();
        if (matches.isNotEmpty) rssi = int.tryParse(matches[0].group(1)!);
        if (matches.length >= 2) noise = int.tryParse(matches[1].group(1)!);
      } else if (key == 'transmit rate') {
        txRate = double.tryParse(val);
      }
    }

    if ((bssid != null && bssid.toLowerCase().contains('redacted')) ||
        (ssid != null && ssid.toLowerCase().contains('redacted'))) {
      return const WifiPollResult(
        error:
            'macOS redacted Wi-Fi SSID/BSSID. Enable Location Services for Socket Scout in '
            'System Settings → Privacy & Security → Location Services.',
        isPermissionBlocked: true,
        commandUsed: cmd,
      );
    }

    if (bssid == null || !SharedDevice.isValidMac(bssid)) {
      return WifiPollResult(
        error: 'No active Wi-Fi association found on $interfaceName.',
        commandUsed: cmd,
      );
    }

    return WifiPollResult(
      discovery: WifiApDiscovery(
        timestamp: timestamp ?? DateTime.now(),
        interfaceName: interfaceName,
        ssid: (ssid == null || ssid.isEmpty) ? '<Hidden SSID>' : ssid,
        bssid: SharedDevice.normalizeMac(bssid),
        band: band == WifiBand.unknown ? WifiBand.fromChannel(channel) : band,
        channel: channel,
        channelWidthMhz: widthMhz,
        rssiDbm: rssi,
        noiseDbm: noise,
        snrDb: (rssi != null && noise != null) ? (rssi - noise) : null,
        txRateMbps: txRate,
        wifiStandard: phyMode,
        securityType: security,
        rawTelemetry: output.trim(),
      ),
      commandUsed: cmd,
    );
  }

  void dispose() {
    _pollTimer?.cancel();
    _discoveryController.close();
    _liveTelemetryController.close();
    _statusController.close();
  }
}
