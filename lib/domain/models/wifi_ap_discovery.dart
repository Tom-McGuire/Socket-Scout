import 'dart:convert';
import 'package:network_suite_shared/network_suite_shared.dart';

enum WifiBand {
  band24,
  band5,
  band6,
  unknown;

  String get label {
    switch (this) {
      case WifiBand.band24:
        return '2.4 GHz';
      case WifiBand.band5:
        return '5 GHz';
      case WifiBand.band6:
        return '6 GHz';
      case WifiBand.unknown:
        return 'Unknown';
    }
  }

  static WifiBand fromFrequencyMhz(int? freqMhz) {
    if (freqMhz == null) return WifiBand.unknown;
    if (freqMhz >= 2400 && freqMhz <= 2500) return WifiBand.band24;
    if (freqMhz >= 4900 && freqMhz <= 5925) return WifiBand.band5;
    if (freqMhz > 5925 && freqMhz <= 7125) return WifiBand.band6;
    return WifiBand.unknown;
  }

  static WifiBand fromChannel(int? channel) {
    if (channel == null) return WifiBand.unknown;
    if (channel >= 1 && channel <= 14) return WifiBand.band24;
    if (channel >= 32 && channel <= 177) return WifiBand.band5;
    return WifiBand.unknown;
  }

  static WifiBand fromString(String? value) {
    if (value == null) return WifiBand.unknown;
    final lower = value.toLowerCase();
    if (lower.contains('2.4') || lower == 'band24') return WifiBand.band24;
    if (lower.contains('6') && lower.contains('ghz') || lower == 'band6') {
      return WifiBand.band6;
    }
    if (lower.contains('5') || lower == 'band5') return WifiBand.band5;
    return WifiBand.unknown;
  }
}

class WifiNeighborAp {
  const WifiNeighborAp({
    required this.bssid,
    this.ssid,
    this.band = WifiBand.unknown,
    this.channel,
    this.frequencyMhz,
    this.rssiDbm,
    this.signalPercent,
    this.apHostname,
    this.vendor,
    this.securityType,
    this.isConnected = false,
  });

  final String bssid;
  final String? ssid;
  final WifiBand band;
  final int? channel;
  final int? frequencyMhz;
  final int? rssiDbm;
  final int? signalPercent;
  final String? apHostname;
  final String? vendor;
  final String? securityType;
  final bool isConnected;

  String get normalizedBssid => SharedDevice.normalizeMac(bssid);

  String? get resolvedVendor {
    if (vendor != null && vendor!.isNotEmpty) return vendor;
    try {
      final looked = OuiLookup.lookupVendor(normalizedBssid);
      if (looked.isNotEmpty && !looked.toLowerCase().contains('unknown')) {
        return looked;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toJson() => {
        'bssid': normalizedBssid,
        'ssid': ssid,
        'band': band.name,
        'channel': channel,
        'frequency_mhz': frequencyMhz,
        'rssi_dbm': rssiDbm,
        'signal_percent': signalPercent,
        'ap_hostname': apHostname,
        'vendor': vendor,
        'security_type': securityType,
        'is_connected': isConnected,
      };

  factory WifiNeighborAp.fromJson(Map<String, dynamic> map) {
    final freq = map['frequency_mhz'] as int?;
    final ch = map['channel'] as int?;
    final bandRaw = map['band'] as String?;
    final band = bandRaw != null
        ? WifiBand.fromString(bandRaw)
        : (freq != null
            ? WifiBand.fromFrequencyMhz(freq)
            : WifiBand.fromChannel(ch));

    return WifiNeighborAp(
      bssid: map['bssid'] as String? ?? '00:00:00:00:00:00',
      ssid: map['ssid'] as String?,
      band: band,
      channel: ch,
      frequencyMhz: freq,
      rssiDbm: map['rssi_dbm'] as int?,
      signalPercent: map['signal_percent'] as int?,
      apHostname: map['ap_hostname'] as String?,
      vendor: map['vendor'] as String?,
      securityType: map['security_type'] as String?,
      isConnected: map['is_connected'] == true,
    );
  }
}

class WifiApDiscovery {
  const WifiApDiscovery({
    this.id,
    required this.timestamp,
    required this.interfaceName,
    required this.ssid,
    required this.bssid,
    this.vendor,
    this.apHostname,
    this.band = WifiBand.unknown,
    this.channel,
    this.frequencyMhz,
    this.channelWidthMhz,
    this.rssiDbm,
    this.noiseDbm,
    this.snrDb,
    this.signalPercent,
    this.txRateMbps,
    this.rxRateMbps,
    this.wifiStandard,
    this.securityType,
    this.neighbors = const [],
    this.rawTelemetry = '',
    this.isDemo = false,
  });

  final int? id;
  final DateTime timestamp;
  final String interfaceName;
  final String ssid;
  final String bssid;
  final String? vendor;
  final String? apHostname;
  final WifiBand band;
  final int? channel;
  final int? frequencyMhz;
  final int? channelWidthMhz;
  final int? rssiDbm;
  final int? noiseDbm;
  final int? snrDb;
  final int? signalPercent;
  final double? txRateMbps;
  final double? rxRateMbps;
  final String? wifiStandard;
  final String? securityType;
  final List<WifiNeighborAp> neighbors;
  final String rawTelemetry;
  final bool isDemo;

  String get normalizedBssid => SharedDevice.normalizeMac(bssid);

  String? get resolvedVendor {
    if (vendor != null && vendor!.isNotEmpty) return vendor;
    try {
      final looked = OuiLookup.lookupVendor(normalizedBssid);
      if (looked.isNotEmpty && !looked.toLowerCase().contains('unknown')) {
        return looked;
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the best display name for this AP, prioritizing any custom name
  /// configured in the Network Suite Shared Device Database.
  String get displayName {
    if (!isDemo && SharedDeviceDatabase.instance.isInitialized) {
      try {
        final device =
            SharedDeviceDatabase.instance.getDeviceByMac(normalizedBssid);
        if (device != null && device.hasCustomName) {
          return device.name;
        }
      } catch (_) {}
    }
    if (apHostname != null && apHostname!.trim().isNotEmpty) {
      return apHostname!.trim();
    }
    if (ssid.trim().isNotEmpty && ssid != '<Hidden SSID>') {
      return '$ssid ($normalizedBssid)';
    }
    return normalizedBssid;
  }

  /// Whether this AP has a custom name stored in the Shared Device Database.
  bool get hasCustomName {
    if (isDemo || !SharedDeviceDatabase.instance.isInitialized) return false;
    try {
      final device =
          SharedDeviceDatabase.instance.getDeviceByMac(normalizedBssid);
      return device != null && device.hasCustomName;
    } catch (_) {
      return false;
    }
  }

  /// Effective signal percentage (derived from RSSI if OS didn't report %).
  int? get effectiveSignalPercent {
    if (signalPercent != null) return signalPercent!.clamp(0, 100);
    if (rssiDbm == null) return null;
    // Standard linear approximation: -50 dBm => 100%, -100 dBm => 0%
    return ((rssiDbm! + 100) * 2).clamp(0, 100);
  }

  /// Effective SNR in dB if both RSSI and noise floor are known.
  int? get effectiveSnrDb {
    if (snrDb != null) return snrDb;
    if (rssiDbm != null && noiseDbm != null) {
      return rssiDbm! - noiseDbm!;
    }
    return null;
  }

  String get signalQualityLabel {
    final rssi = rssiDbm;
    if (rssi != null) {
      if (rssi >= -55) return 'Excellent';
      if (rssi >= -67) return 'Good';
      if (rssi >= -75) return 'Fair';
      return 'Weak';
    }
    final pct = signalPercent;
    if (pct != null) {
      if (pct >= 80) return 'Excellent';
      if (pct >= 60) return 'Good';
      if (pct >= 40) return 'Fair';
      return 'Weak';
    }
    return 'Unknown';
  }

  String get formattedRssi {
    if (rssiDbm != null && effectiveSignalPercent != null) {
      return '$rssiDbm dBm (${effectiveSignalPercent!}%)';
    }
    if (rssiDbm != null) return '$rssiDbm dBm';
    if (signalPercent != null) return '$signalPercent%';
    return 'N/A';
  }

  String get formattedChannel {
    final parts = <String>[];
    if (channel != null) {
      parts.add('Ch $channel');
    }
    if (band != WifiBand.unknown) {
      parts.add(band.label);
    }
    if (channelWidthMhz != null) {
      parts.add('${channelWidthMhz}MHz');
    }
    if (parts.isEmpty && frequencyMhz != null) {
      return '$frequencyMhz MHz';
    }
    return parts.isEmpty ? 'Unknown' : parts.join(' • ');
  }

  String get formattedLinkSpeed {
    if (txRateMbps != null && rxRateMbps != null) {
      return '${_fmtMbps(txRateMbps!)} / ${_fmtMbps(rxRateMbps!)} Mbps';
    }
    if (txRateMbps != null) return '${_fmtMbps(txRateMbps!)} Mbps Tx';
    if (rxRateMbps != null) return '${_fmtMbps(rxRateMbps!)} Mbps Rx';
    return 'N/A';
  }

  static String _fmtMbps(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  String get summaryDescription {
    final parts = <String>[];
    if (ssid.isNotEmpty) parts.add('SSID $ssid');
    parts.add('BSSID $normalizedBssid');
    if (channel != null) parts.add('Ch $channel (${band.label})');
    if (rssiDbm != null) parts.add('$rssiDbm dBm');
    return parts.join(' • ');
  }

  WifiApDiscovery copyWith({
    int? id,
    DateTime? timestamp,
    String? interfaceName,
    String? ssid,
    String? bssid,
    String? vendor,
    String? apHostname,
    WifiBand? band,
    int? channel,
    int? frequencyMhz,
    int? channelWidthMhz,
    int? rssiDbm,
    int? noiseDbm,
    int? snrDb,
    int? signalPercent,
    double? txRateMbps,
    double? rxRateMbps,
    String? wifiStandard,
    String? securityType,
    List<WifiNeighborAp>? neighbors,
    String? rawTelemetry,
    bool? isDemo,
  }) {
    return WifiApDiscovery(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      interfaceName: interfaceName ?? this.interfaceName,
      ssid: ssid ?? this.ssid,
      bssid: bssid ?? this.bssid,
      vendor: vendor ?? this.vendor,
      apHostname: apHostname ?? this.apHostname,
      band: band ?? this.band,
      channel: channel ?? this.channel,
      frequencyMhz: frequencyMhz ?? this.frequencyMhz,
      channelWidthMhz: channelWidthMhz ?? this.channelWidthMhz,
      rssiDbm: rssiDbm ?? this.rssiDbm,
      noiseDbm: noiseDbm ?? this.noiseDbm,
      snrDb: snrDb ?? this.snrDb,
      signalPercent: signalPercent ?? this.signalPercent,
      txRateMbps: txRateMbps ?? this.txRateMbps,
      rxRateMbps: rxRateMbps ?? this.rxRateMbps,
      wifiStandard: wifiStandard ?? this.wifiStandard,
      securityType: securityType ?? this.securityType,
      neighbors: neighbors ?? this.neighbors,
      rawTelemetry: rawTelemetry ?? this.rawTelemetry,
      isDemo: isDemo ?? this.isDemo,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'interface_name': interfaceName,
      'ssid': ssid,
      'bssid': normalizedBssid,
      'vendor': vendor,
      'ap_hostname': apHostname,
      'band': band.name,
      'channel': channel,
      'frequency_mhz': frequencyMhz,
      'channel_width_mhz': channelWidthMhz,
      'rssi_dbm': rssiDbm,
      'noise_dbm': noiseDbm,
      'snr_db': snrDb,
      'signal_percent': signalPercent,
      'tx_rate_mbps': txRateMbps,
      'rx_rate_mbps': rxRateMbps,
      'wifi_standard': wifiStandard,
      'security_type': securityType,
      'neighbors_json':
          jsonEncode(neighbors.map((n) => n.toJson()).toList()),
      'raw_telemetry': rawTelemetry,
      'is_demo': isDemo ? 1 : 0,
    };
  }

  factory WifiApDiscovery.fromMap(Map<String, dynamic> map) {
    List<WifiNeighborAp> parsedNeighbors = const [];
    final rawNeighbors = map['neighbors_json'] as String?;
    if (rawNeighbors != null && rawNeighbors.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawNeighbors);
        if (decoded is List) {
          parsedNeighbors = decoded
              .whereType<Map>()
              .map((e) => WifiNeighborAp.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }

    final freq = map['frequency_mhz'] as int?;
    final ch = map['channel'] as int?;
    final bandStr = map['band'] as String?;
    final band = bandStr != null
        ? WifiBand.fromString(bandStr)
        : (freq != null
            ? WifiBand.fromFrequencyMhz(freq)
            : WifiBand.fromChannel(ch));

    return WifiApDiscovery(
      id: map['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      interfaceName: map['interface_name'] as String? ?? 'wlan0',
      ssid: map['ssid'] as String? ?? '',
      bssid: map['bssid'] as String? ?? '00:00:00:00:00:00',
      vendor: map['vendor'] as String?,
      apHostname: map['ap_hostname'] as String?,
      band: band,
      channel: ch,
      frequencyMhz: freq,
      channelWidthMhz: map['channel_width_mhz'] as int?,
      rssiDbm: map['rssi_dbm'] as int?,
      noiseDbm: map['noise_dbm'] as int?,
      snrDb: map['snr_db'] as int?,
      signalPercent: map['signal_percent'] as int?,
      txRateMbps: (map['tx_rate_mbps'] as num?)?.toDouble(),
      rxRateMbps: (map['rx_rate_mbps'] as num?)?.toDouble(),
      wifiStandard: map['wifi_standard'] as String?,
      securityType: map['security_type'] as String?,
      neighbors: parsedNeighbors,
      rawTelemetry: map['raw_telemetry'] as String? ?? '',
      isDemo: (map['is_demo'] as int? ?? 0) == 1,
    );
  }
}
