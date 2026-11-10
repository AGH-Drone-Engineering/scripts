# ssh-setup

Automated setup of SSH key authentication for connecting to your Raspberry Pi.

> **Note:** Run these scripts on your **local computer** (Windows, Linux), not on the Raspberry Pi itself.

---

## Usage

Interactive prompts will ask for the Pi's username (default: `pi`) and target hostname/IP (default: `raspberry.local`). Press `Enter` to accept defaults.

### Paste directly into terminal

#### Windows (PowerShell)

Paste the following block into PowerShell:

```powershell
& {
    $u = Read-Host "Username [default: pi]"; if (-not $u) { $u = "pi" }
    $t = Read-Host "Host / mDNS / IP [default: raspberry.local]"; if (-not $t) { $t = "raspberry.local" }
    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    $k = Join-Path $sshDir "id_ed25519"
    $pub = "$k.pub"
    $cfg = Join-Path $sshDir "config"
    $a = $t -replace '\.local$', ''

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue) -or -not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
        Write-Host "`n[!] OpenSSH Client not found. Enable it in Settings > Optional features." -ForegroundColor Red
        return
    }

    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir | Out-Null }

    # 1. Key (comment = user@machine so keys from different PCs can be told apart)
    if (-not (Test-Path $pub)) {
        ssh-keygen -t ed25519 -f "$k" -N '""' -C "$env:USERNAME@$env:COMPUTERNAME"
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pub)) {
            Write-Host "`n[!] ssh-keygen failed." -ForegroundColor Red
            return
        }
    }

    # 2. Copy key to the Pi (asks for the Pi's password; skips the key if already present)
    $keyText = (Get-Content $pub -Raw).Trim()
    Write-Host "Copying key to $u@$t (enter the Pi's password when asked)..."
    ssh "$u@$t" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && (grep -qxF '$keyText' ~/.ssh/authorized_keys || printf '\n%s\n' '$keyText' >> ~/.ssh/authorized_keys) && chmod 600 ~/.ssh/authorized_keys"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[!] Could not copy the key to $u@$t (wrong password, host unreachable, or SSH disabled on the Pi?)." -ForegroundColor Red
        return
    }

    # 3. Verify that key-based login really works (no password fallback)
    ssh -i "$k" -o IdentitiesOnly=yes -o BatchMode=yes -o PasswordAuthentication=no -o ConnectTimeout=10 "$u@$t" true
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n[!] Key was copied, but key-based login does not work." -ForegroundColor Red
        return
    }

    # 4. ~/.ssh/config alias
    if (-not (Test-Path $cfg)) { New-Item -ItemType File -Path $cfg | Out-Null }
    $cur = Get-Content $cfg -Raw -ErrorAction SilentlyContinue
    $pattern = '(?m)^[ \t]*Host[ \t]+(.*[ \t])?' + [regex]::Escape($a) + '([ \t]|$)'
    if ($cur -match $pattern) {
        Write-Host "[i] Alias '$a' already exists in $cfg - left unchanged (make sure it points to $t)." -ForegroundColor Yellow
    } else {
        Add-Content -Path $cfg -Value "`nHost $a`n    HostName $t`n    User $u`n    IdentityFile ~/.ssh/id_ed25519`n    IdentitiesOnly yes"
    }

    Write-Host "`n[+] Done! Key login verified. Connect using: ssh $a" -ForegroundColor Green
}
```

#### Linux (Bash)

Paste the following block into your Bash terminal:

```bash
(
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
)
```

---

### Running from files (if repository is cloned)

- **Linux:**
  ```bash
  bash setup.sh
  ```
- **Windows (PowerShell):**
  ```powershell
  .\setup.ps1
  ```

---

### Connecting

Once complete, connect without typing passwords:

```bash
ssh raspberry
```
*(The alias is derived from the mDNS hostname by stripping `.local` — e.g. `raspberry.local` becomes `ssh raspberry`. If an IP address or custom hostname without `.local` is entered, the alias uses that address instead).*

---

## How it works

1. **Key Generation:** Checks `~/.ssh/id_ed25519`. If no keypair exists, generates an Ed25519 key tagged with your machine identity (`user@hostname`) so keys from different PCs can be identified.
2. **Key Provisioning:** Copies the public key to the Pi's `~/.ssh/authorized_keys` with secure permissions (`700` on `~/.ssh`, `600` on `authorized_keys`). Skips duplicate entries if already installed. Prompts for the Pi's password once.
3. **Verification:** Validates that key-based login actually works in strict batch mode (`IdentitiesOnly=yes`, `BatchMode=yes`, `PasswordAuthentication=no`).
4. **Client Alias (`~/.ssh/config`):** Registers an SSH alias based on the target hostname (e.g. `raspberry` for mDNS name `raspberry.local`). Avoids duplicate entries if the alias already exists.

---

## Prerequisites

- **OpenSSH client:**
  - **Linux:** Preinstalled or available via package manager (`ssh`, `ssh-keygen`, `ssh-copy-id`).
  - **Windows:** Built-in on Windows 10/11 (*Settings > System > Optional features > OpenSSH Client*).
- **Target Reachability:** The Pi must have SSH enabled and be reachable via mDNS (`raspberry.local`), static IP, or direct cable link (see [wifi-fix](../wifi-fix/)).
