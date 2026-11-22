# Socket Scout — Proposed Enhancements & Suite Integrations

---

## Issue 1: One-Click "Configure NIC for Subnet" Handoff to IP Profile Switcher

### Summary
Add a **"Configure NIC for this Subnet"** action on the **Identified Port Hero Card** that passes the discovered Switch Management IP / subnet context to **IP Profile Switcher (`IP-Switcher`)**.

### Motivation
When plugging into an unknown rack drop or lighting VLAN without a DHCP server, Socket Scout immediately decodes the switch's Management IP and Active VLAN ID/PVID via LLDP/CDP. Passing that subnet hint directly to `IP-Switcher` saves manually transcribing IP ranges when configuring a matching static interface address.

### Proposed Implementation
- Add an action button next to the Switch Management IP on the Identified Port Hero Card.
- Launch `IP-Switcher` (via CLI arguments `--suggest-subnet <ip/cidr> --vlan <id> --switch-name <hostname>` or loopback IPC).
- In `IP-Switcher`, either highlight matching existing saved presets or pre-populate a draft static IP profile in the same `/24` subnet with the VLAN tag filled in.

### Acceptance Criteria
- [ ] Button appears on the Hero Card whenever a valid IPv4 Management Address is decoded from LLDP or CDP.
- [ ] Clicking the button launches `IP-Switcher` with the target subnet and VLAN metadata pre-loaded.

---

## Issue 2: Link Speed & Duplex Mismatch Warning Badge

### Summary
Surface a prominent warning badge on the **Identified Port Hero Card** when IEEE 802.3 MAC/PHY auto-negotiation TLVs indicate a degraded link (e.g., `100Mbps Half-Duplex` or `10Mbps`) on a Gigabit-capable port.

### Motivation
Socket Scout already parses IEEE 802.3 MAC/PHY auto-negotiation and Power Via MDI (PoE) TLVs. Highlighting sub-gigabit or half-duplex negotiation immediately alerts field technicians to damaged patch cables or misconfigured switch ports at the wall drop.

### Acceptance Criteria
- [ ] Hero Card displays an amber warning badge when negotiated link speed is `< 1000 Mbps` or duplex is `Half`.
- [ ] Detail Inspector Summary tab clearly displays both Advertised Capabilities and Operational MAU Type.

---

## Issue 3: CLI `--open-pcap` Support for External Capture Handoffs

### Summary
Allow launching Socket Scout with a `--open-pcap <filepath>` CLI argument so **TShark Interface** can send captured files directly for offline LLDP/CDP extraction.

### Acceptance Criteria
- [ ] Passing `--open-pcap <path>` automatically runs the offline PCAP/PCAPNG import workflow on startup.
