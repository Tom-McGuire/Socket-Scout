import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../domain/models/switch_port_discovery.dart';
import '../parser/cdp_dissector.dart';
import '../parser/lldp_dissector.dart';
import '../parser/pcap_binary_reader.dart';

enum CaptureStatus {
  idle,
  starting,
  listening,
  stopped,
  error,
}

class CaptureService {
  Process? _process;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  final StreamingPcapParser _pcapParser = StreamingPcapParser();

  final _discoveryController = StreamController<SwitchPortDiscovery>.broadcast();
  Stream<SwitchPortDiscovery> get onDiscovery => _discoveryController.stream;

  final _statusController = StreamController<CaptureStatus>.broadcast();
  Stream<CaptureStatus> get onStatusChanged => _statusController.stream;

  CaptureStatus _status = CaptureStatus.idle;
  CaptureStatus get status => _status;

  String? _lastError;
  String? get lastError => _lastError;

  String _generatedCommandLine = '';
  String get generatedCommandLine => _generatedCommandLine;

  int _framesReceived = 0;
  int get framesReceived => _framesReceived;

  /// Locates capture executable (tcpdump, tshark, dumpcap).
  static Future<String?> findCaptureBinary() async {
    if (Platform.isWindows) {
      const candidates = [
        r'C:\Program Files\Wireshark\dumpcap.exe',
        r'C:\Program Files\Wireshark\tshark.exe',
        r'C:\Program Files (x86)\Wireshark\dumpcap.exe',
        r'C:\Program Files (x86)\Wireshark\tshark.exe',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      try {
        final res = await Process.run('where', ['dumpcap']);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          return res.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first;
        }
      } catch (_) {}
    } else {
      const candidates = [
        '/usr/bin/tcpdump',
        '/usr/sbin/tcpdump',
        '/usr/bin/dumpcap',
        '/usr/bin/tshark',
        '/usr/local/bin/tcpdump',
        '/usr/local/bin/dumpcap',
        '/usr/local/bin/tshark',
      ];
      for (final p in candidates) {
        if (File(p).existsSync()) return p;
      }
      try {
        final res = await Process.run('which', ['tcpdump']);
        if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
          return res.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Builds the BPF filter and execution arguments.
  static String get bpfFilter =>
      'ether proto 0x88cc or (ether[12:2] <= 1500 and ether[20:2] == 0x2000)';

  /// Starts listening for Layer 2 multicast frames on the specified interface.
  Future<bool> startCapture({
    required String interfaceName,
  }) async {
    await stopCapture();

    _setStatus(CaptureStatus.starting);
    _lastError = null;
    _framesReceived = 0;
    _pcapParser.reset();

    final binary = await findCaptureBinary();
    if (binary == null) {
      _lastError =
          'No packet capture binary (tcpdump, dumpcap, or tshark) found on system.';
      _setStatus(CaptureStatus.error);
      return false;
    }

    final isTcpdump = binary.toLowerCase().contains('tcpdump');
    final isTshark = binary.toLowerCase().contains('tshark');

    final args = <String>[];
    if (isTcpdump) {
      args.addAll([
        '-i', interfaceName,
        '-U', // Packet-buffered stdout
        '-s', '0', // Capture full packet
        '-w', '-', // Output raw PCAP stream to stdout
        bpfFilter,
      ]);
    } else if (isTshark) {
      args.addAll([
        '-i', interfaceName,
        '-l', // Flush stdout after each packet
        '-F', 'pcap',
        '-w', '-',
        '-f', bpfFilter,
      ]);
    } else {
      // dumpcap
      args.addAll([
        '-i', interfaceName,
        '-P', // Save file in PCAP format
        '-w', '-',
        '-f', bpfFilter,
      ]);
    }

    _generatedCommandLine = '$binary ${args.join(' ')}';
    debugPrint('Executing capture: $_generatedCommandLine');

    try {
      _process = await Process.start(binary, args);
      _setStatus(CaptureStatus.listening);

      _stdoutSub = _process!.stdout.listen(
        (chunk) => _handleDataChunk(chunk, interfaceName),
        onError: (e) {
          debugPrint('Capture stdout error: $e');
          _lastError = 'Capture read error: $e';
          _setStatus(CaptureStatus.error);
        },
        onDone: () {
          debugPrint('Capture stdout closed.');
          if (_status == CaptureStatus.listening) {
            _setStatus(CaptureStatus.stopped);
          }
        },
      );

      _stderrSub = _process!.stderr.listen((errBytes) {
        final errText = String.fromCharCodes(errBytes);
        debugPrint('Capture stderr: $errText');
        if (errText.contains('permission') ||
            errText.contains('Operation not permitted') ||
            errText.contains('You don\'t have permission')) {
          _lastError =
              'Capture Permission Denied. Run with elevated privileges or execute:\n'
              'sudo setcap cap_net_raw,cap_net_admin=eip $binary';
          _setStatus(CaptureStatus.error);
        } else if (errText.contains('No such device') ||
            errText.contains('That device is not up')) {
          _lastError = errText.trim();
          _setStatus(CaptureStatus.error);
        }
      });

      _process!.exitCode.then((code) {
        debugPrint('Capture process exited with code $code');
        if (_status == CaptureStatus.listening) {
          if (code != 0 && _lastError == null) {
            _lastError = 'Capture exited with code $code';
            _setStatus(CaptureStatus.error);
          } else {
            _setStatus(CaptureStatus.stopped);
          }
        }
      });

      return true;
    } catch (e) {
      _lastError = 'Failed to spawn capture process: $e';
      _setStatus(CaptureStatus.error);
      return false;
    }
  }

  void _handleDataChunk(List<int> chunk, String interfaceName) {
    try {
      final packets = _pcapParser.appendChunk(chunk);
      for (final pkt in packets) {
        _framesReceived++;
        final discovery = dissectRawFrame(
          pkt.data,
          timestamp: pkt.timestamp,
          interfaceName: interfaceName,
        );
        if (discovery != null) {
          _discoveryController.add(discovery);
        }
      }
    } catch (e) {
      debugPrint('Error parsing streaming pcap chunk: $e');
    }
  }

  /// Dissects an arbitrary raw frame (used for live capture, file import, or demo data).
  static SwitchPortDiscovery? dissectRawFrame(
    Uint8List rawBytes, {
    DateTime? timestamp,
    String interfaceName = 'eth0',
  }) {
    if (LldpDissector.isLldpFrame(rawBytes)) {
      return LldpDissector.dissect(
        packet: rawBytes,
        timestamp: timestamp,
        interfaceName: interfaceName,
      );
    } else if (CdpDissector.isCdpFrame(rawBytes)) {
      return CdpDissector.dissect(
        packet: rawBytes,
        timestamp: timestamp,
        interfaceName: interfaceName,
      );
    }
    return null;
  }

  Future<void> stopCapture() async {
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _process = null;
    }
    await _stdoutSub?.cancel();
    _stdoutSub = null;
    await _stderrSub?.cancel();
    _stderrSub = null;
    _setStatus(CaptureStatus.stopped);
  }

  void _setStatus(CaptureStatus s) {
    _status = s;
    if (!_statusController.isClosed) {
      _statusController.add(s);
    }
  }

  void dispose() {
    stopCapture();
    _discoveryController.close();
    _statusController.close();
  }
}
