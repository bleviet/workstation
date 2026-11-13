#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Finds and removes a Windows network bridge that only wraps Wi-Fi, the cause of
    stalled downloads, SMB errors and Xpra lag on WSL2 dev PCs. Optionally toggles
    LSOv2/RSC as a fallback.

.DESCRIPTION
    On desktop-ryzen5950x all LAN traffic went through a Windows network bridge
    ("Netzwerkbrücke") whose only member was the Wi-Fi adapter. A bridge joins two
    networks; with one member it bridges nothing, but Windows moves TCP/IP and the
    SMB client from the Wi-Fi adapter onto it, and bridging over Wi-Fi needs MAC
    translation for every frame. Symptoms, while ping and signal looked perfect:
      - inbound TCP collapsed to <1 KB/s (internet and NAS)
      - SMB reads failed with "Unerwarteter Netzwerkfehler" (KeePass couldn't
        open its database from the NAS)
      - WSL2 -> LAN dropped to 0.05 MB/s; Xpra stalled ("server is not responding")
    Toggling LSOv2/RSC on the bridge only masked one direction for a while.
    Removing the bridge fixed everything: 65 MB/s internet, 28 MB/s SMB,
    57 MB/s WSL2 -> LAN.

    Without switches the script only reports; nothing is changed.

.PARAMETER FixBridge
    Remove the bridge if all its members are wireless or it has a single member,
    re-enable TCP/IP, SMB client and the other standard bindings on the former
    members, and keep the network profile (e.g. Private, which the SSH firewall
    rules from setup-windows-ssh.ps1 depend on). The LAN IP usually stays the same
    (DHCP keys on the Wi-Fi MAC). Bridges with several wired members are left alone.

.PARAMETER DisableOffloads
    Fallback only: disable LSOv2 and RSC on the default-route adapter (and
    vEthernet (WSL*) with -IncludeWslAdapter). Not needed once the bridge is gone.

.PARAMETER EnableOffloads
    Re-enable LSOv2 and RSC (undo -DisableOffloads).

.PARAMETER AdapterName
    Adapter for -DisableOffloads/-EnableOffloads. Defaults to the default-route adapter.

.PARAMETER IncludeWslAdapter
    Also apply -DisableOffloads/-EnableOffloads to "vEthernet (WSL*)".

.EXAMPLE
    .\scripts\optimize-windows-network.ps1              # report only

.EXAMPLE
    .\scripts\optimize-windows-network.ps1 -FixBridge   # remove a Wi-Fi-only bridge
#>
param(
    [switch]$FixBridge,
    [switch]$DisableOffloads,
    [switch]$EnableOffloads,
    [string]$AdapterName = "",
    [switch]$IncludeWslAdapter
)

$ErrorActionPreference = "Stop"
if ($DisableOffloads -and $EnableOffloads) { throw "Use either -DisableOffloads or -EnableOffloads, not both." }

# Bindings Windows removes from an adapter when it joins a bridge.
$StandardBindings = "ms_tcpip", "ms_tcpip6", "ms_msclient", "ms_server", "ms_pacer", "ms_lltdio", "ms_rspndr"

function Get-BridgeInfo {
    # netsh output is localized but the GUIDs and Yes/No columns are stable.
    $guids = @(netsh bridge list | Select-String -Pattern '\{[0-9A-Fa-f-]{36}\}' -AllMatches |
        ForEach-Object { $_.Matches.Value } | Select-Object -Unique)
    $members = @(netsh bridge show adapter | ForEach-Object {
            if ($_ -match '^\s*(\d+)\s+\{[0-9A-Fa-f-]{36}\}\s+(.+?)\s+(Yes|Ja)\s+(Yes|No|Ja|Nein)\s+') {
                $a = Get-NetAdapter -InterfaceIndex ([int]$Matches[1]) -ErrorAction SilentlyContinue
                [pscustomobject]@{
                    Name     = $Matches[2].Trim()
                    Wireless = [bool]($a -and ($a.PhysicalMediaType -match '802\.11|Wireless' -or $a.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN'))
                }
            }
        })
    $adapter = Get-NetAdapter -InterfaceDescription "Microsoft Network Adapter Multiplexor*" -ErrorAction SilentlyContinue | Select-Object -First 1
    [pscustomobject]@{ Guids = $guids; Members = $members; Adapter = $adapter }
}

function Get-DefaultRouteAdapter {
    $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceAlias -notlike "vEthernet*" } |
        ForEach-Object {
            $ifc = Get-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            [pscustomobject]@{ Route = $_; Metric = $_.RouteMetric + $ifc.InterfaceMetric }
        } |
        Sort-Object Metric | Select-Object -First 1
    if ($route) { Get-NetAdapter -InterfaceIndex $route.Route.ifIndex }
}

function Show-Offloads([string[]]$Names) {
    foreach ($n in $Names) {
        $lso = Get-NetAdapterLso -Name $n -ErrorAction SilentlyContinue
        $rsc = Get-NetAdapterRsc -Name $n -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Adapter = $n
            LsoIPv4 = if ($lso) { $lso.IPv4Enabled } else { "n/a" }
            RscIPv4 = if ($rsc) { $rsc.IPv4Enabled } else { "n/a" }
        }
    }
}

# ── Report ───────────────────────────────────────────────────────────────────
$bridge = Get-BridgeInfo
$default = Get-DefaultRouteAdapter
Write-Host "Default-route adapter: $(if ($default) { $default.Name } else { '(none)' })" -ForegroundColor Cyan

$suspect = $false
if ($bridge.Guids.Count -eq 0) {
    Write-Host "Network bridge: none (good)." -ForegroundColor Green
} else {
    $names = ($bridge.Members | ForEach-Object { "$($_.Name)$(if ($_.Wireless) { ' [Wi-Fi]' })" }) -join ", "
    Write-Host "Network bridge(s): $($bridge.Guids.Count); members: $names"
    $allWireless = $bridge.Members.Count -gt 0 -and -not ($bridge.Members | Where-Object { -not $_.Wireless })
    $suspect = $bridge.Guids.Count -eq 1 -and ($bridge.Members.Count -le 1 -or $allWireless)
    if ($suspect) {
        Write-Warning "This bridge only wraps Wi-Fi / a single adapter. It bridges nothing and is known to stall downloads, SMB and Xpra. Fix: re-run with -FixBridge."
    }
}
Write-Host "Offloads (informational):"
Show-Offloads @($default.Name | Where-Object { $_ }) | Format-Table -AutoSize

# ── Fix: remove a Wi-Fi-only / single-member bridge ──────────────────────────
if ($FixBridge) {
    if ($bridge.Guids.Count -eq 0) {
        Write-Host "No bridge to remove."
    } elseif (-not $suspect) {
        Write-Warning "Bridge has several wired members (or there are several bridges); not removing it automatically. Use ncpa.cpl if you really want it gone."
    } else {
        $netCategory = if ($bridge.Adapter) {
            (Get-NetConnectionProfile -InterfaceAlias $bridge.Adapter.Name -ErrorAction SilentlyContinue).NetworkCategory
        }
        $memberNames = $bridge.Members.Name
        Write-Host "Removing bridge $($bridge.Guids[0]) (members: $($memberNames -join ', ')); the network drops for a few seconds..." -ForegroundColor Cyan
        netsh bridge destroy $bridge.Guids[0] | Out-Host
        Start-Sleep -Seconds 5
        foreach ($m in $memberNames) {
            foreach ($c in $StandardBindings) {
                Enable-NetAdapterBinding -Name $m -ComponentID $c -ErrorAction SilentlyContinue
            }
        }
        $t0 = Get-Date
        do {
            Start-Sleep -Seconds 2
            $ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceAlias -in $memberNames -and $_.IPAddress -notlike "169.254.*" } |
                Select-Object -First 1
        } until ($ip -or ((Get-Date) - $t0).TotalSeconds -gt 60)
        if (-not $ip) { throw "No IPv4 address on $($memberNames -join ', ') after 60 s; check the Wi-Fi connection." }
        Start-Sleep -Seconds 3
        if ($netCategory -and $netCategory -ne "DomainAuthenticated") {
            Set-NetConnectionProfile -InterfaceAlias $ip.InterfaceAlias -NetworkCategory $netCategory -ErrorAction SilentlyContinue
        }
        Write-Host "Bridge removed. $($ip.InterfaceAlias) has $($ip.IPAddress) (profile: $((Get-NetConnectionProfile -InterfaceAlias $ip.InterfaceAlias).NetworkCategory))." -ForegroundColor Green
        Write-Host "If the IP changed, update the Mac's ~/.ssh/config HostName; then run setup-windows-ssh.ps1 to refresh the portproxy if needed."
    }
}

# ── Fallback: LSOv2 / RSC toggles ────────────────────────────────────────────
if ($DisableOffloads -or $EnableOffloads) {
    $targets = @()
    $targets += if ($AdapterName) { (Get-NetAdapter -Name $AdapterName).Name } else { (Get-DefaultRouteAdapter).Name }
    if ($IncludeWslAdapter) { $targets += (Get-NetAdapter -Name "vEthernet (WSL*)" -ErrorAction SilentlyContinue).Name }
    $targets = $targets | Where-Object { $_ } | Select-Object -Unique
    foreach ($n in $targets) {
        # Not every adapter exposes both offloads (Wi-Fi has no LSO); missing ones are skipped.
        if ($DisableOffloads) {
            Write-Host "Disabling LSOv2 and RSC on '$n'..."
            Disable-NetAdapterLso -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
            Disable-NetAdapterRsc -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
        } else {
            Write-Host "Enabling LSOv2 and RSC on '$n'..."
            Enable-NetAdapterLso -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
            Enable-NetAdapterRsc -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
        }
    }
    Show-Offloads $targets | Format-Table -AutoSize
}
