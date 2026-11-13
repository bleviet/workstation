#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Disables Large Send Offload v2 (LSOv2) and Receive Segment Coalescing (RSC)
    on the Windows LAN adapter that carries WSL2 traffic to the network.

.DESCRIPTION
    With LSOv2/RSC enabled on the adapter that NATs WSL2 traffic out to the LAN
    (on desktop-ryzen5950x this was the Windows network bridge "Netzwerkbrücke"),
    outbound TCP from WSL2 collapsed to ~0.05-0.08 MB/s with heavy retransmits.
    Xpra over SSH (WSL2 -> MacBook) showed this as "server is not responding"
    stalls. Disabling both restored ~19 MB/s.

    By default the adapter is the one holding the IPv4 default route (lowest
    metric, excluding vEthernet adapters) — i.e. the bridge if one exists,
    otherwise the physical Wi-Fi/Ethernet NIC. Settings persist across reboots.

.PARAMETER AdapterName
    Adapter to tune (e.g. "Netzwerkbrücke", "Network Bridge", "WLAN", "Ethernet").
    Defaults to the default-route adapter.

.PARAMETER IncludeWslAdapter
    Also tune "vEthernet (WSL*)". Not needed on desktop-ryzen5950x; try it if
    the default adapter alone does not fix throughput.

.PARAMETER Check
    Only report the current LSO/RSC state; change nothing.

.PARAMETER Revert
    Re-enable LSOv2 and RSC on the selected adapter(s).

.EXAMPLE
    .\scripts\optimize-windows-network.ps1 -Check

.EXAMPLE
    .\scripts\optimize-windows-network.ps1

.EXAMPLE
    .\scripts\optimize-windows-network.ps1 -AdapterName "Netzwerkbrücke"
#>
param(
    [string]$AdapterName = "",
    [switch]$IncludeWslAdapter,
    [switch]$Check,
    [switch]$Revert
)

$ErrorActionPreference = "Stop"

function Get-DefaultRouteAdapter {
    $route = Get-NetRoute -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $ifc = Get-NetIPInterface -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            [pscustomobject]@{ Route = $_; Metric = $_.RouteMetric + $ifc.InterfaceMetric }
        } |
        Where-Object { $_.Route.InterfaceAlias -notlike "vEthernet*" } |
        Sort-Object Metric |
        Select-Object -First 1
    if (-not $route) { return $null }
    return Get-NetAdapter -InterfaceIndex $route.Route.ifIndex
}

function Show-State {
    param([string[]]$Names)
    foreach ($n in $Names) {
        $lso = Get-NetAdapterLso -Name $n -ErrorAction SilentlyContinue
        $rsc = Get-NetAdapterRsc -Name $n -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Adapter = $n
            LsoIPv4 = if ($lso) { $lso.IPv4Enabled } else { "n/a" }
            LsoIPv6 = if ($lso) { $lso.IPv6Enabled } else { "n/a" }
            RscIPv4 = if ($rsc) { $rsc.IPv4Enabled } else { "n/a" }
            RscIPv6 = if ($rsc) { $rsc.IPv6Enabled } else { "n/a" }
        }
    }
}

$targets = @()
if ($AdapterName) {
    $targets += (Get-NetAdapter -Name $AdapterName).Name
} else {
    $default = Get-DefaultRouteAdapter
    if (-not $default) {
        throw "No IPv4 default route found. Pass -AdapterName explicitly (see Get-NetAdapter)."
    }
    $targets += $default.Name
}
if ($IncludeWslAdapter) {
    $targets += (Get-NetAdapter -Name "vEthernet (WSL*)" -ErrorAction SilentlyContinue).Name
}
$targets = $targets | Where-Object { $_ } | Select-Object -Unique

Write-Host "Adapter(s): $($targets -join ', ')" -ForegroundColor Cyan
Write-Host "Current state:"
Show-State $targets | Format-Table -AutoSize

if ($Check) { return }

foreach ($n in $targets) {
    if ($Revert) {
        Write-Host "Re-enabling LSOv2 and RSC on '$n'..."
        Enable-NetAdapterLso -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
        Enable-NetAdapterRsc -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
    } else {
        Write-Host "Disabling LSOv2 and RSC on '$n'..."
        # Not every adapter exposes both offloads (e.g. Wi-Fi has no LSO);
        # missing ones are skipped.
        Disable-NetAdapterLso -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
        Disable-NetAdapterRsc -Name $n -IPv4 -IPv6 -ErrorAction SilentlyContinue
    }
}

Write-Host "New state:"
Show-State $targets | Format-Table -AutoSize
Write-Host "The adapter briefly resets when offloads change; reconnect SSH/Xpra if a session dropped."
