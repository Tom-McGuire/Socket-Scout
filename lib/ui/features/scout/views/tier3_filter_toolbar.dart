import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/switch_port_discovery.dart';
import '../../../theme/app_theme.dart';
import '../view_models/socket_scout_view_model.dart';

class Tier3FilterToolbar extends StatefulWidget {
  const Tier3FilterToolbar({super.key});

  @override
  State<Tier3FilterToolbar> createState() => _Tier3FilterToolbarState();
}

class _Tier3FilterToolbarState extends State<Tier3FilterToolbar> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SocketScoutViewModel>();

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Search Input Field (height 32px)
          SizedBox(
            width: 280,
            height: 32,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Filter switches, ports, VLANs, IPs...',
                hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white54),
                prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          vm.setSearchQuery('');
                        },
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
              onChanged: (val) => vm.setSearchQuery(val),
            ),
          ),

          const SizedBox(width: 16),

          // Protocol Filter Chips
          _buildProtocolChip(
            context,
            label: 'ALL PROTOCOLS',
            isSelected: vm.filter.protocol == null,
            onTap: () => vm.setProtocolFilter(null),
          ),
          const SizedBox(width: 6),
          _buildProtocolChip(
            context,
            label: 'LLDP',
            isSelected: vm.filter.protocol == DiscoveryProtocol.lldp,
            accentColor: const Color(0xFF38BDF8),
            onTap: () => vm.setProtocolFilter(
              vm.filter.protocol == DiscoveryProtocol.lldp ? null : DiscoveryProtocol.lldp,
            ),
          ),
          const SizedBox(width: 6),
          _buildProtocolChip(
            context,
            label: 'CDP',
            isSelected: vm.filter.protocol == DiscoveryProtocol.cdp,
            accentColor: const Color(0xFFA78BFA),
            onTap: () => vm.setProtocolFilter(
              vm.filter.protocol == DiscoveryProtocol.cdp ? null : DiscoveryProtocol.cdp,
            ),
          ),

          const Spacer(),

          // Clear All Filters Chip
          if (vm.filter.isActive)
            ActionChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppTheme.inputFill,
              side: const BorderSide(color: AppTheme.warning),
              avatar: const Icon(Icons.filter_alt_off, size: 13, color: AppTheme.warning),
              label: const Text(
                'Clear All Filters',
                style: TextStyle(fontSize: 11, color: AppTheme.warning, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                _searchController.clear();
                vm.clearFilters();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProtocolChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    Color accentColor = AppTheme.primaryAccent,
    required VoidCallback onTap,
  }) {
    final bgColor = isSelected ? accentColor.withValues(alpha: 0.18) : AppTheme.inputFill;
    final borderColor = isSelected ? accentColor : AppTheme.border;
    final textColor = isSelected ? accentColor : Colors.white70;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
