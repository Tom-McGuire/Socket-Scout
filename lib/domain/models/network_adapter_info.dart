class NetworkAdapterInfo {
  const NetworkAdapterInfo({
    required this.name,
    this.displayName,
    this.ipAddress,
    this.macAddress,
    this.isLoopback = false,
    this.isUp = true,
  });

  final String name;
  final String? displayName;
  final String? ipAddress;
  final String? macAddress;
  final bool isLoopback;
  final bool isUp;

  static const NetworkAdapterInfo all = NetworkAdapterInfo(
    name: 'any',
    displayName: 'All Interfaces (any)',
  );

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
