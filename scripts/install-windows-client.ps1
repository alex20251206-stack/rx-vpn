param(
  [string]$Version = "",
  [string]$SubUrl = "",
  [string]$Repo = "alex20251206-stack/rx-vpn",
  [string]$Branch = "main",
  [string]$OfflineRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$StateDir = "C:\ProgramData\rx-vpn"
$InstallDir = "C:\Program Files\rx-vpn"
$ClientScriptPath = Join-Path $InstallDir "rx-vpn-windows.ps1"
$ShimPath = Join-Path $InstallDir "rx-vpn-windows.cmd"
$ThirdPartyBase = "https://raw.githubusercontent.com/$Repo/$Branch/third_party/windows"
$ClientBase = "https://raw.githubusercontent.com/$Repo/$Branch/client/windows"
$LocalThirdParty = Join-Path $PSScriptRoot "..\third_party\windows"
$LocalClient = Join-Path $PSScriptRoot "..\client\windows\rx-vpn-windows.ps1"

if ($OfflineRoot) {
  $LocalThirdParty = Join-Path $OfflineRoot "third_party\windows"
  $LocalClient = Join-Path $OfflineRoot "client\windows\rx-vpn-windows.ps1"
}

function Require-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    throw "Run this installer in Administrator PowerShell."
  }
}

function Resolve-Version {
  if ($script:Version) {
    if ($script:Version -notmatch '^v\d+\.\d+\.\d+$') {
      throw "Version must match vX.Y.Z."
    }
    return
  }
  $releaseApi = "https://api.github.com/repos/$Repo/releases/latest"
  $json = Invoke-RestMethod -Uri $releaseApi -UseBasicParsing
  if (-not $json.tag_name) { throw "Cannot resolve latest release tag." }
  $script:Version = [string]$json.tag_name
}

function Download-File([string]$Url, [string]$Out) {
  Write-Host "==> downloading $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Out -UseBasicParsing
}

function Copy-Or-Download([string]$Name, [string]$OutPath) {
  $localPath = Join-Path $LocalThirdParty $Name
  if (Test-Path $localPath) {
    Write-Host "==> using local bundle: $localPath"
    Copy-Item -LiteralPath $localPath -Destination $OutPath -Force
    return
  }
  Download-File "$ThirdPartyBase/$Name" $OutPath
}

function Get-ExpectedHashes([string]$ShaFilePath) {
  $map = @{}
  foreach ($line in Get-Content -LiteralPath $ShaFilePath) {
    if (-not $line.Trim()) { continue }
    $parts = $line -split '\s+', 2
    if ($parts.Count -ne 2) { continue }
    $map[$parts[1].Trim()] = $parts[0].Trim().ToLowerInvariant()
  }
  return $map
}

function Assert-Hash([string]$Path, [string]$Expected) {
  $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $Expected) {
    throw "SHA256 mismatch for $(Split-Path $Path -Leaf). expected=$Expected actual=$actual"
  }
}

function Ensure-PathEntry([string]$Dir) {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ($machinePath -notlike "*$Dir*") {
    [Environment]::SetEnvironmentVariable("Path", "$machinePath;$Dir", "Machine")
    Write-Host "==> added to machine PATH: $Dir"
  }
}

function Install-OpenVpn([string]$MsiPath) {
  Write-Host "==> installing OpenVPN"
  Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", "`"$MsiPath`"", "/qn", "/norestart") -Wait -NoNewWindow
}

function Install-Stunnel([string]$ExePath) {
  Write-Host "==> installing stunnel"
  Start-Process -FilePath $ExePath -ArgumentList @("/VERYSILENT", "/NORESTART", "/SP-") -Wait -NoNewWindow
}

function Install-Nssm([string]$ZipPath) {
  Write-Host "==> installing NSSM"
  $target = "C:\Program Files\nssm"
  if (Test-Path $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  Expand-Archive -LiteralPath $ZipPath -DestinationPath "C:\Program Files" -Force
  $expanded = "C:\Program Files\nssm-2.24-101-g897c7ad"
  if (Test-Path $expanded) {
    Rename-Item -LiteralPath $expanded -NewName "nssm" -Force
  }
}

function Install-ClientScript {
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  if (Test-Path $LocalClient) {
    Write-Host "==> using local client script: $LocalClient"
    Copy-Item -LiteralPath $LocalClient -Destination $ClientScriptPath -Force
  } else {
    $clientUrl = "$ClientBase/rx-vpn-windows.ps1"
    Download-File $clientUrl $ClientScriptPath
  }
  @"
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "$ClientScriptPath" %*
"@ | Set-Content -LiteralPath $ShimPath -Encoding ascii
  Ensure-PathEntry $InstallDir
}

Require-Admin
Resolve-Version

$tmp = Join-Path $env:TEMP "rx-vpn-win-install-$PID"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
  $openvpnName = "OpenVPN-2.7.1-I001-amd64.msi"
  $stunnelName = "stunnel-5.78-win64-installer.exe"
  $nssmName = "nssm-2.24-101-g897c7ad.zip"
  $shaName = "SHA256SUMS.txt"

  $openvpnPath = Join-Path $tmp $openvpnName
  $stunnelPath = Join-Path $tmp $stunnelName
  $nssmPath = Join-Path $tmp $nssmName
  $shaPath = Join-Path $tmp $shaName

  Copy-Or-Download $openvpnName $openvpnPath
  Copy-Or-Download $stunnelName $stunnelPath
  Copy-Or-Download $nssmName $nssmPath
  Copy-Or-Download $shaName $shaPath

  $hashes = Get-ExpectedHashes $shaPath
  Assert-Hash $openvpnPath $hashes[$openvpnName]
  Assert-Hash $stunnelPath $hashes[$stunnelName]
  Assert-Hash $nssmPath $hashes[$nssmName]

  Install-OpenVpn $openvpnPath
  Install-Stunnel $stunnelPath
  Install-Nssm $nssmPath
  Install-ClientScript

  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

  Write-Host "==> done. Open a new PowerShell window and run:"
  Write-Host "   rx-vpn-windows status"
  if ($SubUrl) {
    Write-Host "==> applying subscription URL"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $ClientScriptPath set-url $SubUrl
  } else {
    Write-Host "==> next:"
    Write-Host "   rx-vpn-windows set-url 'http://<OVPN_REMOTE_HOST>:8139/api/sub/<sub-code>'"
  }
}
finally {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
