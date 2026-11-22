import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/data/services/wifi/wifi_discovery_service.dart';
import 'package:socket_scout/domain/models/wifi_ap_discovery.dart';

void main() {
  group('WifiDiscoveryService cross-platform parsers', () {
    test('parses Linux iw dev link output for 5 GHz Wi-Fi 6', () {
      const sample = '''
Connected to 00:18:0a:44:55:66 (on wlp2s0)
\tSSID: CORP-HQ-WIFI
\tfreq: 5180.0
\tRX: 102400 bytes (1200 packets)
\tTX: 51200 bytes (600 packets)
\tsignal: -56 dBm
\trx bitrate: 780.0 MBit/s 80MHz HE-MCS 8 HE-NSS 2
\ttx bitrate: 866.7 MBit/s 80MHz HE-MCS 9 HE-NSS 2
''';

      final disc = WifiDiscoveryService.parseLinuxIwLink(
        sample,
        interfaceName: 'wlp2s0',
      );
      expect(disc, isNotNull);
      expect(disc!.normalizedBssid, '00:18:0A:44:55:66');
      expect(disc.ssid, 'CORP-HQ-WIFI');
      expect(disc.band, WifiBand.band5);
      expect(disc.channel, 36);
      expect(disc.frequencyMhz, 5180);
      expect(disc.channelWidthMhz, 80);
      expect(disc.rssiDbm, -56);
      expect(disc.txRateMbps, 866.7);
      expect(disc.rxRateMbps, 780.0);
      expect(disc.wifiStandard, 'Wi-Fi 6 (802.11ax)');
    });

    test('parses Linux iw dev link output for 6 GHz Wi-Fi 6E', () {
      const sample = '''
Connected to 94:b4:0f:77:88:99 (on wlan0)
\tSSID: ENG-6E
\tfreq: 6135.0
\tsignal: -48 dBm
\ttx bitrate: 2401.9 MBit/s 160MHz HE-MCS 11
''';

      final disc = WifiDiscoveryService.parseLinuxIwLink(
        sample,
        interfaceName: 'wlan0',
      );
      expect(disc, isNotNull);
      expect(disc!.band, WifiBand.band6);
      expect(disc.channel, 37);
      expect(disc.channelWidthMhz, 160);
      expect(disc.wifiStandard, 'Wi-Fi 6E (802.11ax)');
    });

    test('returns null for Linux iw dev link when not connected', () {
      final disc = WifiDiscoveryService.parseLinuxIwLink(
        'Not connected.\n',
        interfaceName: 'wlan0',
      );
      expect(disc, isNull);
    });

    test('parses Linux iw scan neighbors and enterprise AP Name IE', () {
      const scanSample = '''
BSS 00:18:0a:44:55:66(on wlan0) -- associated
\tfreq: 5180
\tsignal: -54.00 dBm
\tSSID: CORP-HQ-WIFI
\tRSN:\t * Version: 1
\t\t * Authentication suites: IEEE 802.1X
\tVendor specific: OUI 00:40:96, AP Name: AP-FL2-CONF-01
BSS 24:5a:4c:11:22:33(on wlan0)
\tfreq: 2437
\tsignal: -72.00 dBm
\tSSID: CORP-HQ-WIFI
\tDS Parameter set: channel 6
''';

      final neighbors = WifiDiscoveryService.parseLinuxIwScan(
        scanSample,
        connectedBssid: '00:18:0A:44:55:66',
      );
      expect(neighbors.length, 2);
      expect(neighbors.first.normalizedBssid, '00:18:0A:44:55:66');
      expect(neighbors.first.isConnected, isTrue);
      expect(neighbors.first.apHostname, 'AP-FL2-CONF-01');
      expect(neighbors.first.band, WifiBand.band5);
      expect(neighbors.last.channel, 6);
      expect(neighbors.last.band, WifiBand.band24);
      expect(neighbors.last.isConnected, isFalse);
    });

    test('parses Linux nmcli escaped-colon output', () {
      const nmcliSample = r'''
yes:CORP-HQ-WIFI:00\:18\:0A\:44\:55\:66:36:5180 MHz:866 Mbit/s:88:WPA3
no:GUEST-WIFI:24\:5A\:4C\:11\:22\:33:6:2437 MHz:144 Mbit/s:54:WPA2
''';

      final disc = WifiDiscoveryService.parseLinuxNmcliWifi(
        nmcliSample,
        interfaceName: 'wlan0',
      );
      expect(disc, isNotNull);
      expect(disc!.ssid, 'CORP-HQ-WIFI');
      expect(disc.normalizedBssid, '00:18:0A:44:55:66');
      expect(disc.channel, 36);
      expect(disc.band, WifiBand.band5);
      expect(disc.signalPercent, 88);
      expect(disc.securityType, 'WPA3');
      expect(disc.neighbors.length, 2);
    });

    test('parses Windows netsh wlan show interfaces output', () {
      const sample = '''
There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6E AX211 160MHz
    GUID                   : 11111111-2222-3333-4444-555555555555
    Physical address       : aa:bb:cc:dd:ee:ff
    State                  : connected
    SSID                   : OFFICE-NET
    AP BSSID               : 94:b4:0f:77:88:99
    Band                   : 5 GHz
    Network type           : Infrastructure
    Radio type             : 802.11ax
    Authentication         : WPA3-Personal
    Channel                : 44
    Receive rate (Mbps)    : 1201
    Transmit rate (Mbps)   : 1201
    Signal                 : 92%
''';

      final result = WifiDiscoveryService.parseWindowsNetshInterfaces(
        sample,
        interfaceName: 'Wi-Fi',
      );
      expect(result.isPermissionBlocked, isFalse);
      expect(result.discovery, isNotNull);
      final disc = result.discovery!;
      expect(disc.ssid, 'OFFICE-NET');
      expect(disc.normalizedBssid, '94:B4:0F:77:88:99');
      expect(disc.band, WifiBand.band5);
      expect(disc.channel, 44);
      expect(disc.signalPercent, 92);
      expect(disc.txRateMbps, 1201);
      expect(disc.rxRateMbps, 1201);
      expect(disc.securityType, 'WPA3-Personal');
    });

    test('detects Windows Location Services permission error', () {
      const sample =
          'This command requires location permission. Please enable Location Services in Windows Settings.';
      final result = WifiDiscoveryService.parseWindowsNetshInterfaces(
        sample,
        interfaceName: 'Wi-Fi',
      );
      expect(result.discovery, isNull);
      expect(result.isPermissionBlocked, isTrue);
      expect(result.error, contains('Location Services'));
    });

    test('parses Windows netsh wlan show networks mode=bssid', () {
      const sample = '''
SSID 1 : OFFICE-NET
    Network type            : Infrastructure
    Authentication          : WPA3-Personal
    Encryption              : CCMP
    BSSID 1                 : 94:b4:0f:77:88:99
         Signal             : 90%
         Radio type         : 802.11ax
         Band               : 5 GHz
         Channel            : 44
    BSSID 2                 : 24:5a:4c:11:22:33
         Signal             : 62%
         Radio type         : 802.11ax
         Band               : 2.4 GHz
         Channel            : 11
''';

      final neighbors = WifiDiscoveryService.parseWindowsNetshNetworks(
        sample,
        connectedBssid: '94:B4:0F:77:88:99',
      );
      expect(neighbors.length, 2);
      expect(neighbors.first.isConnected, isTrue);
      expect(neighbors.first.channel, 44);
      expect(neighbors.last.channel, 11);
      expect(neighbors.last.band, WifiBand.band24);
    });

    test('parses macOS wdutil info and detects redacted BSSID', () {
      const normalSample = '''
WIFI
    SSID                 : STUDIO-WIFI
    BSSID                : 00:18:0a:44:55:66
    RSSI                 : -51 dBm
    Noise                : -94 dBm
    Tx Rate              : 1200.0 Mbps
    Security             : WPA3 Personal
    PHY Mode             : 11ax
    Channel              : 5g36/80
''';
      final ok = WifiDiscoveryService.parseMacOsWdutil(
        normalSample,
        interfaceName: 'en0',
      );
      expect(ok.isPermissionBlocked, isFalse);
      expect(ok.discovery, isNotNull);
      expect(ok.discovery!.ssid, 'STUDIO-WIFI');
      expect(ok.discovery!.normalizedBssid, '00:18:0A:44:55:66');
      expect(ok.discovery!.band, WifiBand.band5);
      expect(ok.discovery!.channel, 36);
      expect(ok.discovery!.channelWidthMhz, 80);
      expect(ok.discovery!.snrDb, 43);

      const redactedSample = '''
WIFI
    SSID                 : <redacted>
    BSSID                : <redacted>
''';
      final blocked = WifiDiscoveryService.parseMacOsWdutil(
        redactedSample,
        interfaceName: 'en0',
      );
      expect(blocked.discovery, isNull);
      expect(blocked.isPermissionBlocked, isTrue);
    });

    test('parses macOS system_profiler SPAirPortDataType', () {
      const sample = '''
Wi-Fi:
      Interfaces:
        en0:
          Current Network Information:
            STUDIO-6E:
              PHY Mode: 802.11ax
              BSSID: 94:b4:0f:77:88:99
              Channel: 37 (6GHz, 160MHz)
              Security: WPA3 Personal
              Signal / Noise: -52 dBm / -95 dBm
              Transmit Rate: 2400
          Other Local Wi-Fi Networks:
            Guest:
''';

      final res = WifiDiscoveryService.parseMacOsSystemProfiler(
        sample,
        interfaceName: 'en0',
      );
      expect(res.isPermissionBlocked, isFalse);
      expect(res.discovery, isNotNull);
      expect(res.discovery!.ssid, 'STUDIO-6E');
      expect(res.discovery!.normalizedBssid, '94:B4:0F:77:88:99');
      expect(res.discovery!.band, WifiBand.band6);
      expect(res.discovery!.channel, 37);
      expect(res.discovery!.channelWidthMhz, 160);
      expect(res.discovery!.snrDb, 43);
    });

    test('detects roaming when BSSID changes across polls', () async {
      int pollIndex = 0;
      final outputs = [
        'Connected to 00:18:0a:44:55:66 (on wlan0)\n\tSSID: CORP\n\tfreq: 5180\n\tsignal: -60 dBm\n',
        'Connected to 00:18:0a:44:55:66 (on wlan0)\n\tSSID: CORP\n\tfreq: 5180\n\tsignal: -55 dBm\n',
        'Connected to 94:b4:0f:77:88:99 (on wlan0)\n\tSSID: CORP\n\tfreq: 6135\n\tsignal: -49 dBm\n',
      ];

      final service = WifiDiscoveryService(
        platformOverride: 'linux',
        processRunner: (exe, args) async {
          if (exe == 'iw' && args.contains('link')) {
            final idx = pollIndex < outputs.length ? pollIndex : outputs.length - 1;
            pollIndex++;
            return ProcessResult(0, 0, outputs[idx], '');
          }
          return ProcessResult(0, 1, '', '');
        },
      );

      final roamingEvents = <WifiApDiscovery>[];
      final liveEvents = <WifiApDiscovery>[];
      final sub1 = service.onDiscovery.listen(roamingEvents.add);
      final sub2 = service.onLiveTelemetry.listen(liveEvents.add);

      await service.pollOnce(interfaceName: 'wlan0');
      await service.pollOnce(interfaceName: 'wlan0');
      await service.pollOnce(interfaceName: 'wlan0');
      await Future<void>.delayed(Duration.zero);

      expect(liveEvents.length, 3);
      expect(roamingEvents.length, 2);
      expect(roamingEvents[0].normalizedBssid, '00:18:0A:44:55:66');
      expect(roamingEvents[1].normalizedBssid, '94:B4:0F:77:88:99');

      await sub1.cancel();
      await sub2.cancel();
      service.dispose();
    });
  });
}
