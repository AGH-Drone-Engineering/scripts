#!/bin/bash
# Remove old Ethernet profiles
sudo nmcli con delete "Wired connection 1" 2>/dev/null
sudo nmcli con delete eth0-direct 2>/dev/null
sudo nmcli con delete eth0-dhcp 2>/dev/null

# 1. DHCP first (router); if no response within timeout, NM falls back to profile 2
sudo nmcli con add type ethernet ifname eth0 con-name eth0-dhcp \
  ipv4.method auto ipv4.may-fail no ipv4.dhcp-timeout 8 \
  ipv6.method link-local \
  connection.autoconnect-priority 10 connection.autoconnect-retries 1

# 2. Fallback: RPi shares connection and serves 10.42.0.x (direct cable to laptop)
sudo nmcli con add type ethernet ifname eth0 con-name eth0-direct \
  ipv4.method shared ipv4.addresses 10.42.0.1/24 \
  ipv6.method link-local \
  connection.autoconnect-priority 0

sudo nmcli con up eth0-dhcp || sudo nmcli con up eth0-direct
