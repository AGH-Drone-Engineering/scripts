#!/usr/bin/env bash
# Sets up passwordless SSH login to a Raspberry Pi (key + ~/.ssh/config alias).
# Run with bash (not sh).

read -rp "Username [pi]: " u </dev/tty; u=${u:-pi}
read -rp "Host / IP / mDNS [raspberry.local]: " t </dev/tty; t=${t:-raspberry.local}

fail() { printf '\n[!] %s\n' "$1" >&2; exit 1; }

for cmd in ssh ssh-keygen ssh-copy-id; do
    command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' not found - install the OpenSSH client first."
done

sshdir="$HOME/.ssh"
k="$sshdir/id_ed25519"
cfg="$sshdir/config"
a="${t%.local}"

mkdir -p "$sshdir" && chmod 700 "$sshdir"

# 1. Key (comment = user@machine so keys from different PCs can be told apart)
if [ ! -f "$k.pub" ]; then
    ssh-keygen -t ed25519 -f "$k" -N "" -C "$(whoami)@$(hostname)" || fail "ssh-keygen failed."
fi

# 2. Copy key to the Pi (asks for the Pi's password; skips keys already present)
echo "Copying key to $u@$t (enter the Pi's password when asked)..."
ssh-copy-id -i "$k.pub" "$u@$t" \
    || fail "Could not copy the key to $u@$t (wrong password, host unreachable, or SSH disabled on the Pi?)."

# 3. Verify that key-based login really works (no password fallback)
ssh -i "$k" -o IdentitiesOnly=yes -o BatchMode=yes -o PasswordAuthentication=no \
    -o ConnectTimeout=10 "$u@$t" true \
    || fail "Key was copied, but key-based login does not work."

# 4. ~/.ssh/config alias
[ -f "$cfg" ] || { touch "$cfg" && chmod 600 "$cfg"; }
a_re=$(printf '%s' "$a" | sed 's/[][\.*^$]/\\&/g')
if grep -qE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?${a_re}([[:space:]]|\$)" "$cfg"; then
    printf '[i] Alias "%s" already exists in %s - left unchanged (make sure it points to %s).\n' "$a" "$cfg" "$t"
else
    printf '\nHost %s\n    HostName %s\n    User %s\n    IdentityFile %s\n    IdentitiesOnly yes\n' \
        "$a" "$t" "$u" "$k" >> "$cfg"
fi

printf '\n[+] Done! Key login verified. Connect using: ssh %s\n' "$a"

