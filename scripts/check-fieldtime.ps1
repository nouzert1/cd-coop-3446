# check-fieldtime.ps1 - descobre se o kFieldTimeClient ainda esta' no lugar.
#
# O problema, em uma frase: kFieldTimeClient e' um global em .bss. Em arquivo ele e'
# ZERO, e zero nao distingue um build do outro -- nao ha conteudo para comparar, nao ha
# xref RIP (o mod le direto com base+offset) e nao ha ponteiro guardado. Por isso ele
# nunca pode ser resolvido por leitura offline, e ficou marcado INFERRED desde 2976.
#
# Mas da' para decidir AO VIVO, e e' isso que este script faz. Com o mundo carregado, o
# FieldTime ou esta' preenchido no endereco esperado, ou nao esta'. Se estiver, o valor
# herdado esta' certo e nada precisa mudar. Se nao estiver, ai' sim precisa remedir.
#
# O que se procura: a struct FieldTime tem campos pequenos de data/hora e um `anchor`
# que e' um timestamp grande. Ler duas vezes com um intervalo e comparar separa "esta'
# la' e andando" de "esta' la' e parado" de "nao esta' la'".
#
# Uso (com o jogo aberto E o mundo carregado, depois de mover o personagem uma vez):
#   powershell -ExecutionPolicy Bypass -File .\check-fieldtime.ps1
#   powershell -ExecutionPolicy Bypass -File .\check-fieldtime.ps1 -Probe <cdmp_probe.exe>

[CmdletBinding()]
param(
    [int]    $Pid_    = 0,
    [string] $Probe   = '',
    [uint32] $Rva     = 0x6EB2AD8,
    [int]    $Samples = 3
)

$ErrorActionPreference = 'Stop'

if (-not $Probe) {
    foreach ($c in @(
        (Join-Path $PSScriptRoot '..\build\bin\RelWithDebInfo\cdmp_probe.exe'),
        (Join-Path $PSScriptRoot 'cdmp_probe.exe'))) {
        if (Test-Path $c) { $Probe = (Resolve-Path $c).Path; break }
    }
}
if (-not $Probe -or -not (Test-Path $Probe)) {
    throw "cdmp_probe.exe nao encontrado. Passe -Probe <caminho>."
}

if (-not $Pid_) {
    $p = Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) { throw 'CrimsonDesert.exe nao esta rodando. Abra o jogo e entre no mundo.' }
    $Pid_ = $p.Id
}

$expr = 'exe+0x{0:X}' -f $Rva
Write-Host "processo $Pid_, lendo $expr"
Write-Host ''

function Read-Block {
    param([string] $E)
    $raw = & $Probe --pid $Pid_ read $E --type u8 --count 32 2>&1
    $bytes = @()
    foreach ($l in $raw) {
        if ($l -match ':\s*\d+ \(0x([0-9A-Fa-f]{1,2})\)') { $bytes += [Convert]::ToByte($matches[1], 16) }
    }
    return ,$bytes
}

$snaps = @()
for ($i = 0; $i -lt $Samples; $i++) {
    $snaps += ,(Read-Block $expr)
    if ($i -lt $Samples - 1) { Start-Sleep -Milliseconds 700 }
}

$first = $snaps[0]
if ($first.Count -lt 32) { throw "leitura curta ($($first.Count) bytes). O processo respondeu?" }

$allzero = -not ($first | Where-Object { $_ -ne 0 })
Write-Host ('bytes: {0}' -f (($first | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
Write-Host ''

# Campo `anchor`: u64. Onde ele cai no layout nao importa para este teste -- o que
# importa e' se existe algum u64 grande no bloco, que e' a assinatura de um timestamp.
$cands = @()
for ($o = 0; $o -le 24; $o++) {
    $v = [BitConverter]::ToUInt64($first, $o)
    # um timestamp em ms desde a epoca fica entre ~2001 e ~2100
    if ($v -ge 1000000000000 -and $v -le 5000000000000) {
        $cands += [pscustomobject]@{ Offset = $o; Value = $v; When = ([DateTimeOffset]::FromUnixTimeMilliseconds([int64]$v).ToLocalTime()) }
    }
}

$changed = $false
for ($i = 1; $i -lt $snaps.Count; $i++) {
    for ($j = 0; $j -lt 32; $j++) {
        if ($snaps[$i][$j] -ne $snaps[0][$j]) { $changed = $true; break }
    }
    if ($changed) { break }
}

Write-Host '=== VEREDITO ==='
if ($allzero) {
    Write-Host '  ZERADO. Duas leituras iguais e tudo zero.'
    Write-Host ''
    Write-Host '  Isto NAO decide sozinho. Duas causas possiveis:'
    Write-Host '    (a) o mundo ainda nao esta carregado - entre no jogo e mova o personagem'
    Write-Host '    (b) o endereco mudou no 3446 e este bloco ficou orfao'
    Write-Host ''
    Write-Host '  Confirme (a) antes de concluir (b): o mod tambem exige movimento, e'
    Write-Host '  kStaticPlayerPos deve ter coordenadas reais se houver sessao.'
} elseif ($cands.Count -gt 0) {
    Write-Host '  ENCONTRADO. Ha um u64 com cara de timestamp no bloco:'
    $cands | ForEach-Object { Write-Host ('    +0x{0,-2} = {1}  ({2:yyyy-MM-dd HH:mm:ss})' -f $_.Offset, $_.Value, $_.When) }
    Write-Host ''
    Write-Host '  Com o mundo carregado e um timestamp plausivel no endereco herdado,'
    Write-Host '  kFieldTimeClient esta CERTO no 3446 e nao precisa ser remedido.'
    if ($changed) { Write-Host '  O bloco tambem mudou entre as leituras - o jogo esta escrevendo nele.' }
    else         { Write-Host '  (O bloco nao mudou entre as leituras; o tempo anda devagar, isso e normal.)' }
} else {
    Write-Host '  NAO-ZERO, mas sem timestamp reconhecivel.'
    Write-Host ''
    Write-Host '  O endereco tem dados, o que sugere que ALGO o usa, mas nao com a'
    Write-Host '  assinatura de FieldTime. Provavelmente mudou de lugar no 3446.'
    Write-Host '  Proximo passo: comparar com o 3424 em runtime, se houver meio de'
    Write-Host '  rodar o build antigo, ou localizar o escritor do tempo no 3446.'
}
Write-Host ''
Write-Host 'Controle (deve ter dado real): kStaticPlayerPos em kWorldSystemSlot vizinho.'
