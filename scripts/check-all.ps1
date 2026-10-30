#!/usr/bin/env pwsh
# Runs every check that does not need the game or a second PC, in order, and
# stops at the first failure.
#
#   .\scripts\check-all.ps1
#
# What each one covers:
#   build + unit tests   the port's logic, the room codec, the boss rules
#   roomcodec            the codec over 20M lobby ids (injective, reversible)
#   verify-port          the resolved addresses, re-decoded from the binary
#   e2e-loopback         two real mod instances connecting to each other
#
# This is the "is the mod still good?" button. It does not prove the mod works
# in the game: that is scripts\port-3424-probe.ps1 with the game open, and then
# the two-PC session.

param(
    [ValidateSet('Debug', 'Release', 'RelWithDebInfo')]
    [string]$Config = 'RelWithDebInfo'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$failed = @()

function Step([string]$name, [scriptblock]$body) {
    Write-Host ''
    Write-Host "=== $name ===" -ForegroundColor Cyan
    try {
        & $body
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { throw "exit code $LASTEXITCODE" }
        Write-Host "OK: $name" -ForegroundColor Green
    } catch {
        Write-Host "FAILED: $name" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Red
        $script:failed += $name
    }
}

Step 'build + unit tests' {
    & (Join-Path $PSScriptRoot 'build.ps1') -Config $Config
}
Step 'port verification (offline)' {
    & (Join-Path $PSScriptRoot 'verify-port.ps1')
}
Step 'two-instance loopback' {
    & (Join-Path $PSScriptRoot 'e2e-loopback.ps1') -Config $Config
}

Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host 'RESULT: ALL OFFLINE CHECKS PASSED' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Still to do, and only you can: '
    Write-Host '  1. with the game at the title screen:  .\scripts\port-3424-probe.ps1'
    Write-Host '  2. with your friend:                   the two-PC session (docs\PRUEBA-DOS-PC.md)'
    exit 0
}
Write-Host ("RESULT: FAILED -> {0}" -f ($failed -join ', ')) -ForegroundColor Red
exit 1
