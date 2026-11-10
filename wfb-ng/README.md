# IMAV antenna link — setup

A long-range digital radio link between a drone and a ground station, built on
two [BL-M8812EU2](https://openfpv.com.ua/en/hardware/net-cards/rtl8812eu)
(RTL8812EU chipset) modules mounted on this repo's carrier board, running
[wfb-ng](https://github.com/svpcom/wfb-ng). Carries SSH and MAVLink, plus an
optional video stage — an IP camera over RTSP ships today, pluggable for
USB/HDMI or a Pi camera later (`docs/integration.md`).

This is not a WiFi network. The cards run in monitor mode and inject raw
802.11 frames — no AP, no association, no DHCP. wfb-ng multiplexes
everything into a few fixed streams that show up on both ends as plain UDP
sockets on localhost, plus an IP tunnel for anything else.

```
   drone (air)                                    ground station (gs)
 ┌───────────────┐        5 GHz, monitor mode      ┌───────────────┐
 │ Raspberry Pi   │◄══════════════════════════════►│ Raspberry Pi   │
 │ + BL-M8812EU2  │        wfb-ng, ch 165           │ + BL-M8812EU2  │
 │                │                                 │                │
 │ FC ─UART─ Pi   │── MAVLink stream ──────────────►│ Pi ─UDP:14550─ QGC
 │ sshd           │◄── IP tunnel (drone-wfb) ──────►│ gs-wfb tunnel ─ ssh
 └───────────────┘                                 └───────────────┘
   10.5.0.2/24                                        10.5.0.1/24
```

## Before you power anything on

- **Antennas:** Both antennas must be fitted before transmitting, always. This module
  has no antenna-lost protection — transmitting without one destroys the
  power amplifier, with no warning from the hardware.
- **Power supply configurations:**
  - **Bench testing (Raspberry Pi USB power):** A Pi's USB port cannot supply the power
    demanded by the module at full power. For bench testing over USB-C, override settings
    in `link.conf.local`:
    ```ini
    POWER_SOURCE=usb-pi
    WIFI_TXPOWER=500
    ```
  - **Field operations (External BEC / Battery — Default):** When powered from the carrier
    board's external leads, `link.conf` defaults to `POWER_SOURCE=external` and `WIFI_TXPOWER=1500`.
- **Regulatory:** Channel 165 (5825 MHz) is not EU-harmonised for general RLAN use.
  `WIFI_REGION` only lifts the driver's own restrictions — it does not
  make the transmission legal. See `docs/tuning.md` before transmitting
  at real power.

## Quickstart

```sh
# 1. On the drone's Pi. Generates the matched keypair for both ends:
git clone <this-repo-url> && cd scripts/wfb-ng
sudo ./install.sh --role air

# 2. Still on the drone's Pi. Provisions the GS key to the ground station over SSH:
sudo ./scripts/wfb-keys-provision --role air <ground-station-host>

# 3. On the ground station's Pi. Finds /etc/gs.key already in place:
git clone <this-repo-url> && cd scripts/wfb-ng
sudo ./install.sh --role gs

# 4. Verify link health on either machine:
sudo ./scripts/wfb-doctor
```

Full walkthrough: **[docs/install.md](docs/install.md)**.

## Using the link

### 1. MAVLink / Telemetry
- **Ground Station:** `QGC_HOST=listen` is enabled by default in `link.conf`, which listens on UDP port `14550`.
- **GCS (QGroundControl / Mission Planner):** Add a UDP connection and set **Target Host** to the ground station's IP (e.g. `192.168.127.12` or `ground-station.local`), port `14550`.
- Telemetry connects without needing to reconfigure the ground station when your laptop IP changes. (To push directly to a fixed IP instead, set `QGC_HOST=<ip>` in `link.conf.local`).

### 2. Video / Camera
- **Drone (Camera Network Setup):** An IP camera (e.g. on subnet `192.168.144.x` like SIYI at `192.168.144.25`) requires the drone's Ethernet port (`eth0` or `eth1`) to have a matching static IP:
  ```sh
  # Quick test:
  sudo ip addr flush dev eth1 && sudo ip link set eth1 up && sudo ip addr add 192.168.144.40/24 dev eth1

  # Or persistent via NetworkManager (survives reboot):
  sudo nmcli con add type ethernet ifname eth1 con-name camera-net ipv4.method manual ipv4.addresses 192.168.144.40/24 connection.autoconnect yes
  ```
- **Ground Station (Viewing):**
  - **In any Web Browser (WebRTC — ultra-low latency ~50 ms):**
    Install the bridge once on GS (`sudo ./scripts/wfb-webrtc-install`), then open:
    `http://<ground-station-ip>:8889/wfb`
  - **In VLC / QGroundControl:**
    Connect to RTSP stream: `rtsp://<ground-station-ip>:8554/wfb`.

### 3. SSH Management
- A point-to-point IP tunnel connects both Pis over the 5 GHz radio link:
  - **Drone (`air`):** `10.5.0.2` (`ssh <user>@10.5.0.2`)
  - **Ground Station (`gs`):** `10.5.0.1` (`ssh <user>@10.5.0.1`)
- *Note:* mDNS (`.local` hostnames) does not resolve across point-to-point tunnels; always use the static tunnel IPs `10.5.0.1` and `10.5.0.2`.

## What to read next

| Need to... | Read |
|---|---|
| Install from a clean image, step by step | [docs/install.md](docs/install.md) |
| Run day-to-day: pre-flight check, `wfb-cli`, changing a setting, upgrades, uninstalling | [docs/operations.md](docs/operations.md) |
| Wire up SSH, MAVLink, or a camera | [docs/integration.md](docs/integration.md) |
| Diagnose a symptom | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Choose channel/bandwidth/power/antennas, or check the legal picture | [docs/tuning.md](docs/tuning.md) |

## Repo layout

| Path | What |
|---|---|
| `link.conf` | The one file you edit — SETTINGS section: channel, power, MAVLink, camera |
| `link.conf.local.example` | Copy to `link.conf.local` for host-specific overrides (gitignored) |
| `VERSIONS` | Pinned driver/wfb-ng versions |
| `install.sh` | Entrypoint — `sudo ./install.sh --role air\|gs [flags]`, see `--help` |
| `uninstall.sh` | Reverses `install.sh` — see `docs/operations.md` |
| `lib/` | Installer stages, run in order, each independently re-runnable (`--only`) |
| `config/` | Templates and system files the installer places, including `video-sources/` (pluggable camera modules) |
| `scripts/` | `wfb-doctor` (diagnostics) and `wfb-keys-provision` (key distribution), both usable standalone |
| `keys/` | Empty, gitignored placeholder — nothing writes here automatically; the installer places keys at `/etc/drone.key`/`/etc/gs.key` |
| `docs/` | Install walkthrough, operations, integration guide, troubleshooting, RF tuning |
