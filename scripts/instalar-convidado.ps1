<#
.SYNOPSIS
  Installs the GUEST kit after a Steam integrity check, verifying every step by hash.

.DESCRIPTION
  The Steam integrity check restores the game to pristine, which also removes anything
  the mod put in bin64 -- cdmp.asi, cdmp.ini and the renamed winmm.dll all go. That is
  the point of running it, and it is also why this script exists rather than a hand copy:
  after a verify there is nothing left to compare against, so "I copied it" is the only
  claim available unless hashes are checked.

  This checks them. It copies from the published guest kit, renames dinput8.dll to
  winmm.dll, and refuses to report success unless the installed files match the expected
  digests and the INI really says role=guest.

  It also refuses to run while the game is open. The .asi is locked while CrimsonDesert
  runs, the copy fails, and the failure leaves a half-installed directory that looks fine.

.EXAMPLE
  .\instalar-convidado.ps1
#>

[CmdletBinding()]
param(
    # Where the guest kit was unpacked. Defaults to the built kit in this repo.
    [string] $KitDir = '',
    # The game's bin64.
    [string] $GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64',
    # The other player's SteamID64, written into [steam] peer_steamid.
    [string] $PeerSteamId = '76561198410974148'
)

$ErrorActionPreference = 'Stop'

# $PSScriptRoot is empty when the script is invoked in some ways, and a default parameter
# computed from it fails before the body runs. Resolve it here instead, where a fallback
# is possible: the repo root is the parent of this file's directory.
if (-not $KitDir) {
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    if (-not $here) { $here = (Get-Location).Path }
    $KitDir = Join-Path (Split-Path $here -Parent) 'dist\role-swap\guest'
}

# The digests of the published guest kit. A file that does not match is not installed.
$expected = @{
    'cdmp.asi'  = 'ED9FBA87E7ABCC825DE52FFC1C67A95B1A13F1D1546F6F24B1B6CEDA7B3026E0'
    'winmm.dll' = '031A3E5576D91DCE1E438D36B9A3D462C7334AB4791990A8FF1E3DDC0E132DAF'
}

function Fail($msg) { Write-Host "ERRO: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $GameDir)) { Fail "A pasta do jogo nao existe: $GameDir" }

# The .asi cannot be replaced while the game holds it open, and the copy fails in a way
# that is easy to miss.
if (Get-Process CrimsonDesert -ErrorAction SilentlyContinue) {
    Fail 'O jogo esta ABERTO. Feche o Crimson Desert e rode de novo.'
}

$asi = Join-Path $KitDir 'cdmp.asi'
$ini = Join-Path $KitDir 'cdmp.ini'
$ldr = Join-Path $KitDir 'dinput8.dll'
foreach ($f in @($asi, $ini, $ldr)) {
    if (-not (Test-Path $f)) { Fail "Falta no kit: $f" }
}

Write-Host ''
Write-Host '=== 1. conferindo o kit de origem ===' -ForegroundColor Cyan
$srcAsi = (Get-FileHash $asi -Algorithm SHA256).Hash
$srcLdr = (Get-FileHash $ldr -Algorithm SHA256).Hash
if ($srcAsi -ne $expected['cdmp.asi']) {
    Fail "O cdmp.asi do kit nao e' o esperado.`n  esperado: $($expected['cdmp.asi'])`n  obtido:   $srcAsi"
}
if ($srcLdr -ne $expected['winmm.dll']) {
    Fail "O dinput8.dll do kit nao e' o esperado.`n  esperado: $($expected['winmm.dll'])`n  obtido:   $srcLdr"
}
Write-Host "  cdmp.asi   ok" -ForegroundColor Green
Write-Host "  dinput8.dll ok" -ForegroundColor Green

Write-Host ''
Write-Host '=== 2. limpando restos na bin64 ===' -ForegroundColor Cyan
# Anything named like the mod is removed, including rotated logs from earlier runs: a
# leftover cdmp.log is read as if it were this run's, which has already caused one wrong
# diagnosis in this project.
$stale = Get-ChildItem $GameDir -File -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match '^(cdmp|winmm|dinput8)' }
foreach ($f in $stale) {
    Remove-Item $f.FullName -Force
    Write-Host "  removido: $($f.Name)"
}
if (-not $stale) { Write-Host '  nada a remover' }

Write-Host ''
Write-Host '=== 3. instalando ===' -ForegroundColor Cyan
Copy-Item $asi (Join-Path $GameDir 'cdmp.asi') -Force
Copy-Item $ldr (Join-Path $GameDir 'winmm.dll') -Force

# The INI is rewritten rather than copied, so the peer SteamID is right even when the
# kit was packed for someone else. Written as UTF-16 LE: a UTF-8 INI is accepted by the
# mod and reads as empty, which looks like a config problem and is not one.
$text = [IO.File]::ReadAllText($ini, [Text.Encoding]::Unicode)
$text = [regex]::Replace($text, '(?m)^role=.*$', 'role=guest')
$text = [regex]::Replace($text, '(?m)^peer_steamid=.*$', "peer_steamid=$PeerSteamId")
$text = [regex]::Replace($text, '(?m)^code=.*$', 'code=')
[IO.File]::WriteAllText((Join-Path $GameDir 'cdmp.ini'), $text, [Text.Encoding]::Unicode)
Write-Host "  cdmp.asi   -> cdmp.asi"
Write-Host "  cdmp.ini   -> cdmp.ini   (role=guest, peer=$PeerSteamId)"
Write-Host "  dinput8.dll -> winmm.dll  (o jogo importa WINMM e nao DINPUT8)"

Write-Host ''
Write-Host '=== 4. verificando o que ficou instalado ===' -ForegroundColor Cyan
$bad = 0
foreach ($name in $expected.Keys) {
    $p = Join-Path $GameDir $name
    if (-not (Test-Path $p)) { Write-Host "  $name  FALTA" -ForegroundColor Red; $bad++; continue }
    $h = (Get-FileHash $p -Algorithm SHA256).Hash
    if ($h -eq $expected[$name]) {
        Write-Host "  $name  ok" -ForegroundColor Green
    } else {
        Write-Host "  $name  NAO BATE" -ForegroundColor Red
        Write-Host "     esperado: $($expected[$name])"
        Write-Host "     obtido:   $h"
        $bad++
    }
}

$role = (Select-String -Path (Join-Path $GameDir 'cdmp.ini') -Pattern '^role=(.*)$' -Encoding unicode).Matches[0].Groups[1].Value.Trim()
if ($role -ne 'guest') { Write-Host "  role=$role  ERRADO (deveria ser guest)" -ForegroundColor Red; $bad++ }
else { Write-Host '  role=guest  ok' -ForegroundColor Green }

$peer = (Select-String -Path (Join-Path $GameDir 'cdmp.ini') -Pattern '^peer_steamid=(.*)$' -Encoding unicode).Matches[0].Groups[1].Value.Trim()
if ($peer -ne $PeerSteamId) { Write-Host "  peer_steamid=$peer  ERRADO" -ForegroundColor Red; $bad++ }
else { Write-Host "  peer_steamid=$peer  ok" -ForegroundColor Green }

if ($bad -gt 0) { Fail "$bad verificacoes falharam. NAO abra o jogo antes de resolver." }

Write-Host ''
Write-Host '=== PRONTO ===' -ForegroundColor Green
Write-Host '  Abra o jogo, carregue o save e entre no mundo.'
Write-Host '  Para conferir depois de abrir:'
Write-Host ''
Write-Host '    Select-String -Path "' -NoNewline
Write-Host "$GameDir\cdmp.log" -NoNewline
Write-Host '" -Pattern "Exit watch|Local: pos" | Select-Object -Last 3'
Write-Host ''
