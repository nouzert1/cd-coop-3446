# instalar-host.ps1 - poe o cdmp.asi recem-compilado na pasta do jogo do host.
#
# Existe porque isto foi feito a mao varias vezes e a mao da' errado de duas formas:
# copiar com o jogo aberto falha com "sendo usado por outro processo" (e um `-Force` num
# script que ignora o erro deixa o build velho la', silenciosamente), e nao havia backup
# antes de sobrescrever.
#
# Faz tres coisas, e as tres importam:
#   1. confere que o jogo esta' FECHADO -- se estiver aberto, para e explica, em vez de
#      falhar no meio;
#   2. faz backup do cdmp.asi atual com carimbo de tempo antes de trocar;
#   3. confere o SHA256 DEPOIS da copia, comparando com o da origem. Um `Copy-Item` que
#      retorna sem erro nao prova que o arquivo no destino e' o novo -- ja' aconteceu
#      nesta portagem de o destino ficar com o build anterior.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\instalar-host.ps1
#   powershell -ExecutionPolicy Bypass -File .\instalar-host.ps1 -GameBin "D:\...\bin64"

[CmdletBinding()]
param(
    [string] $Source  = '',
    [string] $GameBin = 'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64',
    [switch] $Force
)

$ErrorActionPreference = 'Stop'

if (-not $Source) {
    foreach ($c in @(
        (Join-Path $PSScriptRoot '..\build\bin\RelWithDebInfo\cdmp.asi'),
        (Join-Path $PSScriptRoot 'cdmp.asi'))) {
        if (Test-Path $c) { $Source = (Resolve-Path $c).Path; break }
    }
}
if (-not $Source -or -not (Test-Path $Source)) { throw 'cdmp.asi de origem nao encontrado. Passe -Source <caminho>.' }
if (-not (Test-Path $GameBin)) { throw "a pasta do jogo nao existe: $GameBin" }

$dst = Join-Path $GameBin 'cdmp.asi'

# 1. o jogo tem que estar fechado
$proc = Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "CrimsonDesert.exe esta' rodando (pid $($proc.Id -join ', '))." -ForegroundColor Yellow
    Write-Host ''
    Write-Host 'O jogo mantem o cdmp.asi aberto, entao a copia falha com "sendo usado por'
    Write-Host 'outro processo". Feche o jogo e rode de novo.'
    Write-Host ''
    Write-Host 'Se preferir, -Force encerra o processo agora. Nao faca isso com o jogo'
    Write-Host 'salvando: use o menu do jogo.'
    if (-not $Force) { exit 2 }
    Write-Host 'Encerrando o jogo (-Force)...' -ForegroundColor Yellow
    $proc | Stop-Process -Force
    Start-Sleep -Seconds 3
    if (Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue) { throw 'o jogo nao encerrou' }
}

# 2. backup
if (Test-Path $dst) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = "$dst.bak-$stamp"
    Copy-Item $dst $bak -Force
    Write-Host "backup: $(Split-Path $bak -Leaf)"
}

# 3. copia e confere
$want = (Get-FileHash $Source -Algorithm SHA256).Hash
Copy-Item $Source $dst -Force
$got = (Get-FileHash $dst -Algorithm SHA256).Hash

Write-Host ''
Write-Host "origem : $want"
Write-Host "destino: $got"
if ($got -ne $want) {
    throw "o arquivo no destino NAO e' o novo (a copia nao pegou). O build no jogo continua o antigo."
}
Write-Host "instalado: $dst" -ForegroundColor Green

# O host tem que estar em role=host e sem peer fixo: quem procura o parceiro e' o
# convidado. Conferir aqui evita a sessao em que os dois ficam esperando um pelo outro.
$ini = Join-Path $GameBin 'cdmp.ini'
if (Test-Path $ini) {
    $role = (Get-Content $ini -Encoding Unicode | Select-String '^\s*role\s*=' | Select-Object -First 1)
    $peer = (Get-Content $ini -Encoding Unicode | Select-String '^\s*peer_steamid\s*=' | Select-Object -First 1)
    Write-Host ''
    Write-Host "cdmp.ini: $($role.Line.Trim()) | $($peer.Line.Trim())"
    if ($role -and $role.Line -notmatch 'host') {
        Write-Host 'AVISO: este PC nao esta como role=host. O host e quem abre o mundo.' -ForegroundColor Yellow
    }
} else {
    Write-Host ''
    Write-Host "AVISO: nao ha cdmp.ini em $GameBin. O mod vai usar os padroes" -ForegroundColor Yellow
    Write-Host '(e o padrao de [coop] enabled e 0, entao o co-op nao liga sozinho).'
}

Write-Host ''
Write-Host 'Pronto. Os DOIS PCs precisam do mesmo build: a versao do protocolo mudou'
Write-Host 'para 10, e um kit antigo simplesmente nao conecta.'
