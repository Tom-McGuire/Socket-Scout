import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../../domain/models/discovery_filter.dart';
import '../../../domain/models/switch_port_discovery.dart';
import '../../../domain/models/wifi_ap_discovery.dart';

class SwitchDatabaseService {
  Database? _db;

  Future<void> init({String? customPath}) async {
    if (_db != null) return;

    final String dbPath;
    if (customPath != null) {
      dbPath = customPath;
    } else {
      final appDir = await getApplicationSupportDirectory();
      dbPath = p.join(appDir.path, 'socket_scout.db');
    }

    final file = File(dbPath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    _db = sqlite3.open(dbPath);
    _createTables();
  }

  /// In-memory database initialization for unit testing
  void initInMemory() {
    _db = sqlite3.openInMemory();
    _createTables();
  }

  void _createTables() {
    _db!.execute('''
      CREATE TABLE IF NOT EXISTS switch_discoveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp_ms INTEGER NOT NULL,
        protocol TEXT NOT NULL,
        switch_hostname TEXT NOT NULL,
        port_id TEXT NOT NULL,
        switch_model TEXT,
        port_description TEXT,
        vlan_id INTEGER,
        vlan_name TEXT,
        management_ip TEXT,
        chassis_id TEXT,
        ttl INTEGER,
        capabilities TEXT,
        power_mdi TEXT,
        link_aggregation TEXT,
        mtu INTEGER,
        duplex TEXT,
        vtp_domain TEXT,
        raw_tlvs TEXT,
        raw_hex TEXT,
        interface_name TEXT,
        is_demo INTEGER DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_discoveries_timestamp ON switch_discoveries(timestamp_ms DESC);
      CREATE INDEX IF NOT EXISTS idx_discoveries_hostname ON switch_discoveries(switch_hostname);
    ''');
    try {
      _db!.execute('ALTER TABLE switch_discoveries ADD COLUMN is_demo INTEGER DEFAULT 0;');
    } catch (_) {}

    _db!.execute('''
      CREATE TABLE IF NOT EXISTS wifi_ap_discoveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp INTEGER NOT NULL,
        interface_name TEXT NOT NULL,
        ssid TEXT NOT NULL,
        bssid TEXT NOT NULL,
        vendor TEXT,
        ap_hostname TEXT,
        band TEXT,
        channel INTEGER,
        frequency_mhz INTEGER,
        channel_width_mhz INTEGER,
        rssi_dbm INTEGER,
        noise_dbm INTEGER,
        snr_db INTEGER,
        signal_percent INTEGER,
        tx_rate_mbps REAL,
        rx_rate_mbps REAL,
        wifi_standard TEXT,
        security_type TEXT,
        neighbors_json TEXT,
        raw_telemetry TEXT,
        is_demo INTEGER DEFAULT 0
      );
      CREATE INDEX IF NOT EXISTS idx_wifi_timestamp ON wifi_ap_discoveries(timestamp DESC);
      CREATE INDEX IF NOT EXISTS idx_wifi_bssid ON wifi_ap_discoveries(bssid);
    ''');
  }

  int insertDiscovery(SwitchPortDiscovery discovery) {
    if (_db == null) return -1;

    final stmt = _db!.prepare('''
      INSERT INTO switch_discoveries (
        timestamp_ms, protocol, switch_hostname, port_id, switch_model,
        port_description, vlan_id, vlan_name, management_ip, chassis_id,
        ttl, capabilities, power_mdi, link_aggregation, mtu,
        duplex, vtp_domain, raw_tlvs, raw_hex, interface_name, is_demo
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');

    try {
      final map = discovery.toMap();
      stmt.execute([
        map['timestamp_ms'],
        map['protocol'],
        map['switch_hostname'],
        map['port_id'],
        map['switch_model'],
        map['port_description'],
        map['vlan_id'],
        map['vlan_name'],
        map['management_ip'],
        map['chassis_id'],
        map['ttl'],
        map['capabilities'],
        map['power_mdi'],
        map['link_aggregation'],
        map['mtu'],
        map['duplex'],
        map['vtp_domain'],
        map['raw_tlvs'],
        map['raw_hex'],
        map['interface_name'],
        map['is_demo'] ?? 0,
      ]);
      return _db!.lastInsertRowId;
    } catch (e) {
      debugPrint('insertDiscovery error: $e');
      return -1;
    } finally {
      stmt.close();
    }
  }

  List<SwitchPortDiscovery> getDiscoveries({
    int limit = 200,
    int offset = 0,
    DiscoveryFilter? filter,
  }) {
    if (_db == null) return [];

    final whereClauses = <String>[];
    final params = <Object?>[];

    if (filter != null) {
      if (filter.protocol != null) {
        whereClauses.add('protocol = ?');
        params.add(filter.protocol!.name);
      }
      if (filter.vlanId != null) {
        whereClauses.add('vlan_id = ?');
        params.add(filter.vlanId);
      }
      if (filter.searchQuery.trim().isNotEmpty) {
        final query = '%${filter.searchQuery.trim().toLowerCase()}%';
        whereClauses.add('''
          (LOWER(switch_hostname) LIKE ? OR
           LOWER(port_id) LIKE ? OR
           LOWER(switch_model) LIKE ? OR
           LOWER(management_ip) LIKE ? OR
           LOWER(chassis_id) LIKE ?)
        ''');
        params.addAll([query, query, query, query, query]);
      }
    }

    final whereSql = whereClauses.isNotEmpty
        ? 'WHERE ${whereClauses.join(' AND ')}'
        : '';

    final sortCol = switch (filter?.sortBy) {
      'hostname' => 'switch_hostname',
      'port' => 'port_id',
      'vlan' => 'vlan_id',
      _ => 'timestamp_ms',
    };
    final sortDir = (filter?.sortAscending ?? false) ? 'ASC' : 'DESC';

    final sql = '''
      SELECT * FROM switch_discoveries
      $whereSql
      ORDER BY $sortCol $sortDir
      LIMIT ? OFFSET ?
    ''';
    params.add(limit);
    params.add(offset);

    try {
      final rows = _db!.select(sql, params);
      return rows.map((row) => SwitchPortDiscovery.fromMap(row)).toList();
    } catch (e) {
      debugPrint('getDiscoveries error: $e');
      return [];
    }
  }

  int countDiscoveries({DiscoveryFilter? filter}) {
    if (_db == null) return 0;
    try {
      final rows = _db!.select('SELECT COUNT(*) as count FROM switch_discoveries');
      return rows.first['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void clearAll() {
    _db?.execute('DELETE FROM switch_discoveries');
    _db?.execute('DELETE FROM wifi_ap_discoveries');
  }

  int insertWifiDiscovery(WifiApDiscovery discovery) {
    if (_db == null) return -1;

    final stmt = _db!.prepare('''
      INSERT INTO wifi_ap_discoveries (
        timestamp, interface_name, ssid, bssid, vendor, ap_hostname,
        band, channel, frequency_mhz, channel_width_mhz,
        rssi_dbm, noise_dbm, snr_db, signal_percent,
        tx_rate_mbps, rx_rate_mbps, wifi_standard, security_type,
        neighbors_json, raw_telemetry, is_demo
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');

    try {
      final map = discovery.toMap();
      stmt.execute([
        map['timestamp'],
        map['interface_name'],
        map['ssid'],
        map['bssid'],
        map['vendor'],
        map['ap_hostname'],
        map['band'],
        map['channel'],
        map['frequency_mhz'],
        map['channel_width_mhz'],
        map['rssi_dbm'],
        map['noise_dbm'],
        map['snr_db'],
        map['signal_percent'],
        map['tx_rate_mbps'],
        map['rx_rate_mbps'],
        map['wifi_standard'],
        map['security_type'],
        map['neighbors_json'],
        map['raw_telemetry'],
        map['is_demo'] ?? 0,
      ]);
      return _db!.lastInsertRowId;
    } catch (e) {
      debugPrint('insertWifiDiscovery error: $e');
      return -1;
    } finally {
      stmt.close();
    }
  }

  List<WifiApDiscovery> getWifiDiscoveries({
    int limit = 200,
    int offset = 0,
  }) {
    if (_db == null) return [];

    try {
      final rows = _db!.select(
        '''
        SELECT * FROM wifi_ap_discoveries
        ORDER BY timestamp DESC
        LIMIT ? OFFSET ?
        ''',
        [limit, offset],
      );
      return rows.map((row) => WifiApDiscovery.fromMap(row)).toList();
    } catch (e) {
      debugPrint('getWifiDiscoveries error: $e');
      return [];
    }
  }

  int countWifiDiscoveries() {
    if (_db == null) return 0;
    try {
      final rows =
          _db!.select('SELECT COUNT(*) as count FROM wifi_ap_discoveries');
      return rows.first['count'] as int? ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void clearWifiDiscoveries() {
    _db?.execute('DELETE FROM wifi_ap_discoveries');
  }

  void close() {
    _db?.close();
    _db = null;
  }
}
