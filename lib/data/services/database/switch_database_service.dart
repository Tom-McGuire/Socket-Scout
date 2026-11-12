import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../../domain/models/discovery_filter.dart';
import '../../../domain/models/switch_port_discovery.dart';

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
  }

  void close() {
    _db?.close();
    _db = null;
  }
}
