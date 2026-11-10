# 🛠️ scripts — Raspberry Pi & UAV Setup Scripts

A collection of configuration, installation, and utility scripts for Linux systems (primarily **Raspberry Pi OS** / Debian).

---

## Module Overview

| Module | Purpose | Key Tech | Documentation |
|---|---|---|---|
| **[wifi-fix](wifi-fix/)** | Fixes Raspberry Pi headless access issues. Provides an instant direct Ethernet cable connection (`10.42.0.1` / mDNS) and prevents Wi-Fi sleep/dropouts. | NetworkManager, systemd timers, RFKill, iw | [wifi-fix/README.md](wifi-fix/README.md) |
| **[wfb-ng](wfb-ng/)** | Installer and tooling for a long-range bidirectional digital radio link (air ↔ ground station). Carries MAVLink, SSH tunnel, and RTSP/WebRTC video. | WFB-ng, RTL8812EU (raw 802.11 monitor injection), WebRTC, MAVLink | [wfb-ng/README.md](wfb-ng/README.md) |

---

## Quickstart

### 1. Clone the repository on your Raspberry Pi

```bash
git clone https://github.com/AGH-Drone-Engineering/scripts.git
cd scripts
```

### 2. Choose your module

- **Network configuration (Direct laptop cable access or reliable Wi-Fi):**
  ```bash
  cd wifi-fix
  chmod +x eth.sh wifi.sh
  sudo ./eth.sh     # direct Ethernet link (10.42.0.1 / mDNS fallback)
  sudo ./wifi.sh    # Wi-Fi hardening with automatic watchdog
  ```
  *(Details: [wifi-fix/README.md](wifi-fix/README.md))*

- **WFB-ng Radio Link setup (Drone / Ground Station):**
  > **Important safety note:** Both antennas **must** be connected to the module before powering up (transmitting without antennas destroys the RF power amplifier). If testing on a workbench via Raspberry Pi USB power, cap the power limit to prevent brownouts.

  ```bash
  cd wfb-ng

  # 1. On the drone (generates the encryption keypair):
  sudo ./install.sh --role air

  # 2. Ship the ground station key to the GS host over your local network:
  sudo ./scripts/wfb-keys-provision --role air <ground_station_ip_or_hostname>

  # 3. On the ground station (finds /etc/gs.key already present):
  sudo ./install.sh --role gs
  ```
  *(Details & `link.conf` tuning: [wfb-ng/README.md](wfb-ng/README.md) and [wfb-ng/docs/install.md](wfb-ng/docs/install.md))*
