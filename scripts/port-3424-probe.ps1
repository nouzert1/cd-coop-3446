# Fase A5: fecha os endereços que faltam no port 3424.
#
# Use com o JOGO ABERTO (a tela de título já basta: o WorldSystem existe desde
# lá). O probe anexa com PROCESS_VM_READ apenas -- é read-only e não pode
# travar nem modificar o jogo.
#
#   cd "C:\Users\ACER\Downloads\Mods\CD-coop-3424"
#   .\scripts\port-3424-probe.ps1
#
# Saída: docs\PORT-3424-probe.txt  (cole esse arquivo de volta na conversa)

param(
    [string]$Process = 'CrimsonDesert.exe',
    [string]$Out = "$PSScriptRoot\..\docs\PORT-3424-probe.txt"
)
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$probe = Join-Path $root 'build\bin\RelWithDebInfo\cdmp_probe.exe'

if (-not (Test-Path $probe)) { throw "Build the project first: $probe not found" }
if (-not (Get-Process ($Process -replace '\.exe$','') -ErrorAction SilentlyContinue)) {
    throw "$Process is not running. Start the game, reach the title screen, then run this again."
}

function Run([string[]]$args_) {
    "### probe $($args_ -join ' ')" | Out-File $Out -Append -Encoding utf8
    $r = & $probe --process $Process @args_ 2>&1
    $r | Out-File $Out -Append -Encoding utf8
    ""
}
Set-Content -Path $Out -Value "# cdmp_probe - port 3424 ($(Get-Date -Format s))" -Encoding utf8

# 1. Build check: must report the new timestamp as a KNOWN build.
Run @('info')

# 2. The globals we already have -> confirm they are non-zero and point to the
#    right kinds of objects (WorldSystem from the title screen on).
Run @('read','exe+71AEA50','--type','ptr')   # WorldSystem
Run @('read','exe+70CAEB0','--type','ptr')   # Camera
Run @('read','exe+7222280','--type','ptr')   # ActorManager global
Run @('read','exe+70CAB80','--type','ptr')   # Main root

# 3. Follow WorldSystem -> ActorManager -> user actor, and dump the actor's
#    vtable so the controller/status/physics vtables can be pinned.
Run @('chain','exe+71AEA50','0x30')
Run @('dump','exe+71AEA50','--size','0x40')

# 4. RTTI of the object the camera slot points at (needs a loaded save).
Run @('rtti','exe+70CAEB0')

# 5. Candidate resolution for what is still open.
Run @('classes','StatusActorComponent','--max','5')
Run @('classes','CharacterControlActorComponent','--max','5')
Run @('classes','Physics','--max','20')
Run @('classes','Camera','--max','20')

Write-Host "Wrote $Out"
Write-Host "Paste that file back into the chat."
