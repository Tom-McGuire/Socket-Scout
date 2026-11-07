# Socket Scout (Switch Port Identifier — LLDP & CDP Listener)

A high-performance, dark-first desktop network diagnostic tool built with **Flutter Desktop**, native raw packet capture streaming, and an embedded **SQLite (`sqlite3`)** discovery engine.

Designed for network engineers, sysadmins, and field technicians who arrive at an equipment rack, patch panel, or wall drop and need to instantly know which physical switch, port, and VLAN their Ethernet cable is plugged into.

---

## The Problem

You arrive at a server cabinet, wiring closet, or office wall jack with an Ethernet drop and have no idea which physical switch or port your cable terminates on. Traditional discovery requires tracing cables through dense patch panels, carrying console roll-over cables, or logging into switch management web/CLI interfaces.

## The Solution

**Socket Scout** puts your selected network interface into listening mode for Layer 2 multicast discovery frames:
- **LLDP (Link Layer Discovery Protocol — IEEE 802.1AB standard)** on multicast address `01:80:C2:00:00:0E` (EtherType `0x88CC`).
- **CDP (Cisco Discovery Protocol v1 & v2)** on multicast address `01:00:0C:CC:CC:CC` (LLC/SNAP protocol `0x2000`).

Within seconds of connecting your cable, Socket Scout dissects incoming frames to reveal:
- **Switch Hostname & Model**: e.g., `SW-CAT9200-RACK04.corp.local`, `Cisco Catalyst 9200-24P`, `Netgear M4250 AV Line`, `Aruba CX 6200F`.
- **Physical Port / Interface**: e.g., `GigabitEthernet1/0/14`, `1/1/24`, `Port 7`.
- **Active VLAN ID / PVID**: e.g., `VLAN 20 (Corp-Data)`, `VLAN 100 (AV-Dante)`.
- **Switch Management IP Address**: IPv4 and IPv6 addresses for direct management access.
- **Port Description & Hold-Time (TTL)**: Port labels (e.g. `Access Drop Room 204B`) and advertisement freshness countdown.
- **Capabilities & Hardware Metadata**: Switch, Router, WLAN AP, Bridge status, link aggregation (LAG), duplex, MTU, and Power-over-Ethernet (PoE PSE class and wattage).

---

## Key Features

- **Real-Time Layer 2 Multicast Engine**:
  - Unbuffered streaming capture via background `tcpdump`, `dumpcap`, or `tshark` child processes with optimized BPF filter:
    ```text
    ether proto 0x88cc or (ether[12:2] <= 1500 and ether[20:2] == 0x2000)
    ```
  - Incremental binary stream decoder extracting raw Ethernet frames directly into protocol dissectors.
- **Dedicated Protocol Dissectors**:
  - **IEEE 802.1AB LLDP Dissector**: Chassis ID (MAC/network/local), Port ID, TTL, System Name, System Description, Capabilities bitmap, Management Address, IEEE 802.1 Port VLAN ID (PVID) & VLAN Name, IEEE 802.3 MAC/PHY auto-negotiation, Power Via MDI (PoE), Link Aggregation, and Maximum Frame Size (MTU).
  - **Cisco CDP Dissector**: Device ID, IPv4/IPv6 Addresses, Port ID, Capabilities (Router, Switch, IGMP, Host), Software Version, Platform, Native VLAN, VTP Management Domain, Duplex, and Power Consumption (mW).
- **Wire-Accurate Demo Simulation Mode**:
  - Built-in binary frame generator producing authentic frames for Cisco Catalyst 9200 (both CDP and LLDP), Netgear M4250 ProAV, Aruba CX 6200F, and Juniper EX4300 switches for immediate testing and demonstration without physical switch hardware.
- **Offline PCAP / PCAPNG Import**:
  - Import `.pcap`, `.pcapng`, or `.cap` capture files directly into the application for offline dissection and troubleshooting.
- **SQLite Discovery History & Persistence**:
  - Discoveries are automatically persisted into an embedded SQLite database (`socket_scout.db`), enabling searchable historical logs of every wall drop and rack port tested across a facility.
- **5-Tier Desktop Screen Architecture**:
  1. **Top Control Bar**: Network interface selector, Start/Stop toggle, Demo Presets, PCAP import, CSV/JSON/Report export, and Clear history.
  2. **Global Status & Alert Banner**: Live pulsing green capture indicator with elapsed timer and frame counter, plus permission elevation diagnostic tips (`sudo setcap`).
  3. **Filter & Triage Toolbar**: High-density search bar, protocol toggle chips (`ALL`, `LLDP`, `CDP`), and one-click filter clear.
  4. **Primary Workspace**:
     - *Identified Port Hero Card*: Prominent, high-contrast dashboard displaying switch hostname, model, physical port badge, active VLAN ID, management IP with 1-click copy, and PoE status.
     - *High-Density Virtualized Data Table*: Virtualized scrolling table with resizable columns and selected row highlights.
  5. **4-Mode Collapsible Detail Inspector & Status Bar**:
     - *Summary Tab*: Key-value technical badges for quick reference.
     - *Raw TLV Tree Tab*: Hierarchical view showing TLV Type codes, names, lengths, and decoded descriptions.
     - *Hex / ASCII Inspector*: 16-bytes-per-line Wireshark-style canonical hex dump with ASCII sidebar.
     - *CLI Command Preview*: Generated terminal execution command with 1-click copy.
     - *Persistent Status Bar*: Ingress adapter, discovery counters, and live listener status.
- **Graceful Lifecycle Management**:
  - Intercepts `WidgetsBindingObserver.didRequestAppExit` to guarantee immediate SIGTERM/SIGKILL termination of capture subprocesses on window close, preventing zombie processes or locked network sockets.
- **Export Capabilities**:
  - Export discovery logs to CSV, structured JSON, or formatted plain-text Engineering Reports suitable for pasting into trouble tickets and network documentation.

---

## Architecture

Socket Scout follows a strict MVVM pattern with separation of concerns:

```
lib/
├── data/
│   ├── repositories/
│   │   └── switch_discovery_repository.dart  # Data coordination, cache, and event streams
│   └── services/
│       ├── capture/
│       │   └── capture_service.dart          # Subprocess launcher (tcpdump/tshark/dumpcap)
│       ├── database/
│       │   └── switch_database_service.dart  # SQLite persistence via sqlite3 & sqlite3_flutter_libs
│       ├── export/
│       │   └── export_service.dart            # CSV, JSON, and Engineering Report generator
│       ├── generator/
│       │   └── demo_l2_generator.dart        # Wire-accurate Cisco, Netgear, Aruba & Juniper frames
│       ├── network/
│       │   └── network_adapter_service.dart  # Network interface discovery
│       └── parser/
│           ├── cdp_dissector.dart            # Cisco Discovery Protocol v1/v2 binary parser
│           ├── lldp_dissector.dart           # IEEE 802.1AB LLDP binary parser
│           └── pcap_binary_reader.dart       # Streaming & file PCAP/PCAPNG reader
├── domain/
│   └── models/
│       ├── discovery_filter.dart             # Filter criteria & search predicate
│       ├── network_adapter_info.dart         # Network interface model
│       └── switch_port_discovery.dart        # Immutable switch discovery & TLV models
├── ui/
│   ├── features/
│   │   └── scout/
│   │       ├── view_models/
│   │       │   └── socket_scout_view_model.dart # ChangeNotifier UI state & event handling
│   │       └── views/
│   │           ├── socket_scout_screen.dart     # Root screen with WidgetsBindingObserver
│   │           ├── tier1_top_control_bar.dart   # Tier 1: App header & controls
│   │           ├── tier2_status_banner.dart     # Tier 2: Live listener & error banners
│   │           ├── tier3_filter_toolbar.dart    # Tier 3: Search & protocol filter chips
│   │           ├── tier4_primary_workspace.dart # Tier 4: Hero card & virtualized table
│   │           └── tier5_detail_inspector.dart  # Tier 5: Inspector tabs & status bar
│   └── theme/
│       └── app_theme.dart                    # Material 3 dark slate theme tokens
└── main.dart                                 # App entrypoint & MultiProvider setup
```

---

## Building and Running

### Prerequisites

- **Flutter SDK**: 3.13+ (Channel `stable`)
- **Desktop Build Toolchains**:
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`, `libsqlite3-dev`
  - **Windows**: Visual Studio 2022 (with Desktop development with C++)
  - **macOS**: Xcode 15+ and Command Line Tools
- **Packet Capture Tool (Optional for live capture, not needed for demo mode)**:
  - Linux/macOS: `tcpdump`, `dumpcap`, or `tshark`
  - Windows: Npcap or Wireshark (provides `dumpcap.exe` or `tshark.exe`)

### Linux Capture Permissions
To allow capture without running the full application as root:
```bash
sudo setcap cap_net_raw,cap_net_admin=eip $(which tcpdump)
```

### Install Dependencies
```bash
flutter pub get
```

### Run in Debug Mode
```bash
# Linux
flutter run -d linux

# Windows
flutter run -d windows

# macOS
flutter run -d macos
```

### Run Automated Tests
```bash
flutter test
```

### Run Static Analysis
```bash
flutter analyze
```

### Build Release Binaries
```bash
# Linux (Tarball created in build/linux/x64/release/bundle)
flutter build linux --release

# Windows (Zip created from build/windows/x64/runner/Release)
flutter build windows --release

# macOS (App bundle in build/macos/Build/Products/Release)
flutter build macos --release
```

---

## CI/CD & Automated Releases

Socket Scout includes a universal GitHub Actions workflow ([`.github/workflows/release.yml`](.github/workflows/release.yml)) that automatically compiles and packages native desktop binaries for Windows (`x64`), Linux (`x64`), and macOS (`Universal`):

To trigger an automated release build:
```bash
git tag v0.5.0.Beta
git push origin v0.5.0.Beta
```
The workflow will compile the application in parallel across all three operating systems and upload the packaged archives to GitHub Releases.

---

## License

This project is licensed under the [MIT License](LICENSE) - see the [LICENSE](LICENSE) file for details.
