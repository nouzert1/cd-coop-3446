# ler-cargas.ps1 - le' um cdmp_packets_*.bin e diz o TAMANHO das cargas de ator.
#
# Existe por causa de uma duvida concreta: o teto kMaxLoad de 16 KB (native_suppress.cpp) e
# kMaxLoadSize (enemy_relay.cpp) vem de uma medida do build 1.0.0.2976, "6,6 a 11 KB". Se os
# registros do 3446 engordaram, todo inimigo e' descartado em silencio e o mundo PARECE vazio.
# Ate' agora a unica forma de saber era abrir a captura a mao.
#
# Le' o formato de troc_sniffer.cpp: "CDPK" u32 versao u32 pe_timestamp, depois registros de
# u64 t_us | u8 dir | u8 pad | u16 size | u16 copied | u16 pad | u32 session | u32 thread | data.
#
# Uso:  powershell -File .\ler-cargas.ps1 -Bin <caminho do .bin> [-Max N]

param(
    [Parameter(Mandatory=$true)][string] $Bin,
    [int] $Max = 0
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Bin)) { throw "nao encontrei: $Bin" }

# O jogo mantem a captura aberta enquanto escreve, entao ler direto falha com "sendo usado por
# outro processo". Trabalhamos sobre uma copia. Vale a pena insistir nisso: a captura so' existe
# enquanto o jogo esta' aberto, ou seja, o momento em que ela e' util e' exatamente o momento em
# que ela esta' travada.
$origem = $Bin
$tmp = Join-Path $env:TEMP ("cdmp-ler-" + [IO.Path]::GetFileName($Bin))
Copy-Item $origem $tmp -Force
$Bin = $tmp

$KOpActorLoadDataAck = 2005
$bytes = [IO.File]::ReadAllBytes($Bin)
if ($bytes.Length -lt 16) { Write-Output "arquivo vazio ou curto demais ($($bytes.Length) bytes) - o sniffer ainda nao gravou nada"; return }

$magic = [Text.Encoding]::ASCII.GetString($bytes, 0, 4)
if ($magic -ne 'CDPK') { throw "nao e' uma captura do cdmp (magic '$magic')" }
$ver = [BitConverter]::ToUInt32($bytes, 4)
$pe  = [BitConverter]::ToUInt32($bytes, 8)

Write-Output "captura: $([IO.Path]::GetFileName($origem))"
Write-Output "  formato v$ver, PE 0x$($pe.ToString('X8')), $([math]::Round($bytes.Length/1MB,1)) MB"

$off = 12
$sizes = @{}
$types = @{}
$biggest = 0
$n = 0
$notSold = 0

while ($off + 24 -le $bytes.Length) {
    $t_us   = [BitConverter]::ToUInt64($bytes, $off)
    $dir    = $bytes[$off + 8]
    $size   = [BitConverter]::ToUInt16($bytes, $off + 10)
    $copied = [BitConverter]::ToUInt16($bytes, $off + 12)
    $off += 24
    if ($off + $copied -gt $bytes.Length) { break }
    if ($copied -lt $size) { $notSold++ }

    # So' as cargas de ator do servidor para o cliente
    if ($copied -ge 5 -and $dir -eq 1) {
        $op = [BitConverter]::ToUInt16($bytes, $off)
        if ($op -eq $KOpActorLoadDataAck) {
            $n++
            $payload = $copied - 5
            if ($payload -gt $biggest) { $biggest = $payload }
            $t = $bytes[$off + 7]     # u16 len | u8 type
            if (-not $types.ContainsKey($t)) { $types[$t] = 0 }
            $types[$t]++
            if ($t -eq 3 -or $t -eq 6) {
                if (-not $sizes.ContainsKey($payload)) { $sizes[$payload] = 0 }
                $sizes[$payload]++
            }
        }
    }
    $off += $copied
    if ($Max -gt 0 -and $n -ge $Max) { break }
}

Write-Output ""
Write-Output "cargas ActorLoadDataAck vistas: $n   (truncadas pelo sniffer: $notSold)"
if ($n -eq 0) { Write-Output "  NENHUMA. O sniffer nao ve cargas -- o problema nao e' o teto."; return }

Write-Output ""
Write-Output "por tipo de registro (load[2]):"
foreach ($t in ($types.Keys | Sort-Object)) { Write-Output "  tipo $t : $($types[$t])" }

if ($sizes.Count -gt 0) {
    $vals = $sizes.Keys | Sort-Object
    $tot = ($sizes.Values | Measure-Object -Sum).Sum
    $med = $vals[[int]($vals.Count / 2)]
    Write-Output ""
    Write-Output "tamanho das cargas tipo 3/6 (payload, sem os 5 bytes de cabecalho):"
    Write-Output "  amostras: $tot"
    Write-Output "  menor:    $($vals[0]) bytes"
    Write-Output "  mediana:  $med bytes"
    Write-Output "  maior:    $($vals[-1]) bytes"
    Write-Output ""
    if ($vals[-1] -gt 16384) {
        Write-Output "  >>> O TETO DE 16 KB E' BAIXO DEMAIS: ha' cargas de $($vals[-1]) bytes."
        Write-Output "      kMaxLoad (native_suppress.cpp) e kMaxLoadSize (enemy_relay.cpp) precisam subir."
    } elseif ($vals[-1] -gt 14000) {
        Write-Output "  >>> ATENCAO: a maior e' $($vals[-1]) bytes, perto do teto de 16 KB. Pouca folga."
    } else {
        Write-Output "  ok: a maior e' $($vals[-1]) bytes, com folga ate' 16384. O teto do 2976 ainda serve."
    }
} else {
    Write-Output ""
    Write-Output "  (nenhuma carga tipo 3/6 nesta captura; so' outros tipos)"
}
