#!/usr/bin/env pwsh
# Two-instance protocol test on one PC, with no game.
#
#   .\scripts\e2e-loopback.ps1
#
# WHY THIS EXISTS
# The real test needs two PCs, two Steam accounts and a friend. This runs the
# SAME mod twice, on the same machine, over the UDP transport, and checks the
# part that the Steam path also depends on: the handshake, the build-id exchange,
# the state stream and the disconnect. It cannot test Steam itself or anything
# that needs the game, but it does prove the protocol layer works between two
# real mod instances rather than in a unit test.
#
# Topology matters: in UDP the HOST listens and the GUEST connects to it. Do not
# point either side at cdmp_peer for this -- the host would try to bind the port
# the relay already holds, and fail with "Cannot open UDP socket: WSA error 0".
#
# Exit code 0 means both sides connected and stayed connected.

param(
    [int]$Port = 37031,
    [int]$Seconds = 14,
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
    [string]$Config = 'RelWithDebInfo'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$bin = Join-Path $root "build\bin\$Config"

foreach ($f in 'cdmp.asi', 'cdmp_host.exe') {
    if (-not (Test-Path (Join-Path $bin $f))) { throw "Build first: $f not found in $bin" }
}

$work = Join-Path $env:TEMP "cdmp-e2e-$Port"
if (Test-Path $work) { Remove-Item $work -Recurse -Force }
foreach ($side in 'host', 'guest') {
    New-Item -ItemType Directory -Path (Join-Path $work $side) -Force | Out-Null
    Copy-Item (Join-Path $bin 'cdmp.asi') (Join-Path $work $side)
    Copy-Item (Join-Path $bin 'cdmp_host.exe') (Join-Path $work $side)
}

# Both sides get the same co-op settings, differing only in role. The INI must be
# UTF-16: the mod reads it with the wide INI API, and a UTF-8 file is silently
# ignored key by key.
function Write-Ini([string]$path, [string]$name, [string]$role) {
    @"
[general]
player_name=$name

[net]
enabled=1
transport=udp
role=$role
peer_host=127.0.0.1
peer_port=$Port
send_rate_hz=20

[overlay]
enabled=0

[sniffer]
enabled=1

[coop]
enabled=1
delay_ms=300
enemy_auto=1
guest_hits=1
boss_safe=1
guest_loot=1
"@ | Set-Content $path -Encoding Unicode
}
Write-Ini (Join-Path $work 'host\cdmp.ini') 'Hosty' 'host'
Write-Ini (Join-Path $work 'guest\cdmp.ini') 'Guesty' 'guest'

Write-Host "Starting the host (listens on $Port)..."
$hp = Start-Process -FilePath (Join-Path $work 'host\cdmp_host.exe') `
    -ArgumentList (Join-Path $work 'host\cdmp.asi'), "$Seconds" `
    -WorkingDirectory (Join-Path $work 'host') -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2  # the host must be listening before the guest looks

Write-Host 'Starting the guest...'
$gp = Start-Process -FilePath (Join-Path $work 'guest\cdmp_host.exe') `
    -ArgumentList (Join-Path $work 'guest\cdmp.asi'), "$($Seconds - 4)" `
    -WorkingDirectory (Join-Path $work 'guest') -PassThru -WindowStyle Hidden
$gp.WaitForExit(($Seconds + 20) * 1000) | Out-Null
$hp.WaitForExit(($Seconds + 20) * 1000) | Out-Null
$hp | Stop-Process -Force -ErrorAction SilentlyContinue
$gp | Stop-Process -Force -ErrorAction SilentlyContinue

$hlog = Get-Content (Join-Path $work 'host\cdmp.log') -Raw
$glog = Get-Content (Join-Path $work 'guest\cdmp.log') -Raw

function Check([string]$what, [bool]$ok) {
    Write-Host ("  {0} {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what)
    return $ok
}
$all = $true
Write-Host ''
Write-Host 'Results:'
$all = (Check 'host listened'                 ($hlog -match 'as host; peer = whoever connects')) -and $all
$all = (Check 'host saw the guest join'       ($hlog -match 'is joining'))                    -and $all
$all = (Check 'host identified the guest'     ($hlog -match "connected to peer 'Guesty'"))    -and $all
$all = (Check 'guest identified the host'     ($glog -match "connected to peer 'Hosty'"))     -and $all
# A build-id mismatch shows up exactly here, which is why both sides print it.
$all = (Check 'no build-id mismatch'          (-not ($hlog -match 'Different mod versions') -and
                                               -not ($glog -match 'Different mod versions'))) -and $all
# rejects > 0 would mean malformed or unknown packets; unknown kinds > 0 would mean
# the two sides read the protocol differently.
$all = (Check 'host exchanged state'          ($hlog -match 'remote states [1-9]'))            -and $all
$all = (Check 'guest exchanged state'         ($glog -match 'remote states [1-9]'))            -and $all
$all = (Check 'nothing rejected (host)'       ($hlog -match 'rejected 0'))                     -and $all
$all = (Check 'nothing rejected (guest)'      ($glog -match 'rejected 0'))                     -and $all
$all = (Check 'no unknown packet kinds'       (-not ($hlog -match 'unknown kinds [1-9]') -and
                                               -not ($glog -match 'unknown kinds [1-9]')))     -and $all
$all = (Check 'no errors in either log'       (-not ($hlog -match '\] ERR ') -and
                                               -not ($glog -match '\] ERR ')))                 -and $all
$all = (Check 'clean shutdown'                (($hlog -match 'Network stopped') -and
                                               ($glog -match 'Network stopped')))              -and $all

Write-Host ''
Write-Host "Logs: $work\host\cdmp.log and $work\guest\cdmp.log"
if ($all) {
    Write-Host 'RESULT: the protocol layer works between two real mod instances.'
    exit 0
}
Write-Host 'RESULT: FAILED - read the logs above.'
exit 1
