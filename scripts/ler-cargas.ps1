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
    # A guarda tem que ser `+ copied` E `>= 12`, porque o payload lido abaixo chega a +7.
    # Sem o `>= 12`, um pacote curto (o menor desta captura tem copied=5) faz a leitura em
    # $p+7 passar do fim do array e derruba o script inteiro com ArgumentException -- o que
    # apareceria como "o analisador nao roda" em vez de "uma carga curta foi pulada".
    if ($off + $copied -gt $bytes.Length) { break }
    if ($copied -lt $size) { $notSold++ }

    # So' as cargas de ator, e SO' do servidor para o cliente.
    #
    # O 2 aqui NAO e' um chute: troc_sniffer.cpp:35 diz `enum class Dir : uint8_t {
    # ClientToServer = 1, ServerToClient = 2 }`. A primeira versao deste script testava
    # `-eq 1` e por isso relatou "cargas vistas: 0" sobre uma captura que tinha 1029 delas --
    # um resultado que parecia uma descoberta (o jogo nao manda cargas no 3446!) e era so' um
    # filtro invertido. A licao vale para o resto: um zero so' significa alguma coisa depois
    # que a ferramenta que o produziu foi conferida contra uma fonte que nao seja ela mesma.
    if ($copied -ge 12 -and $dir -eq 2 -and $off + 7 -le $bytes.Length) {
        # O PAYLOAD COMECA EM $off, NAO EM $off+24 -- a linha 54 ja' avancou $off pelos 24
        # bytes do descritor antes de chegar aqui. A primeira versao desta correcao escreveu
        # `$p = $off + 24` e com isso leu o DESCRITOR DO PROXIMO pacote: o opcode nunca era
        # 2005, a contagem deu 0, e a mensagem impressa foi "o sniffer nao ve cargas" --
        # uma conclusao sobre o JOGO produzida inteiramente por um erro de aritmetica no
        # analisador. E' o mesmo modo de falha das duas correcoes anteriores nesta funcao, e
        # e' por isso que a validacao (len+5==copied em 13890/13890) foi feita ANTES de
        # acreditar no numero, e nao depois.
        # ---------------------------------------------------------------------------------
        # O OPCODE ESTA' NO PAYLOAD, NAO NO DESCRITOR. Este era o bug de verdade, e ele
        # explicava o "tipo 255" -- as outras duas correcoes desta funcao tratavam sintomas.
        #
        # O descritor de 24 bytes NAO TEM OPCODE. Ele e':
        #
        #   +0  u64  t_us        B4 2A A0 BE 0A 00 00 00
        #   +8  u8   dir         01 ou 02
        #   +9  u8   pad         00
        #   +10 u16  size        02 41
        #   +12 u16  copied      02 41
        #   +14 u16  pad
        #   +16 u32  session
        #   +20 u32  thread
        #
        # O pacote Troc comeca em $off+24, e so' ali existe opcode. Ler u16 em $off pegava
        # os dois primeiros bytes de t_us -- que sobem a cada pacote -- e o filtro
        # `-eq 2005` casava por acaso, em ~20 lugares, produzindo uma amostra pequena e
        # incoerente que ainda parecia uma medicao. Foi por isso que a contagem deu 20
        # enquanto o total real era 13890.
        #
        # O layout do PAYLOAD, agora conferido contra o proprio arquivo em 13890 de 13890
        # cargas (len+5 == copied em 100% delas):
        #
        #   +0  u16  opcode       D5 07          = 2005
        #   +2  u8   slot         FF
        #   +3  u16  len          FD 40          -> len + 5 == copied
        #   +5  u8   ...          00
        #   +6  u8   ...          00
        #   +7  u8   type         03 / 06 / 07   <- o type, como native_suppress.cpp le
        #
        # Conferencia nos tres primeiros pacotes grandes: (16637,16642) (23082,23087)
        # (6843,6848) -- len+5 == copied nos tres. A validacao esta' no comentario da
        # versao porque foi ela, e nao uma leitura de codigo, que fechou o caso.
        $p  = $off
        $op = [BitConverter]::ToUInt16($bytes, $p)
        if ($op -eq $KOpActorLoadDataAck) {
            $n++
            $payload = $copied - 5
            if ($payload -gt $biggest) { $biggest = $payload }
            $t = $bytes[$p + 7]
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
