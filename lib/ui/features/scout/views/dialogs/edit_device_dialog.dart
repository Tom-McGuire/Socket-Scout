import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:socket_scout/domain/models/switch_port_discovery.dart';
import 'package:socket_scout/ui/theme/app_theme.dart';

/// Modal dialog for adding or editing a network device's identity and custom name
/// in the Network Suite Shared Device Library (`shared_devices.db`).
class EditDeviceDialog extends StatefulWidget {
  final SharedDevice? existing;
  final String? prefillMac;
  final String? prefillName;
  final String? prefillVendor;
  final String? prefillCategory;
  final String? prefillNotes;
  final VoidCallback? onSaved;

  const EditDeviceDialog({
    super.key,
    this.existing,
    this.prefillMac,
    this.prefillName,
    this.prefillVendor,
    this.prefillCategory,
    this.prefillNotes,
    this.onSaved,
  });

  /// Displays the edit dialog for an existing or manual device.
  static Future<bool?> show(
    BuildContext context, {
    SharedDevice? existing,
    String? prefillMac,
    String? prefillName,
    String? prefillVendor,
    String? prefillCategory,
    String? prefillNotes,
    VoidCallback? onSaved,
  }) async {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) {
        await SharedDeviceDatabase.instance.init();
      }
    } catch (e) {
      debugPrint('EditDeviceDialog init warning: $e');
    }

    if (!context.mounted) return null;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => EditDeviceDialog(
        existing: existing,
        prefillMac: prefillMac,
        prefillName: prefillName,
        prefillVendor: prefillVendor,
        prefillCategory: prefillCategory,
        prefillNotes: prefillNotes,
        onSaved: onSaved,
      ),
    );
  }

  /// Displays the edit dialog prefilled with data extracted from a discovered
  /// switch port frame (LLDP / CDP).
  static Future<bool?> showForDiscovery(
    BuildContext context,
    SwitchPortDiscovery discovery, {
    VoidCallback? onSaved,
  }) async {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) {
        await SharedDeviceDatabase.instance.init();
      }
    } catch (e) {
      debugPrint('EditDeviceDialog init warning: $e');
    }

    final rawMac = discovery.effectiveMacAddress ?? discovery.chassisId;
    String? normMac;
    if (rawMac != null && SharedDevice.isValidMac(rawMac)) {
      normMac = SharedDevice.normalizeMac(rawMac);
    }

    SharedDevice? existing;
    if (normMac != null && SharedDeviceDatabase.instance.isInitialized) {
      try {
        existing = SharedDeviceDatabase.instance.getDeviceByMac(normMac);
      } catch (_) {}
    }

    // Determine initial name
    final rawHostname = discovery.switchHostname.trim();
    final hasRealHostname = rawHostname.isNotEmpty &&
        !rawHostname.toLowerCase().startsWith('unknown');

    final initialName = (existing != null && existing.hasCustomName)
        ? existing.name
        : (hasRealHostname
            ? rawHostname
            : (existing?.name ?? (normMac != null ? 'Switch $normMac' : 'Switch')));

    // Determine vendor
    String? vendor = existing?.vendor;
    if (vendor == null || vendor.isEmpty || vendor.toLowerCase().contains('unknown')) {
      if (normMac != null) {
        try {
          vendor = OuiLookup.lookupVendor(normMac);
        } catch (_) {}
      }
      if (vendor == null || vendor.isEmpty || vendor.toLowerCase().contains('unknown')) {
        final modelLower = discovery.switchModel.toLowerCase();
        if (modelLower.contains('cisco')) {
          vendor = 'Cisco Systems, Inc.';
        } else if (modelLower.contains('netgear')) {
          vendor = 'Netgear Inc.';
        } else if (modelLower.contains('aruba') || modelLower.contains('procurve')) {
          vendor = 'Aruba / HPE';
        } else if (modelLower.contains('juniper')) {
          vendor = 'Juniper Networks, Inc.';
        } else if (modelLower.contains('mikrotik')) {
          vendor = 'MikroTik';
        } else if (discovery.protocol == DiscoveryProtocol.cdp) {
          vendor = 'Cisco Systems, Inc.';
        }
      }
    }

    // Determine notes
    String? notes = existing?.notes;
    if (notes == null || notes.isEmpty) {
      final notesParts = <String>[];
      if (discovery.managementIp != null && discovery.managementIp!.trim().isNotEmpty) {
        notesParts.add('Mgmt IP: ${discovery.managementIp!.trim()}');
      }
      if (discovery.portId.trim().isNotEmpty && !discovery.portId.toLowerCase().startsWith('unknown')) {
        final portDesc = (discovery.portDescription != null && discovery.portDescription!.trim().isNotEmpty)
            ? ' (${discovery.portDescription!.trim()})'
            : '';
        notesParts.add('Port: ${discovery.portId.trim()}$portDesc');
      }
      if (discovery.vlanId != null) {
        notesParts.add('VLAN: ${discovery.vlanId}');
      }
      if (discovery.switchModel.trim().isNotEmpty &&
          discovery.switchModel != 'Unknown Model' &&
          !discovery.switchModel.toLowerCase().startsWith('unknown')) {
        notesParts.add('Model: ${discovery.switchModel.trim()}');
      }
      notesParts.add('Via: ${discovery.protocol.label}');
      notes = notesParts.join(' | ');
    }

    if (!context.mounted) return null;
    final saved = await show(
      context,
      existing: existing,
      prefillMac: normMac ?? rawMac,
      prefillName: initialName,
      prefillVendor: vendor,
      prefillCategory: existing?.deviceType ?? 'switch',
      prefillNotes: notes,
      onSaved: onSaved,
    );

    return saved;
  }

  @override
  State<EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<EditDeviceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _macCtrl;
  late final TextEditingController _vendorCtrl;
  late final TextEditingController _notesCtrl;

  late String _selectedCategory;
  List<UnifiedDeviceCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    _macCtrl = TextEditingController(
      text: widget.existing?.macAddress ?? widget.prefillMac ?? '',
    );
    _nameCtrl = TextEditingController(
      text: widget.existing?.name ?? widget.prefillName ?? '',
    );
    _vendorCtrl = TextEditingController(
      text: widget.existing?.vendor ?? widget.prefillVendor ?? '',
    );
    _notesCtrl = TextEditingController(
      text: widget.existing?.notes ?? widget.prefillNotes ?? '',
    );

    _selectedCategory = widget.existing?.deviceType ?? widget.prefillCategory ?? 'switch';

    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        _categories = SharedDeviceDatabase.instance.getUnifiedCategories();
      }
    } catch (_) {}

    if (_categories.isNotEmpty && !_categories.any((c) => c.key == _selectedCategory)) {
      final match = _categories.where(
        (c) => c.label.toLowerCase() == _selectedCategory.toLowerCase(),
      );
      if (match.isNotEmpty) {
        _selectedCategory = match.first.key;
      }
    }
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _nameCtrl.dispose();
    _vendorCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final rawMac = _macCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final normMac = SharedDevice.isValidMac(rawMac) ? SharedDevice.normalizeMac(rawMac) : rawMac;

    final dev = SharedDevice(
      macAddress: normMac,
      name: name,
      deviceType: _selectedCategory,
      vendor: _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : null,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      sourceApp: 'socket_scout',
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      SharedDeviceDatabase.instance.upsertDevice(dev);
    } catch (e) {
      debugPrint('EditDeviceDialog upsert error: $e');
    }

    widget.onSaved?.call();
    Navigator.of(context).pop(true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Saved switch "$name" ($normMac) to Shared Device Library',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.hub_outlined, size: 18, color: Color(0xFF10B981)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditing ? 'Edit Device in Library' : 'Add Switch to Shared Library',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Identifies this hardware switch across all Network Suite apps',
                  style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // MAC Address
                const Text(
                  'MAC / CHASSIS ID',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _macCtrl,
                  enabled: !isEditing,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'AA:BB:CC:DD:EE:FF',
                    hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                    prefixIcon: Icon(Icons.fingerprint, size: 16, color: Colors.white54),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'MAC address is required';
                    }
                    if (!SharedDevice.isValidMac(val.trim())) {
                      return 'Invalid MAC format (e.g. 00:11:22:33:44:55)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Friendly Name
                const Text(
                  'FRIENDLY DEVICE NAME',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Core Switch Rack 1, Floor 2 Distribution',
                    hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                    prefixIcon: Icon(Icons.label_outline, size: 16, color: Colors.white54),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Device name cannot be empty';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // Device Category
                const Text(
                  'DEVICE CATEGORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.inputFill,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderInput),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _categories.any((c) => c.key == _selectedCategory)
                          ? _selectedCategory
                          : (_categories.isNotEmpty ? _categories.first.key : null),
                      dropdownColor: AppTheme.surfaceContainer,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedCategory = val);
                        }
                      },
                      items: _categories.map((c) {
                        return DropdownMenuItem<String>(
                          value: c.key,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(c.icon, size: 14, color: const Color(0xFF10B981)),
                              const SizedBox(width: 8),
                              Text(c.label),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Hardware Vendor
                const Text(
                  'HARDWARE VENDOR',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _vendorCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Cisco Systems, Netgear, Aruba',
                    hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                    prefixIcon: Icon(Icons.business_outlined, size: 16, color: Colors.white54),
                  ),
                ),
                const SizedBox(height: 12),

                // Notes
                const Text(
                  'NOTES & DISCOVERY METADATA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'e.g. Mgmt IP: 192.168.1.1 | Port: Gi1/0/1 | VLAN: 10',
                    hintStyle: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Save to Device Library'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          onPressed: _save,
        ),
      ],
    );
  }
}
