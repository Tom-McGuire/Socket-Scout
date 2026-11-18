import 'network_adapter_info.dart';

/// Parsed startup network adapter overrides passed via CLI arguments.
class LaunchAdapterConfig {
  /// Creates a [LaunchAdapterConfig] with optional [adapterIp] and
  /// [adapterName] CLI overrides.
  const LaunchAdapterConfig({this.adapterIp, this.adapterName});

  /// Parses `--adapter-ip` and `--adapter-name` from CLI [args].
  ///
  /// Supports both space-separated (`--flag value`) and equals-separated
  /// (`--flag=value`) forms. Unknown flags, trailing flags without values,
  /// and flag-looking next arguments starting with `--` are safely ignored.
  /// Values are trimmed and empty values normalize to `null`.
  factory LaunchAdapterConfig.fromArgs(List<String> args) {
    String? ip;
    String? name;

    for (var i = 0; i < args.length; i++) {
      final parsedIp = _parseFlag(args, i, '--adapter-ip');
      if (parsedIp != null) {
        ip = parsedIp.value;
        if (parsedIp.consumedNext) i++;
        continue;
      }

      final parsedName = _parseFlag(args, i, '--adapter-name');
      if (parsedName != null) {
        name = parsedName.value;
        if (parsedName.consumedNext) i++;
      }
    }

    return LaunchAdapterConfig(adapterIp: ip, adapterName: name);
  }

  /// IPv4 address passed via `--adapter-ip`.
  final String? adapterIp;

  /// Interface name, display name, or label passed via `--adapter-name`.
  final String? adapterName;

  /// Whether at least one non-empty adapter override is configured.
  bool get hasOverride =>
      (adapterIp != null && adapterIp!.trim().isNotEmpty) ||
      (adapterName != null && adapterName!.trim().isNotEmpty);

  /// Alias for [hasOverride] matching the suite launcher specification.
  bool get hasAdapterOverride => hasOverride;

  /// Finds the best matching adapter from [adapters] on initial startup.
  ///
  /// Matching priority:
  /// 1. Exact IPv4 address match (`adapter.ipAddress == targetIp`).
  /// 2. Case-insensitive name match against non-`any` adapters (exact match on
  ///    `name`/`displayName` first, then substring match on
  ///    `name`/`displayName`/`label`), falling back to `isAllInterfaces` only
  ///    when explicitly requested as `'any'` or `'all interfaces (any)'`.
  /// 3. Returns `null` if no override is configured or no adapter matches.
  NetworkAdapterInfo? matchAdapter(List<NetworkAdapterInfo> adapters) {
    if (!hasOverride || adapters.isEmpty) {
      return null;
    }

    final targetIp = adapterIp?.trim();
    if (targetIp != null && targetIp.isNotEmpty) {
      for (final adapter in adapters) {
        if (adapter.ipAddress == targetIp) {
          return adapter;
        }
      }
    }

    final rawName = adapterName?.trim();
    if (rawName == null || rawName.isEmpty) {
      return null;
    }
    final targetName = rawName.toLowerCase();

    final nonAllAdapters = adapters.where((a) => !a.isAllInterfaces).toList();

    for (final adapter in nonAllAdapters) {
      if (adapter.name.toLowerCase() == targetName ||
          adapter.displayName?.toLowerCase() == targetName) {
        return adapter;
      }
    }

    for (final adapter in nonAllAdapters) {
      if (adapter.name.toLowerCase().contains(targetName) ||
          (adapter.displayName?.toLowerCase().contains(targetName) ?? false) ||
          adapter.label.toLowerCase().contains(targetName)) {
        return adapter;
      }
    }

    if (targetName == 'any' || targetName == 'all interfaces (any)') {
      for (final adapter in adapters) {
        if (adapter.isAllInterfaces) {
          return adapter;
        }
      }
    }

    return null;
  }

  static ({String? value, bool consumedNext})? _parseFlag(
    List<String> args,
    int index,
    String flagName,
  ) {
    final arg = args[index];
    if (arg == flagName) {
      if (index + 1 < args.length) {
        final next = args[index + 1].trim();
        if (!next.startsWith('--')) {
          return (value: next.isEmpty ? null : next, consumedNext: true);
        }
      }
      return null;
    }

    final prefix = '$flagName=';
    if (arg.startsWith(prefix)) {
      final raw = arg.substring(prefix.length).trim();
      return (value: raw.isEmpty ? null : raw, consumedNext: false);
    }

    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchAdapterConfig &&
          runtimeType == other.runtimeType &&
          adapterIp == other.adapterIp &&
          adapterName == other.adapterName;

  @override
  int get hashCode => Object.hash(adapterIp, adapterName);

  @override
  String toString() =>
      'LaunchAdapterConfig(adapterIp: $adapterIp, adapterName: $adapterName)';
}
