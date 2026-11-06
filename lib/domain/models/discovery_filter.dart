import 'switch_port_discovery.dart';

class DiscoveryFilter {
  const DiscoveryFilter({
    this.searchQuery = '',
    this.protocol,
    this.vlanId,
    this.sortBy = 'time',
    this.sortAscending = false,
  });

  final String searchQuery;
  final DiscoveryProtocol? protocol;
  final int? vlanId;
  final String sortBy;
  final bool sortAscending;

  bool get isActive =>
      searchQuery.trim().isNotEmpty || protocol != null || vlanId != null;

  DiscoveryFilter copyWith({
    String? searchQuery,
    DiscoveryProtocol? protocol,
    bool clearProtocol = false,
    int? vlanId,
    bool clearVlan = false,
    String? sortBy,
    bool? sortAscending,
  }) {
    return DiscoveryFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      protocol: clearProtocol ? null : (protocol ?? this.protocol),
      vlanId: clearVlan ? null : (vlanId ?? this.vlanId),
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }

  bool matches(SwitchPortDiscovery item) {
    if (protocol != null && item.protocol != protocol) {
      return false;
    }

    if (vlanId != null && item.vlanId != vlanId) {
      return false;
    }

    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final matchesHostname = item.switchHostname.toLowerCase().contains(query);
      final matchesPort = item.portId.toLowerCase().contains(query);
      final matchesModel = item.switchModel.toLowerCase().contains(query);
      final matchesIp = item.managementIp?.toLowerCase().contains(query) ?? false;
      final matchesChassis = item.chassisId?.toLowerCase().contains(query) ?? false;
      final matchesVlan = item.vlanId?.toString().contains(query) ?? false;
      final matchesPortDesc = item.portDescription?.toLowerCase().contains(query) ?? false;

      if (!matchesHostname &&
          !matchesPort &&
          !matchesModel &&
          !matchesIp &&
          !matchesChassis &&
          !matchesVlan &&
          !matchesPortDesc) {
        return false;
      }
    }

    return true;
  }
}
