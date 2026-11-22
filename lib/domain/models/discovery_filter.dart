import 'switch_port_discovery.dart';
import 'wifi_ap_discovery.dart';

class DiscoveryFilter {
  const DiscoveryFilter({
    this.searchQuery = '',
    this.protocol,
    this.vlanId,
    this.wifiBand,
    this.sortBy = 'time',
    this.sortAscending = false,
  });

  final String searchQuery;
  final DiscoveryProtocol? protocol;
  final int? vlanId;
  final WifiBand? wifiBand;
  final String sortBy;
  final bool sortAscending;

  bool get isActive =>
      searchQuery.trim().isNotEmpty ||
      protocol != null ||
      vlanId != null ||
      wifiBand != null;

  DiscoveryFilter copyWith({
    String? searchQuery,
    DiscoveryProtocol? protocol,
    bool clearProtocol = false,
    int? vlanId,
    bool clearVlan = false,
    WifiBand? wifiBand,
    bool clearWifiBand = false,
    String? sortBy,
    bool? sortAscending,
  }) {
    return DiscoveryFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      protocol: clearProtocol ? null : (protocol ?? this.protocol),
      vlanId: clearVlan ? null : (vlanId ?? this.vlanId),
      wifiBand: clearWifiBand ? null : (wifiBand ?? this.wifiBand),
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

  bool matchesWifi(WifiApDiscovery item) {
    if (wifiBand != null && item.band != wifiBand) {
      return false;
    }

    final query = searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final matchesDisplay = item.displayName.toLowerCase().contains(query);
      final matchesSsid = item.ssid.toLowerCase().contains(query);
      final matchesBssid = item.normalizedBssid.toLowerCase().contains(query);
      final matchesVendor = item.resolvedVendor?.toLowerCase().contains(query) ?? false;
      final matchesApHost = item.apHostname?.toLowerCase().contains(query) ?? false;
      final matchesBand = item.band.label.toLowerCase().contains(query);
      final matchesChannel = item.channel?.toString().contains(query) ?? false;
      final matchesSecurity = item.securityType?.toLowerCase().contains(query) ?? false;

      if (!matchesDisplay &&
          !matchesSsid &&
          !matchesBssid &&
          !matchesVendor &&
          !matchesApHost &&
          !matchesBand &&
          !matchesChannel &&
          !matchesSecurity) {
        return false;
      }
    }

    return true;
  }
}
