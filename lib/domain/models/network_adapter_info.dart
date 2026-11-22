enum AdapterKind {
  wired,
  wifi,
  any,
  other;

  String get label {
    switch (this) {
      case AdapterKind.wired:
        return 'Wired';
      case AdapterKind.wifi:
        return 'Wi-Fi';
      case AdapterKind.any:
        return 'All Interfaces';
      case AdapterKind.other:
        return 'Other';
    }
  }
}

class NetworkAdapterInfo {
  const NetworkAdapterInfo({
    required this.name,
    this.displayName,
    this.ipAddress,
    this.macAddress,
    this.isLoopback = false,
    this.isUp = true,
    this.kind = AdapterKind.wired,
  });

  final String name;
  final String? displayName;
  final String? ipAddress;
  final String? macAddress;
  final bool isLoopback;
  final bool isUp;
  final AdapterKind kind;

  static const NetworkAdapterInfo all = NetworkAdapterInfo(
    name: 'any',
    displayName: 'All Interfaces (any)',
    kind: AdapterKind.any,
  );

  bool get isAllInterfaces => name == 'any' || kind == AdapterKind.any;
  bool get isWifi => kind == AdapterKind.wifi;

  NetworkAdapterInfo copyWith({
    String? name,
    String? displayName,
    String? ipAddress,
    String? macAddress,
    bool? isLoopback,
    bool? isUp,
    AdapterKind? kind,
  }) {
    return NetworkAdapterInfo(
      name: name ?? this.name,
      displayName: displayName ?? this.displayName,
      ipAddress: ipAddress ?? this.ipAddress,
      macAddress: macAddress ?? this.macAddress,
      isLoopback: isLoopback ?? this.isLoopback,
      isUp: isUp ?? this.isUp,
      kind: kind ?? this.kind,
    );
  }

  String get label {
    final display = displayName ?? name;
    if (ipAddress != null && ipAddress!.isNotEmpty) {
      return '$display ($ipAddress)';
    }
    return display;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkAdapterInfo &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => label;
}
