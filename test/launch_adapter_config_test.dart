import 'package:flutter_test/flutter_test.dart';
import 'package:socket_scout/domain/models/launch_adapter_config.dart';
import 'package:socket_scout/domain/models/network_adapter_info.dart';

void main() {
  group('NetworkAdapterInfo.isAllInterfaces', () {
    test('returns true for NetworkAdapterInfo.all and name == any', () {
      expect(NetworkAdapterInfo.all.isAllInterfaces, isTrue);
      expect(const NetworkAdapterInfo(name: 'any').isAllInterfaces, isTrue);
    });

    test('returns false for regular adapters', () {
      const eth = NetworkAdapterInfo(
        name: 'eth0',
        displayName: 'Ethernet',
        ipAddress: '192.168.1.10',
      );
      expect(eth.isAllInterfaces, isFalse);
    });
  });

  group('LaunchAdapterConfig properties and equality', () {
    test('hasOverride and hasAdapterOverride reflect non-empty values', () {
      const empty = LaunchAdapterConfig();
      expect(empty.hasOverride, isFalse);
      expect(empty.hasAdapterOverride, isFalse);

      const whitespace = LaunchAdapterConfig(
        adapterIp: '   ',
        adapterName: '\t\n',
      );
      expect(whitespace.hasOverride, isFalse);
      expect(whitespace.hasAdapterOverride, isFalse);

      const ipOnly = LaunchAdapterConfig(adapterIp: '10.0.0.5');
      expect(ipOnly.hasOverride, isTrue);
      expect(ipOnly.hasAdapterOverride, isTrue);

      const nameOnly = LaunchAdapterConfig(adapterName: 'eth0');
      expect(nameOnly.hasOverride, isTrue);
      expect(nameOnly.hasAdapterOverride, isTrue);
    });

    test('implements value equality, hashCode, and toString', () {
      const a = LaunchAdapterConfig(
        adapterIp: '192.168.1.50',
        adapterName: 'eth0',
      );
      const b = LaunchAdapterConfig(
        adapterIp: '192.168.1.50',
        adapterName: 'eth0',
      );
      const c = LaunchAdapterConfig(
        adapterIp: '192.168.1.51',
        adapterName: 'eth0',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(
        a.toString(),
        'LaunchAdapterConfig(adapterIp: 192.168.1.50, adapterName: eth0)',
      );
    });
  });

  group('LaunchAdapterConfig.fromArgs', () {
    test('returns empty config when args are empty', () {
      final config = LaunchAdapterConfig.fromArgs(const []);
      expect(config.adapterIp, isNull);
      expect(config.adapterName, isNull);
      expect(config.hasOverride, isFalse);
    });

    test('parses space-separated flags', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '192.168.1.50',
        '--adapter-name',
        'eth0',
      ]);
      expect(config.adapterIp, '192.168.1.50');
      expect(config.adapterName, 'eth0');
      expect(config.hasOverride, isTrue);
    });

    test('parses equals-separated flags', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip=10.20.30.40',
        '--adapter-name=Wi-Fi',
      ]);
      expect(config.adapterIp, '10.20.30.40');
      expect(config.adapterName, 'Wi-Fi');
    });

    test('parses mixed forms and ignores unknown flags and positional args', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--verbose',
        'positional-arg',
        '--adapter-ips',
        '1.2.3.4',
        '--adapter-ip=172.16.0.10',
        '--theme=dark',
        '--adapter-name',
        'enp3s0',
        '--adapter-name-extra=ignored',
      ]);
      expect(config.adapterIp, '172.16.0.10');
      expect(config.adapterName, 'enp3s0');
    });

    test('trims whitespace and normalizes empty values to null', () {
      final trimmed = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '  192.168.10.5  ',
        '--adapter-name=  Intel Ethernet  ',
      ]);
      expect(trimmed.adapterIp, '192.168.10.5');
      expect(trimmed.adapterName, 'Intel Ethernet');

      final empties = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip=',
        '--adapter-name',
        '   ',
      ]);
      expect(empties.adapterIp, isNull);
      expect(empties.adapterName, isNull);
      expect(empties.hasOverride, isFalse);

      final emptySpaceSeparated = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '',
        '--adapter-name=   ',
      ]);
      expect(emptySpaceSeparated.adapterIp, isNull);
      expect(emptySpaceSeparated.adapterName, isNull);
    });

    test('safely ignores trailing flags without values', () {
      final trailingIp = LaunchAdapterConfig.fromArgs(const ['--adapter-ip']);
      expect(trailingIp.adapterIp, isNull);
      expect(trailingIp.adapterName, isNull);

      final trailingName = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip=10.0.0.1',
        '--adapter-name',
      ]);
      expect(trailingName.adapterIp, '10.0.0.1');
      expect(trailingName.adapterName, isNull);
    });

    test('ignores flag-looking next args without swallowing the next flag', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '--adapter-name',
        'eth0',
      ]);
      expect(config.adapterIp, isNull);
      expect(config.adapterName, 'eth0');

      final keepsPreviousOnMalformedLaterFlag = LaunchAdapterConfig.fromArgs(
        const [
          '--adapter-ip',
          '10.0.0.2',
          '--adapter-ip',
          '--other-flag',
        ],
      );
      expect(keepsPreviousOnMalformedLaterFlag.adapterIp, '10.0.0.2');
    });
  });

  group('LaunchAdapterConfig.matchAdapter', () {
    const eth0 = NetworkAdapterInfo(
      name: 'eth0',
      displayName: 'Realtek PCIe GbE',
      ipAddress: '192.168.1.50',
    );
    const wlan0 = NetworkAdapterInfo(
      name: 'wlan0',
      displayName: 'Intel Wi-Fi 6',
      ipAddress: '10.0.0.25',
    );
    const usbEth = NetworkAdapterInfo(
      name: 'enx001122334455',
      displayName: 'USB Ethernet Adapter',
    );
    final allAdapters = <NetworkAdapterInfo>[
      NetworkAdapterInfo.all,
      eth0,
      wlan0,
      usbEth,
    ];

    test('returns null when no override or adapter list is empty', () {
      const noOverride = LaunchAdapterConfig();
      expect(noOverride.matchAdapter(allAdapters), isNull);

      const whitespaceOverride = LaunchAdapterConfig(
        adapterIp: '   ',
        adapterName: '  ',
      );
      expect(whitespaceOverride.matchAdapter(allAdapters), isNull);

      const validOverride = LaunchAdapterConfig(adapterIp: '192.168.1.50');
      expect(validOverride.matchAdapter(const []), isNull);
    });

    test('Priority 1: exact IPv4 match wins even if adapterName points elsewhere', () {
      const config = LaunchAdapterConfig(
        adapterIp: '10.0.0.25',
        adapterName: 'eth0',
      );
      expect(config.matchAdapter(allAdapters), same(wlan0));
    });

    test('Priority 1 trims whitespace and falls back to name when IP misses', () {
      const trimmedIpConfig = LaunchAdapterConfig(adapterIp: ' 192.168.1.50 ');
      expect(trimmedIpConfig.matchAdapter(allAdapters), same(eth0));

      const fallbackConfig = LaunchAdapterConfig(
        adapterIp: '172.16.99.99',
        adapterName: 'wlan0',
      );
      expect(fallbackConfig.matchAdapter(allAdapters), same(wlan0));
    });

    test('Priority 2: exact case-insensitive match on name and displayName', () {
      const byName = LaunchAdapterConfig(adapterName: 'ETH0');
      expect(byName.matchAdapter(allAdapters), same(eth0));

      const byDisplayName = LaunchAdapterConfig(
        adapterName: 'intel wi-fi 6',
      );
      expect(byDisplayName.matchAdapter(allAdapters), same(wlan0));
    });

    test('Priority 2: exact match takes precedence over earlier substring match', () {
      const subMatchFirst = NetworkAdapterInfo(
        name: 'eth0_vlan10',
        displayName: 'eth0 VLAN 10',
      );
      const exactSecond = NetworkAdapterInfo(
        name: 'eth0',
        displayName: 'Primary Ethernet',
      );

      const config = LaunchAdapterConfig(adapterName: 'ETH0');
      expect(
        config.matchAdapter([NetworkAdapterInfo.all, subMatchFirst, exactSecond]),
        same(exactSecond),
      );
    });

    test('Priority 2: substring case-insensitive match on name, displayName, and label', () {
      const byNameSubstring = LaunchAdapterConfig(adapterName: '001122');
      expect(byNameSubstring.matchAdapter(allAdapters), same(usbEth));

      const byDisplaySubstring = LaunchAdapterConfig(adapterName: 'realtek');
      expect(byDisplaySubstring.matchAdapter(allAdapters), same(eth0));

      const byLabelSubstring = LaunchAdapterConfig(
        adapterName: 'wi-fi 6 (10.0.0.25)',
      );
      expect(byLabelSubstring.matchAdapter(allAdapters), same(wlan0));
    });

    test('skips NetworkAdapterInfo.all unless explicitly requested', () {
      const partialAll = LaunchAdapterConfig(adapterName: 'All Interfaces');
      expect(partialAll.matchAdapter(allAdapters), isNull);

      const wordAll = LaunchAdapterConfig(adapterName: 'all');
      expect(wordAll.matchAdapter(allAdapters), isNull);

      const substringInAll = LaunchAdapterConfig(adapterName: 'interfaces');
      expect(substringInAll.matchAdapter(allAdapters), isNull);

      const explicitAny = LaunchAdapterConfig(adapterName: 'ANY');
      expect(
        explicitAny.matchAdapter(allAdapters),
        same(NetworkAdapterInfo.all),
      );

      const explicitAllLabel = LaunchAdapterConfig(
        adapterName: '  all interfaces (any)  ',
      );
      expect(
        explicitAllLabel.matchAdapter(allAdapters),
        same(NetworkAdapterInfo.all),
      );

      const anycast = NetworkAdapterInfo(
        name: 'anycast0',
        displayName: 'Anycast Tunnel',
      );
      expect(
        explicitAny.matchAdapter([NetworkAdapterInfo.all, anycast]),
        same(anycast),
      );

      expect(explicitAny.matchAdapter([eth0, wlan0]), isNull);
    });

    test('Priority 3: returns null when neither IP nor name matches', () {
      const config = LaunchAdapterConfig(
        adapterIp: '203.0.113.42',
        adapterName: 'nonexistent0',
      );
      expect(config.matchAdapter(allAdapters), isNull);
    });
  });
}
