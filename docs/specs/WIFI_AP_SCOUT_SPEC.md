# Socket Scout: Wi-Fi Access Point (AP) Scout Mode Specification

## 1. Overview & Goal

Extend **Socket Scout** so that selecting a **Wi-Fi network adapter** in the Zone 2 Interface Selector automatically switches the workspace from **Wired Switch Port Listener (LLDP / CDP)** mode into **Wi-Fi Access Point (AP) Scout** mode.

Just as wired mode identifies the physical switch, port, and VLAN an Ethernet cable is plugged into, Wi-Fi mode identifies the exact physical **Access Point radio (BSSID)**, **SSID**, **Band / Channel**, **Signal Strength (RSSI)**, **PHY Link Speed**, **OUI Vendor**, **Neighboring APs**, and optional **Vendor-IE AP Hostname**—while syncing discovered APs into the Network Suite `SharedDeviceDatabase` (`shared_devices.db`).

---

## 2. Why Wi-Fi Works Differently from Wired LLDP / CDP

- Over Ethernet, managed switches transmit **LLDP (0x88CC)** / **CDP (0x2000)** directly to the client NIC.
- Over Wi-Fi, APs generally keep LLDP/CDP on their wired uplink port and do **not** forward those frames over the air to associated wireless clients.
- However, every OS exposes the associated **BSSID (AP Radio MAC)** and RF/link telemetry without requiring monitor mode or special hardware, and some enterprise APs (Cisco, Aruba, Ruckus, Ubiquiti) optionally include an **AP Name** inside 802.11 Beacon/Probe Response vendor-specific Information Elements (IEs).

---

## 3. Architecture & Implementation Plan

### 3.1 Adapter Type Detection (`NetworkAdapterInfo` & `NetworkAdapterService`)
1. Add `enum AdapterKind { wired, wifi, any, other }` (and `bool get isWifi => kind == AdapterKind.wifi;`) to `lib/domain/models/network_adapter_info.dart`.
2. Detect wireless interfaces in `NetworkAdapterService.getAvailableAdapters()`:
   - **Linux**: Check `/sys/class/net/<iface>/wireless` directory existence (or `iw dev` output), with fallback name heuristics (`wlan*`, `wlp*`, `wifi*`).
   - **Windows**: Cross-reference `netsh wlan show interfaces` (`Name` / `Description`) with fallback heuristics (`wi-fi`, `wlan`, `wireless`).
   - **macOS**: Map `networksetup -listallhardwareports` (`Hardware Port: Wi-Fi` / `AirPort`) to device `enX`.
3. Render `Icons.wifi` vs `Icons.settings_ethernet` in the Zone 2 dropdown based on `adapter.isWifi`.

### 3.2 Domain Model & Local Persistence (`WifiApDiscovery`)
Create `lib/domain/models/wifi_ap_discovery.dart`:
- Fields:
  - `id`, `timestamp`, `interfaceName`
  - `ssid`, `bssid` (normalized uppercase MAC via `SharedDevice.normalizeMac`)
  - `vendor` (resolved via `OuiLookup.lookupVendor(bssid)`)
  - `apHostname` (optional, parsed from enterprise vendor IEs when available)
  - `band` (`2.4 GHz`, `5 GHz`, `6 GHz`), `channel`, `frequencyMhz`, `channelWidthMhz`
  - `rssiDbm`, `noiseDbm`, `snrDb`, `signalPercent`
  - `txRateMbps`, `rxRateMbps`, `wifiStandard` (e.g. `Wi-Fi 6 (802.11ax)`), `securityType`
  - `neighbors` (`List<WifiNeighborAp>` — nearby BSSIDs, channels, RSSI for roaming diagnostics)
  - `rawTelemetry` (raw CLI/OS output for inspector view)
  - `isDemo` (`bool`, default `false`)
- Helpers:
  - `displayName` & `hasCustomName` resolving against `SharedDeviceDatabase.instance.getDeviceByMac(bssid)`.
- Add `wifi_ap_discoveries` SQLite table in `SwitchDatabaseService` (including `is_demo INTEGER DEFAULT 0`) so local Wi-Fi roaming history persists across restarts without ever leaking demo entries into `SharedDeviceDatabase`.

### 3.3 Cross-Platform Wi-Fi Telemetry Service (`WifiDiscoveryService`)
Create `lib/data/services/wifi/wifi_discovery_service.dart` using injectable `ProcessRunner` hooks for unit testing:
- **Linux**:
  - Link telemetry: `iw dev <iface> link` (BSSID, SSID, freq, signal, tx/rx bitrate) + optional `nmcli -t -f ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,SECURITY dev wifi list ifname <iface>`.
  - Neighbor scan & Vendor IEs: `iw dev <iface> scan` (extracts neighbor BSSIDs + RSSI + enterprise AP Name IEs where present).
- **Windows**:
  - Link telemetry: `netsh wlan show interfaces`.
  - Neighbor scan: `netsh wlan show networks mode=bssid`.
  - Detect Windows Location Services denial and surface an actionable OS permission banner in Tier 2.
- **macOS**:
  - Link telemetry: `wdutil info` / `system_profiler SPAirPortDataType`.
  - Detect redacted `<redacted>` BSSID/SSID and surface a macOS Location Services permission banner in Tier 2.
- **Polling & Roaming Detection**:
  - When active in Wi-Fi mode, poll link telemetry every 2–3 seconds and refresh neighbors periodically.
  - Update the live Hero AP Card in real time and append a new history row on initial association or whenever the **BSSID changes (roaming event)**.

### 3.4 `SharedDeviceDatabase` Integration & Context Menu
- Auto-sync genuine (`!isDemo`) connected APs into `SharedDeviceDatabase` with `deviceType: 'ap'` (or matching `DeviceCategory` key in `network_suite_shared`), resolved `vendor`, preserved `hasCustomName`, and structured `notes` (`SSID: ... | Band: ... | Ch: ... | Security: ...`).
- Never sync `isDemo == true` records into `SharedDeviceDatabase`.
- Add right-click context menu on the Hero AP Card and Wi-Fi history rows:
  - **Add / Edit in Device Library** (opens `EditDeviceDialog` prefilled with BSSID, AP name/SSID, `ap` category, OUI vendor, and RF notes).
  - Copy BSSID, Copy SSID, Copy Channel / Frequency, Copy RSSI, Copy All AP Details.

### 3.5 Automatic UI Mode Switching (5-Tier Layout)
When `vm.selectedAdapter?.isWifi == true`:
- **Tier 1 (Top Control Bar)**: Keep the 5-zone layout; Zone 3 button continues to start/stop monitoring, and Export supports Wi-Fi AP CSV/JSON/Report.
- **Tier 2 (Status Banner)**: Displays `SCOUTING WIFI ON <iface> • SSID: <ssid> • BSSID: <bssid> • RSSI: -54 dBm` (or OS Location permission guidance if blocked).
- **Tier 3 (Filter Toolbar)**: Switches protocol chips (`LLDP` / `CDP`) to Band filter chips (`ALL BANDS` / `2.4 GHz` / `5 GHz` / `6 GHz`).
- **Tier 4 (Primary Workspace)**:
  - **Hero AP Card**: Displays AP display name / BSSID, SSID, Signal Strength badge (`dBm` + quality color), Band/Channel/Width badge, Tx/Rx PHY rate, Wi-Fi Standard, Security, and `SHARED DB • ACCESS POINT` / `CUSTOM IDENTITY` badge.
  - **History / Roaming Table**: Timestamp, Band badge, AP Name / BSSID, SSID, Channel, RSSI, Link Speed, Vendor.
- **Tier 5 (Detail Inspector)**: Tabs adapt to `SUMMARY`, `NEIGHBOR APs`, `RAW TELEMETRY`, and `CLI COMMAND`.
- **Theme & Demo Walkthrough**: Uses dynamic `AppTheme.*` Light/Dark tokens and supports Wi-Fi demo presets (`isDemo: true`) in the guided walkthrough when a Wi-Fi adapter is active.

---

## 4. Verification Plan
1. Unit tests for Linux (`iw` / `nmcli`), Windows (`netsh wlan`), and macOS (`wdutil` / `system_profiler`) output parsers using fixture strings.
2. Unit tests for `AdapterKind.wifi` detection and `SharedDeviceDatabase` AP sync + `isDemo` isolation.
3. Widget tests verifying automatic UI switching between Wired (LLDP/CDP) and Wi-Fi (AP Scout) modes when changing the Zone 2 adapter dropdown, plus right-click prefilled `EditDeviceDialog` in Wi-Fi mode.
4. Run `flutter analyze` and `flutter test` with zero errors.
