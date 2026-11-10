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

