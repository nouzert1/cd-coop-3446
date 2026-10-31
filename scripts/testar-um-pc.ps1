# testar-um-pc.ps1 - exercita o relay de inimigos e o combate de jefe SOZINHO, num PC.
#
# Por que isto existe
# -------------------
# O objetivo do mod tem um ponto que ficou travado por muitas rodadas: "so' da' para
# validar com 2 PCs". Isso e' verdade para a REDE (dois SteamIDs, dois mundos), mas NAO e'
# verdade para o CAMINHO DO JOGO. O cdmp_peer.exe existe desde o comeco do projeto e faz
# eco: manda os seus proprios dados de volta para voce, com atraso. Nesse modo este PC e'
# anfitriao E convidado ao mesmo tempo, e todo o codigo de copia, relevo e regras de jefe e'
# exercitado de verdade -- que e' onde os defeitos de verdade vivem.
#
# O que ele NAO prova (e' honesto dizer): dois mundos separados, dois SteamIDs, o mundo do
# convidado sem a etapa do jefe, e a latencia real de internet. Ver
# docs/research/pendiente-jefes.md secao 6, "Lo que el eco no prueba".
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\testar-um-pc.ps1 -Prepare
#       -> poe o cdmp.ini em transporte udp/eco e faz backup do save
#   powershell -ExecutionPolicy Bypass -File .\testar-um-pc.ps1 -Run
#       -> sobe o cdmp_peer, vigia o cdmp.log e resume o que apareceu
#   powershell -ExecutionPolicy Bypass -File .\testar-um-pc.ps1 -Restore
#       -> volta o cdmp.ini para steam/host

[CmdletBinding()]
param(
    [switch] $Prepare,
    [switch] $Run,
    [switch] $Restore,
    [int]    $Seconds = 900,
    [string] $GameBin = 'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64',
    [string] $Peer    = ''
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot e' ...\scripts, entao o repositorio e' um nivel acima. Sem o '..' a busca
# do cdmp_peer e do build falha e o script morre com "argumento vazio" -- que nao diz nada
# sobre a causa real.
$root = Split-Path $PSScriptRoot -Parent
if (-not $Peer) {
    foreach ($c in @((Join-Path $root 'build\bin\RelWithDebInfo\cdmp_peer.exe'),
                     (Join-Path $PSScriptRoot 'cdmp_peer.exe'),
                     (Join-Path $root 'cdmp_peer.exe'),
                     (Join-Path $root 'dist\cdmp-3446-test-kit\diagnostico\cdmp_peer.exe'))) {
        if (Test-Path $c) { $Peer = $c; break }
    }
}
$ini = Join-Path $GameBin 'cdmp.ini'
$log = Join-Path $GameBin 'cdmp.log'
$mark = Join-Path $GameBin 'cdmp.ini.coop-steam-host'

function Backup-Save {
    $save = Join-Path $env:LOCALAPPDATA 'Pearl Abyss\CD\save'
    if (-not (Test-Path $save)) { Write-Host "save nao encontrado em $save" -ForegroundColor Yellow; return }
    $dst = Join-Path $root ('backups\save-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Copy-Item (Join-Path $save '*') $dst -Recurse -Force
    $n = (Get-ChildItem $dst -Recurse -File).Count
    Write-Host "backup do save: $n arquivos em $dst" -ForegroundColor Green
}

if ($Prepare) {
    if (-not (Test-Path $ini)) { throw "nao ha $ini" }
    # O save e' tocado por qualquer teste que envolva morte de inimigo ou de jefe. Fazer o
    # backup aqui, e nao no -Run, e' de proposito: o backup tem que existir ANTES de o jogo
    # ser aberto, nao depois de algo dar errado.
    Backup-Save
    if (-not (Test-Path $mark)) { Copy-Item $ini $mark -Force }
    $t = Get-Content $ini -Encoding Unicode
    $t = $t -replace '^\s*transport\s*=.*', 'transport=udp'
    $t = $t -replace '^\s*role\s*=.*',      'role=guest'
    $t = $t -replace '^\s*offset_m\s*=.*',  'offset_m=2'
    # suppress=dry: com o eco este PC e' anfitriao e convidado, e o mod forca o ensaio seco.
    # Escrever nada no mundo e' o ponto -- o teste mede o que SERIA copiado.
    if ($t -notmatch '^\s*suppress\s*=') {
        $t = $t -replace '(?m)^(enemy_auto=.*)$', "`$1`r`nsuppress=dry"
    }
    $t | Set-Content $ini -Encoding Unicode
    Write-Host ''
    Write-Host 'cdmp.ini preparado para teste num PC:' -ForegroundColor Green
    Get-Content $ini -Encoding Unicode | Select-String '^\s*(transport|role|offset_m|enemy_auto|suppress|guest_hits|boss_safe|guest_loot)\s*=' |
        ForEach-Object { Write-Host "  $($_.Line.Trim())" }
    Write-Host ''
    # Isto e' a armadilha que faz o teste parecer quebrado. load_config roda UMA vez, no
    # boot do mod (mod.cpp:836), e o Config fica guardado. Com o jogo ja' aberto, mudar o
    # cdmp.ini nao muda nada -- o mod continua em transporte steam e o resumo sai todo vazio,
    # o que se le como "o codigo nao funciona" quando na verdade a config nova nunca foi
    # lida. Dizer isto aqui e' mais barato que alguem descobrir isso do jeito dificil.
    if (Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue) {
        Write-Host 'ATENCAO: o jogo esta ABERTO.' -ForegroundColor Yellow
        Write-Host 'O mod le o cdmp.ini UMA vez, no boot. Com o jogo aberto esta config NAO vale:'
        Write-Host 'ele continua em transporte steam e o resumo vai sair vazio.'
        Write-Host ''
        Write-Host '  FECHE o jogo e abra de novo (carregue o save) ANTES de rodar -Run.' -ForegroundColor Yellow
    } else {
        Write-Host 'Agora: abra o jogo, carregue o save, e rode -Run noutra janela.'
    }
    exit 0
}

if ($Restore) {
    if (Test-Path $mark) {
        Copy-Item $mark $ini -Force
        Write-Host 'cdmp.ini restaurado para steam/host.' -ForegroundColor Green
    } else {
        Write-Host "nao ha $mark para restaurar" -ForegroundColor Yellow
    }
    exit 0
}

if (-not $Run) {
    Write-Host 'Use um destes:'
    Write-Host '  -Prepare   poe o cdmp.ini em transporte udp (eco) e faz backup do save'
    Write-Host '  -Run       sobe o cdmp_peer e resume o que o cdmp.log mostrou'
    Write-Host '  -Restore   volta o cdmp.ini para steam/host'
    exit 0
}

if (-not (Test-Path $Peer)) { throw "cdmp_peer.exe nao encontrado; passe -Peer <caminho>" }
if (-not (Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue)) {
    Write-Host 'O jogo nao esta aberto. Abra, carregue o save e rode de novo.' -ForegroundColor Yellow
    exit 2
}

# O mod guarda o Config lido no boot. Se o cdmp.ini no disco nao for o que o processo em
# execucao leu, o teste produz um resumo vazio -- e um resumo vazio se le como "o codigo
# nao funciona", que e' a conclusao errada. Conferir antes custa uma linha e evita que a
# sessao inteira seja jogada fora.
$nett = (Get-Content $ini -Encoding Unicode | Select-String '^\s*transport\s*=\s*(\S+)' | Select-Object -First 1)
if ($nett -and $nett.Matches[0].Groups[1].Value -ne 'udp') {
    Write-Host "AVISO: o cdmp.ini diz transport=$($nett.Matches[0].Groups[1].Value), nao udp." -ForegroundColor Yellow
    Write-Host 'Rode -Prepare primeiro, e ele explica o que fazer com o jogo aberto.'
}

# Marca onde o log estava, para resumir so o que esta sessao produziu. Sem isto o resumo
# mistura sessoes antigas e o resultado fica pior que inutil.
$logStart = 0
if (Test-Path $log) { $logStart = (Get-Item $log).Length }

Write-Host "subindo: $Peer --mode relay --delay 50 --offset 2" -ForegroundColor Cyan

# Um cdmp_peer de uma sessao anterior fica orfao com facilidade -- basta fechar a janela em
# vez de usar Ctrl+C. Ele continua segurando a porta 37015, e o novo processo sobe, falha ao
# escutar e sai na hora. O sintoma e' enganoso: Start-Process devolve um objeto com Id nulo,
# e o script morre com "nao e' possivel associar o argumento 'Id' porque ele e' nulo", que
# nao diz nada sobre a causa. Limpar antes e' mais barato que diagnosticar isso de novo.
$stale = Get-Process -Name cdmp_peer -ErrorAction SilentlyContinue
if ($stale) {
    Write-Host "havia $($stale.Count) cdmp_peer de uma sessao anterior; encerrando (a porta 37015 estaria ocupada)" -ForegroundColor Yellow
    $stale | Stop-Process -Force
    Start-Sleep -Seconds 1
}

$peer = Start-Process -FilePath $Peer -ArgumentList @('--mode','relay','--delay','50','--offset','2') -PassThru
if (-not $peer) { throw 'nao consegui subir o cdmp_peer' }
# .Id logo apos a criacao pode ainda estar vazio se o processo sair na largada; esperar um
# instante e conferir por nome da' um erro que se entende.
Start-Sleep -Milliseconds 500
$peerId = $peer.Id
if (-not $peerId) {
    $live = Get-Process -Name cdmp_peer -ErrorAction SilentlyContinue
    if (-not $live) { throw 'o cdmp_peer saiu assim que subiu (porta ocupada ou modo invalido)' }
    $peerId = $live[0].Id
}
Write-Host "cdmp_peer pid $peerId. Rodando por $Seconds s."
Write-Host ''
Write-Host 'O QUE FAZER AGORA (nesta ordem):'
Write-Host '  1. ande um pouco -- a sua copia deve aparecer (prova o laco de estado)'
Write-Host '  2. va ao acampamento Bleed Bandits em (-10284, 640, -3383)'
Write-Host '     -> o relay deve dizer o que COPIARIA (ensaio seco)'
Write-Host '  3. se achar um jefe de encontro, bata nele algumas vezes'
Write-Host '     -> e o caso B0/B2: mede o tipo de registro e as regras de jefe'
Write-Host '  4. saia SEM SALVAR quando terminar'
Write-Host ''
Write-Host 'vigiando o log. Ctrl+C aqui encerra o cdmp_peer.' -ForegroundColor DarkGray

$patterns = @{
    'copia apareceu'      = 'other player is in our world|Puppet: (spawned|queued)|copy .* created'
    'zona de inimigos'    = 'enemy zone ON|zone ON'
    'o que COPIARIA'      = 'WOULD SWEEP|WOULD DROP'
    'inimigo copiado'     = 'Enemy relay: enemy copy'
    'copia morreu'        = 'copy 0x[0-9A-F]+ (died|removed)'
    'golpe do convidado'  = 'GuestHit|guest hit|blow'
    'regras de jefe'      = 'boss: |boss_is_boss|boss safe|boss rules'
    'bandeira de jefe'    = 'flagged as a boss'
    'loot (gemeo)'        = 'twin|loot'
    # Ancorado: a linha de estado periodica tambem contem as palavras "refused" e
    # "rejected", entao um padrao solto casava com ela a cada 5 s e enchia o resumo de
    # ruido, escondendo os avisos de verdade.
    'recusado'            = 'malformed|refused by|ignored|reject(ed)? the'
}
$seen = @{}
foreach ($k in $patterns.Keys) { $seen[$k] = @() }

$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    # Get-Process por id, e nao $peer.HasExited: um objeto Process em cache continua a
    # dizer que o programa vive depois de ele sair, a nao ser que se chame Refresh(). A
    # consulta por id e' sempre atual e nao depende disso.
    if (-not (Get-Process -Id $peerId -ErrorAction SilentlyContinue)) {
        Write-Host 'cdmp_peer saiu.' -ForegroundColor Yellow
        break
    }
    Start-Sleep -Seconds 5
    if (-not (Test-Path $log)) { continue }
    $fs = [System.IO.File]::Open($log, 'Open', 'Read', 'ReadWrite')
    try {
        $fs.Seek($logStart, 'Begin') | Out-Null
        $sr = New-Object System.IO.StreamReader($fs)
        $text = $sr.ReadToEnd(); $sr.Close()
    } finally { $fs.Close() }
    $logStart = (Get-Item $log).Length
    foreach ($line in ($text -split "`r?`n")) {
        # As linhas de estado periodicas (Net:, Local:, co-op:, Overlay:) saem a cada 5 s e
        # casam com varios padroes por acidente -- "refused", "loot", "copy". Sem as tirar,
        # o resumo mostra seis linhas identicas e nenhuma informacao.
        if ($line -match '\] (INF|WRN) \[T\d+\] (Net|Local|co-op|Overlay|Config|Time):') { continue }
        foreach ($k in $patterns.Keys) {
            if ($line -match $patterns[$k] -and $seen[$k].Count -lt 6) {
                $seen[$k] += $line.Trim()
                Write-Host ("  [{0}] {1}" -f $k, $line.Trim()) -ForegroundColor Gray
            }
        }
    }
}

if (Get-Process -Id $peerId -ErrorAction SilentlyContinue) {
    Stop-Process -Id $peerId -Force
    Write-Host 'cdmp_peer encerrado.'
}

Write-Host ''
Write-Host '=========== RESUMO ===========' -ForegroundColor Cyan
foreach ($k in $patterns.Keys) {
    $n = $seen[$k].Count
    $c = if ($n -gt 0) { 'Green' } else { 'DarkGray' }
    Write-Host ("  {0,-20} {1}" -f $k, $(if ($n) { "$n linha(s)" } else { 'nada' })) -ForegroundColor $c
}
Write-Host ''
Write-Host "log completo: $log"
Write-Host 'Quando terminar: -Restore para voltar a steam/host.'
