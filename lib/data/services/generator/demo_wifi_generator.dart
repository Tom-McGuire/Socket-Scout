import '../../../domain/models/wifi_ap_discovery.dart';

/// Generates realistic Wi-Fi Access Point roaming & RF telemetry presets
/// for immediate verification and guided walkthroughs without a live wireless link.
///
/// All generated records are marked `isDemo: true` and are strictly excluded
/// from `SharedDeviceDatabase`.
class DemoWifiGenerator {
  static List<WifiApDiscovery> presets({String interfaceName = 'demo-wlan0'}) {
    final now = DateTime.now();

    return [
      WifiApDiscovery(
        timestamp: now.subtract(const Duration(minutes: 4)),
        interfaceName: interfaceName,
        ssid: 'CORP-HQ-WIFI',
        bssid: '24:5A:4C:11:22:33',
        vendor: 'Ubiquiti Inc.',
        apHostname: 'AP-FL1-LOBBY-U6PRO',
        band: WifiBand.band24,
        channel: 6,
        frequencyMhz: 2437,
        channelWidthMhz: 20,
        rssiDbm: -71,
        noiseDbm: -93,
        snrDb: 22,
        signalPercent: 58,
        txRateMbps: 144.4,
        rxRateMbps: 130.0,
        wifiStandard: 'Wi-Fi 6 (802.11ax)',
        securityType: 'WPA3-Personal (SAE)',
        neighbors: const [
          WifiNeighborAp(
            bssid: '24:5A:4C:11:22:33',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band24,
            channel: 6,
            frequencyMhz: 2437,
            rssiDbm: -71,
            apHostname: 'AP-FL1-LOBBY-U6PRO',
            vendor: 'Ubiquiti Inc.',
            securityType: 'WPA3-Personal',
            isConnected: true,
          ),
          WifiNeighborAp(
            bssid: '00:18:0A:44:55:66',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band5,
            channel: 36,
            frequencyMhz: 5180,
            rssiDbm: -64,
            apHostname: 'AP-FL2-CONF-MR46',
            vendor: 'Cisco Meraki',
            securityType: 'WPA3-Enterprise',
          ),
        ],
        rawTelemetry: '''Connected to 24:5a:4c:11:22:33 (on $interfaceName)
\tSSID: CORP-HQ-WIFI
\tfreq: 2437.0
\tsignal: -71 dBm
\trx bitrate: 130.0 MBit/s HE-MCS 7
\ttx bitrate: 144.4 MBit/s HE-MCS 7
\tAP Name (Vendor IE): AP-FL1-LOBBY-U6PRO''',
        isDemo: true,
      ),
      WifiApDiscovery(
        timestamp: now.subtract(const Duration(minutes: 2)),
        interfaceName: interfaceName,
        ssid: 'CORP-HQ-WIFI',
        bssid: '00:18:0A:44:55:66',
        vendor: 'Cisco Meraki',
        apHostname: 'AP-FL2-CONF-MR46',
        band: WifiBand.band5,
        channel: 36,
        frequencyMhz: 5180,
        channelWidthMhz: 80,
        rssiDbm: -58,
        noiseDbm: -95,
        snrDb: 37,
        signalPercent: 84,
        txRateMbps: 866.7,
        rxRateMbps: 780.0,
        wifiStandard: 'Wi-Fi 6 (802.11ax)',
        securityType: 'WPA3-Enterprise (802.1X)',
        neighbors: const [
          WifiNeighborAp(
            bssid: '00:18:0A:44:55:66',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band5,
            channel: 36,
            frequencyMhz: 5180,
            rssiDbm: -58,
            apHostname: 'AP-FL2-CONF-MR46',
            vendor: 'Cisco Meraki',
            securityType: 'WPA3-Enterprise',
            isConnected: true,
          ),
          WifiNeighborAp(
            bssid: '94:B4:0F:77:88:99',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band6,
            channel: 37,
            frequencyMhz: 6135,
            rssiDbm: -52,
            apHostname: 'AP-FL3-ENG-655',
            vendor: 'Aruba / HPE',
            securityType: 'WPA3-Enterprise',
          ),
          WifiNeighborAp(
            bssid: '24:5A:4C:11:22:33',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band24,
            channel: 6,
            frequencyMhz: 2437,
            rssiDbm: -74,
            apHostname: 'AP-FL1-LOBBY-U6PRO',
            vendor: 'Ubiquiti Inc.',
            securityType: 'WPA3-Personal',
          ),
        ],
        rawTelemetry: '''Connected to 00:18:0a:44:55:66 (on $interfaceName)
\tSSID: CORP-HQ-WIFI
\tfreq: 5180.0
\tsignal: -58 dBm
\trx bitrate: 780.0 MBit/s 80MHz HE-MCS 8
\ttx bitrate: 866.7 MBit/s 80MHz HE-MCS 9
\tAP Name (Vendor IE): AP-FL2-CONF-MR46''',
        isDemo: true,
      ),
      WifiApDiscovery(
        timestamp: now,
        interfaceName: interfaceName,
        ssid: 'CORP-HQ-WIFI',
        bssid: '94:B4:0F:77:88:99',
        vendor: 'Aruba / HPE',
        apHostname: 'AP-FL3-ENG-655',
        band: WifiBand.band6,
        channel: 37,
        frequencyMhz: 6135,
        channelWidthMhz: 160,
        rssiDbm: -49,
        noiseDbm: -96,
        snrDb: 47,
        signalPercent: 96,
        txRateMbps: 2401.9,
        rxRateMbps: 2161.7,
        wifiStandard: 'Wi-Fi 6E (802.11ax)',
        securityType: 'WPA3-Enterprise (802.1X)',
        neighbors: const [
          WifiNeighborAp(
            bssid: '94:B4:0F:77:88:99',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band6,
            channel: 37,
            frequencyMhz: 6135,
            rssiDbm: -49,
            apHostname: 'AP-FL3-ENG-655',
            vendor: 'Aruba / HPE',
            securityType: 'WPA3-Enterprise',
            isConnected: true,
          ),
          WifiNeighborAp(
            bssid: '00:18:0A:44:55:66',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band5,
            channel: 36,
            frequencyMhz: 5180,
            rssiDbm: -63,
            apHostname: 'AP-FL2-CONF-MR46',
            vendor: 'Cisco Meraki',
            securityType: 'WPA3-Enterprise',
          ),
          WifiNeighborAp(
            bssid: '24:5A:4C:11:22:33',
            ssid: 'CORP-HQ-WIFI',
            band: WifiBand.band24,
            channel: 6,
            frequencyMhz: 2437,
            rssiDbm: -78,
            apHostname: 'AP-FL1-LOBBY-U6PRO',
            vendor: 'Ubiquiti Inc.',
            securityType: 'WPA3-Personal',
          ),
        ],
        rawTelemetry: '''Connected to 94:b4:0f:77:88:99 (on $interfaceName)
\tSSID: CORP-HQ-WIFI
\tfreq: 6135.0
\tsignal: -49 dBm
\trx bitrate: 2161.7 MBit/s 160MHz HE-MCS 10
\ttx bitrate: 2401.9 MBit/s 160MHz HE-MCS 11
\tAP Name (Vendor IE): AP-FL3-ENG-655''',
        isDemo: true,
      ),
    ];
  }
}
