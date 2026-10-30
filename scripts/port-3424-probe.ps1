# Fase A5: fecha os endereços que faltam no port 3424.
#
# Use com o JOGO ABERTO (a tela de título já basta: o WorldSystem existe desde
# lá). O probe anexa com PROCESS_VM_READ apenas -- é read-only e não pode
# travar nem modificar o jogo.
#
#   cd "C:\Users\ACER\Downloads\Mods\CD-coop-3424"
#   .\scripts\port-3424-probe.ps1
#
# COM O JOGO FECHADO ele ainda faz a parte offline (--image): lê o .exe do disco e
# confere o build, os prólogos de código e os candidatos de RIP. O que ele NÃO
# consegue sem o jogo são os globais que vivem em memória zerada (.bss) -- ler um
# desses do disco não dá nada, porque não há nada lá até o carregador mapear.
# Por isso o script roda as duas partes e diz qual respondeu o quê.
#
# Saída: docs\PORT-3424-probe.txt  (cole esse arquivo de volta na conversa)

param(
    [string]$Process = 'CrimsonDesert.exe',
    [string]$Out = "$PSScriptRoot\..\docs\PORT-3424-probe.txt",
    [string]$Exe = ''
)
$ErrorActionPreference = 'Continue'
$root = Split-Path $PSScriptRoot -Parent
$probe = Join-Path $root 'build\bin\RelWithDebInfo\cdmp_probe.exe'

if (-not (Test-Path $probe)) { throw "Build the project first: $probe not found" }

# Where the game is. Prefer the argument, then the usual Steam locations.
if (-not $Exe) {
    $candidates = @(
        'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64\CrimsonDesert.exe',
        'D:\SteamLibrary\steamapps\common\Crimson Desert\bin64\CrimsonDesert.exe'
    )
    if ($env:CDMP_GAME_DIR) { $candidates = (Join-Path $env:CDMP_GAME_DIR 'CrimsonDesert.exe'), $candidates }
    $Exe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

$running = [bool](Get-Process ($Process -replace '\.exe$','') -ErrorAction SilentlyContinue)
$canImage = $Exe -and (Test-Path $Exe)
if (-not $running -and -not $canImage) {
    throw ("$Process is not running and the exe was not found. Start the game and reach the " +
           "title screen, or pass -Exe <path to CrimsonDesert.exe> for the offline part only.")
}

Set-Content -Path $Out -Value "# cdmp_probe - port 3424 ($(Get-Date -Format s))" -Encoding utf8
"# game running: $running" | Out-File $Out -Append -Encoding utf8
if ($canImage) { "# image: $Exe" | Out-File $Out -Append -Encoding utf8 }
"" | Out-File $Out -Append -Encoding utf8

function Run([string[]]$args_) {
    "### probe $($args_ -join ' ')" | Out-File $Out -Append -Encoding utf8
    $r = & $probe --process $Process @args_ 2>&1
    $r | Out-File $Out -Append -Encoding utf8
    ""
}
Set-Content -Path $Out -Value "# cdmp_probe - port 3424 ($(Get-Date -Format s))" -Encoding utf8
"# game running: $running" | Out-File $Out -Append -Encoding utf8
if ($canImage) { "# image: $Exe" | Out-File $Out -Append -Encoding utf8 }
"" | Out-File $Out -Append -Encoding utf8

function Run([string[]]$args_) {
    "### probe $($args_ -join ' ')" | Out-File $Out -Append -Encoding utf8
    $r = & $probe --process $Process @args_ 2>&1
    $r | Out-File $Out -Append -Encoding utf8
    ""
}

# Offline part (--image). Always available when the exe exists, and the only part
# that works with the game closed.
function RunImage([string[]]$args_) {
    "### probe --image $($args_ -join ' ')" | Out-File $Out -Append -Encoding utf8
    $r = & $probe --image $Exe @args_ 2>&1
    $r | Out-File $Out -Append -Encoding utf8
    ""
}

if ($canImage) {
    "## offline (reads the exe from disk; no game needed)" | Out-File $Out -Append -Encoding utf8
    # 0. Build identity straight from the header.
    RunImage @('info')
    # 0b. The two code addresses co-op cannot work without: their prologues must
    #     be found in the image, and must be the FIRST match.
    RunImage @('scan', '48 89 5C 24 10 4C 89 4C 24 20 55 56 57 41', '--max', '3')  # kClientPostPacket
    RunImage @('scan', '48 89 5C 24 08 48 89 74 24 10 48 89 7C 24', '--max', '3')  # kClientOnRecvPacket
    # 0c. The unresolved clock: the shape of its head, and what each candidate
    #     actually reads. One of these targets is the clock global.
    RunImage @('scan', '80 3D ?? ?? ?? ?? 00 75 17', '--max', '12')
    foreach ($site in '0x561B45', '0xA38986', '0x15F49A0', '0x2E42959', '0x2F09847',
                      '0x300A092', '0x3EAB55B', '0x4019B90', '0x407F3A2') {
        RunImage @('rip', "exe+$site", '--disp', '2')
    }
    # 0d. The one inferred global that lives in file-backed .idata, so it can be
    #     read without the game. The rest are zero-fill and cannot.
    RunImage @('dump', 'exe+6EB2AD8', '--size', '0x30')
    # 0e. Which predicted globals does code actually reach? x64 reads data
    #     RIP-relatively, so a global that is real and used has a displacement
    #     landing on it. The minimap pair is the interesting one: this disassembly
    #     shows both roots selected by a TLS flag, exactly as offsets.h documents.
    foreach ($g in @('0x71AECF8', '0x71AEDE8', '0x71AEDF0', '0x6E973A0',
                     '0x6EC8540', '0x6EB2AD8')) {
        RunImage @('xrefs', $g, '--max', '6')
    }
    RunImage @('disasm', 'exe+0x8DDE3B', '--count', '6')  # the minimap root pair
    RunImage @('disasm', 'exe+0x4E7A040', '--count', '8')  # the Troc range accessor
    ""
}

if (-not $running) {
    "## live part skipped: $Process is not running" | Out-File $Out -Append -Encoding utf8
    "## the globals in zero-filled memory (clock, minimap, world) need the game open." |
        Out-File $Out -Append -Encoding utf8
    Write-Host "Wrote $Out (offline part only; start the game for the live part)"
    Write-Host "Paste that file back into the chat."
    return
}

"## live (attached to the running game)" | Out-File $Out -Append -Encoding utf8

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
