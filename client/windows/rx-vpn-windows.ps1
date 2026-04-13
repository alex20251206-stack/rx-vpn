param(
  [Parameter(Position = 0)]
  [string]$Command,
  [Parameter(Position = 1)]
  [string]$Arg1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$StateDir = "C:\ProgramData\rx-vpn"
$UrlFile = Join-Path $StateDir "subscription.url"
$LocalPortFile = Join-Path $StateDir "local.port"
$CaFile = Join-Path $StateDir "stunnel-ca.pem"
$OvpnConf = Join-Path $StateDir "client.ovpn"
$StunnelConf = Join-Path $StateDir "stunnel.conf"
$LogFile = Join-Path $StateDir "client.log"
$NssmServiceStunnel = "RXVPN-Stunnel"
$NssmServiceOpenvpn = "RXVPN-OpenVPN"

function Show-Usage {
  @"
Usage: rx-vpn-windows.ps1 <command>

  set-url <url>   Save subscription URL, refresh config, and start services.
  refresh         Re-download profile and restart services.
  status          Show files and service status.
  logs            Follow unified log.
  disable         Stop and disable services.
"@
}

function Require-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Run PowerShell as Administrator."
  }
}

function Get-LocalPort {
  if ($env:OVPN_LOCAL_PORT) {
    return $env:OVPN_LOCAL_PORT.Trim()
  }
  if (Test-Path $LocalPortFile) {
    $saved = (Get-Content -LiteralPath $LocalPortFile -Raw).Trim()
    if ($saved) { return $saved }
  }
  return "11941"
}

function Resolve-Binary([string]$Name, [string[]]$Candidates) {
  foreach ($c in $Candidates) {
    if (Test-Path $c) { return $c }
  }
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "Missing required binary: $Name"
}

function Get-NssmPath {
  Resolve-Binary "nssm.exe" @(
    "C:\Program Files\nssm\win64\nssm.exe",
    "C:\Program Files\nssm\win32\nssm.exe",
    "C:\Windows\System32\nssm.exe"
  )
}

function Get-StunnelPath {
  Resolve-Binary "stunnel.exe" @(
    "C:\Program Files (x86)\stunnel\bin\stunnel.exe",
    "C:\Program Files\stunnel\bin\stunnel.exe"
  )
}

function Get-OpenvpnPath {
  Resolve-Binary "openvpn.exe" @(
    "C:\Program Files\OpenVPN\bin\openvpn.exe",
    "C:\Program Files\OpenVPN\bin\openvpnserv2.exe"
  )
}

function Parse-Remote([string]$Path) {
  $line = Get-Content -LiteralPath $Path | Where-Object { $_ -match '^\s*remote\s+' } | Select-Object -First 1
  if (-not $line) { throw "No remote line in OpenVPN profile." }
  $parts = ($line -replace '^\s*remote\s+', '').Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($parts.Count -lt 2) { throw "Invalid remote line: $line" }
  return @{ Host = $parts[0]; Port = $parts[1] }
}

function Extract-CaBlock([string]$Content) {
  $m = [regex]::Match($Content, '<ca>\s*(?<ca>[\s\S]*?)\s*</ca>')
  if (-not $m.Success) { throw "Missing <ca> block in profile." }
  return $m.Groups["ca"].Value.Trim() + "`r`n"
}

function Rewrite-Ovpn([string]$Content, [string]$LocalPort, [string]$LogPath) {
  $lines = $Content -split "`r?`n"
  $output = New-Object System.Collections.Generic.List[string]
  $remoteDone = $false
  foreach ($ln in $lines) {
    if ($ln -match '^\s*remote\s+') {
      if (-not $remoteDone) {
        $output.Add("remote 127.0.0.1 $LocalPort")
        $remoteDone = $true
      }
      continue
    }
    if ($ln -match '^\s*log(\-append)?\s+') { continue }
    $output.Add($ln)
  }
  if (-not $remoteDone) { throw "Failed to rewrite remote line." }
  $output.Add("log-append $LogPath")
  return ($output -join "`r`n") + "`r`n"
}

function Ensure-Service(
  [string]$Nssm,
  [string]$ServiceName,
  [string]$AppPath,
  [string]$AppParameters
) {
  $exists = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
  if (-not $exists) {
    & $Nssm install $ServiceName $AppPath $AppParameters | Out-Null
  }
  & $Nssm set $ServiceName Application $AppPath | Out-Null
  & $Nssm set $ServiceName AppParameters $AppParameters | Out-Null
  & $Nssm set $ServiceName AppStdout $LogFile | Out-Null
  & $Nssm set $ServiceName AppStderr $LogFile | Out-Null
  & $Nssm set $ServiceName Start SERVICE_AUTO_START | Out-Null
}

function Restart-ServiceByNssm([string]$Nssm, [string]$ServiceName) {
  & $Nssm stop $ServiceName | Out-Null
  & $Nssm start $ServiceName | Out-Null
}

function Build-And-Apply {
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  if (-not (Test-Path $UrlFile)) {
    throw "No subscription URL configured. Run set-url first."
  }

  $tmp = Join-Path $env:TEMP "rx-vpn-subscription-$PID.ovpn"
  Invoke-WebRequest -Uri ((Get-Content -LiteralPath $UrlFile -Raw).Trim()) -Headers @{ Accept = "text/plain" } -OutFile $tmp -UseBasicParsing
  $raw = Get-Content -LiteralPath $tmp -Raw
  if ($raw -notmatch '<ca>') {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    throw "Downloaded response is not an inline OpenVPN profile."
  }

  $lp = Get-LocalPort
  Set-Content -LiteralPath $LocalPortFile -Value "$lp`r`n" -Encoding ascii
  $remote = Parse-Remote $tmp
  $ca = Extract-CaBlock $raw
  Set-Content -LiteralPath $CaFile -Value $ca -Encoding ascii

  @"
foreground = yes
debug = notice
output = $LogFile

[openvpn]
client = yes
accept = 127.0.0.1:$lp
connect = $($remote.Host):$($remote.Port)
verifyChain = yes
CAfile = $CaFile
"@ | Set-Content -LiteralPath $StunnelConf -Encoding ascii

  $ovpn = Rewrite-Ovpn $raw $lp $LogFile
  Set-Content -LiteralPath $OvpnConf -Value $ovpn -Encoding ascii

  if (-not (Test-Path $LogFile)) {
    New-Item -ItemType File -Path $LogFile -Force | Out-Null
  }

  $nssm = Get-NssmPath
  $stunnel = Get-StunnelPath
  $openvpn = Get-OpenvpnPath

  Ensure-Service $nssm $NssmServiceStunnel $stunnel "`"$StunnelConf`""
  Ensure-Service $nssm $NssmServiceOpenvpn $openvpn "--config `"$OvpnConf`""
  Restart-ServiceByNssm $nssm $NssmServiceStunnel
  Restart-ServiceByNssm $nssm $NssmServiceOpenvpn

  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

function Cmd-SetUrl([string]$Url) {
  Require-Admin
  if (-not $Url) { throw "Missing URL." }
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  Set-Content -LiteralPath $UrlFile -Value ($Url.Trim() + "`r`n") -Encoding ascii
  Build-And-Apply
  Write-Host "Configured and started services: $NssmServiceStunnel, $NssmServiceOpenvpn"
}

function Cmd-Refresh {
  Require-Admin
  Build-And-Apply
  Write-Host "Refreshed profile and restarted services."
}

function Cmd-Status {
  Write-Host "State dir: $StateDir"
  Write-Host "Local port: $(Get-LocalPort)"
  if (Test-Path $UrlFile) { Write-Host "URL: configured" } else { Write-Host "URL: not configured" }
  foreach ($svc in @($NssmServiceStunnel, $NssmServiceOpenvpn)) {
    Write-Host "--- $svc ---"
    sc.exe query $svc 2>$null | Out-String | Write-Host
  }
}

function Cmd-Disable {
  Require-Admin
  $nssm = Get-NssmPath
  foreach ($svc in @($NssmServiceOpenvpn, $NssmServiceStunnel)) {
    & $nssm stop $svc | Out-Null
    & $nssm set $svc Start SERVICE_DISABLED | Out-Null
  }
  Write-Host "Stopped and disabled services."
}

function Cmd-Logs {
  if (-not (Test-Path $LogFile)) { throw "No log file yet: $LogFile" }
  Get-Content -LiteralPath $LogFile -Wait
}

switch (($Command ?? "").ToLowerInvariant()) {
  "set-url" { Cmd-SetUrl $Arg1 }
  "refresh" { Cmd-Refresh }
  "status" { Cmd-Status }
  "disable" { Cmd-Disable }
  "logs" { Cmd-Logs }
  "help" { Show-Usage }
  "" { Show-Usage }
  default { throw "Unknown command: $Command" }
}
