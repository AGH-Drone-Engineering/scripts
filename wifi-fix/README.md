# wifi-fix

Network configuration scripts for Raspberry Pi (NetworkManager) to simplify headless setups and eliminate connectivity dropouts.

## Permissions

```bash
chmod +x eth.sh wifi.sh
```

---

## 1. `eth.sh` — Direct Ethernet Cable / DHCP Fallback

Configures `eth0` with dual behavior: connects to local network DHCP when available, or falls back to a direct link when plugged straight into a laptop:

```bash
sudo ./eth.sh
```

### How it works:
1. **Router Mode (DHCP):** Tries obtaining an IP from the local network (8-second timeout).
2. **Direct Link Mode (Shared):** If no DHCP server responds (e.g., direct cable connection to a laptop), the Pi assigns itself static IP **`10.42.0.1`** and acts as a DHCP server, handing out a `10.42.0.x` address to the connected computer.
3. **Connecting from your computer:**
   - Static IP: `ssh <user>@10.42.0.1`
   - mDNS: `ssh <user>@raspberrypi.local` (or `<hostname>.local`)

---

## 2. `wifi.sh` — Wi-Fi Stabilization & Watchdog

Prevents Wi-Fi power-save disconnects and automatically restarts the interface if connectivity is lost:

```bash
# Configure all existing Wi-Fi profiles:
sudo ./wifi.sh

# Or configure a specific profile (find the name via `nmcli connection show`):
sudo ./wifi.sh "NAME"
```

### How it works:
1. Sets regulatory domain to `PL` and unblocks RFKill.
2. Disables Wi-Fi power saving (`powersave = off`) and disables MAC randomization (ensuring static DHCP leases).
3. Installs an automatic systemd watchdog (`rpi-wifi-watchdog.timer` running every 2 minutes):
   - Pings default gateway (with an ARP table fallback for routers blocking ICMP).
   - If 3 consecutive checks fail (6 minutes total), it cycles Wi-Fi radio power (`nmcli radio wifi off && sleep 3 && nmcli radio wifi on`) to re-associate.
4. Safely reloads the active connection in the background without killing existing SSH sessions.

### Useful commands:
```bash
systemctl status rpi-wifi-watchdog.timer
sudo journalctl -t wifi-watchdog -f
```
