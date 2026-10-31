# dump-threads.ps1 - le um minidump e mostra as pilhas das threads.
#
# Escrito porque nao ha ferramenta de debugging instalada nesta maquina (nem cdb, nem
# windbg, nem procdump) e o dump e' a unica evidencia real que existe do travamento.
# O formato MINIDUMP e' documentado e estavel, entao da' para ler direto.
#
# O que interessa aqui NAO e' uma pilha bonita com nomes de funcao - e' descobrir
# QUAIS threads existem, qual e' a principal, e em que endereco cada uma parou. Com os
# enderecos em maos, o modulo e o RVA saem por subtracao da base, e o RVA e' o que o
# cdmp_probe sabe traduzir.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\dump-threads.ps1 -Dump <arquivo.dmp>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string] $Dump,
    [int] $MaxThreads = 20
)

$ErrorActionPreference = 'Stop'

# MINIDUMP_STREAM_TYPE
$StreamThreadList   = 3
$StreamModuleList   = 4
$StreamException    = 6
$StreamSystemInfo   = 7
$StreamMemory64List = 9

$fs = [System.IO.File]::OpenRead($Dump)
try {
    $hdr = New-Object byte[] 32
    [void]$fs.Read($hdr, 0, 32)
    $sig = [Text.Encoding]::ASCII.GetString($hdr, 0, 4)
    if ($sig -ne 'MDMP') { throw "nao e' um minidump (assinatura '$sig')" }

    $nStreams = [BitConverter]::ToUInt32($hdr, 8)
    $dirRva   = [BitConverter]::ToUInt32($hdr, 12)

    # Diretorio de streams
    $fs.Seek($dirRva, 'Begin') | Out-Null
    $streams = @{}
    for ($i = 0; $i -lt $nStreams; $i++) {
        $e = New-Object byte[] 12
        if ($fs.Read($e, 0, 12) -lt 12) { break }
        $t  = [BitConverter]::ToUInt32($e, 0)
        $sz = [BitConverter]::ToUInt32($e, 4)
        $rv = [BitConverter]::ToUInt32($e, 8)
        if ($sz -gt 0) { $streams[[int]$t] = @{ Size = $sz; Rva = $rv } }
    }

    Write-Host "streams presentes: $(($streams.Keys | Sort-Object) -join ', ')"
    Write-Host ''

    # ---- modulos (base + tamanho + nome) ---------------------------------
    $mods = @()
    if ($streams.ContainsKey($StreamModuleList)) {
        $s = $streams[$StreamModuleList]
        $fs.Seek($s.Rva, 'Begin') | Out-Null
        $cntB = New-Object byte[] 4
        [void]$fs.Read($cntB, 0, 4)
        $count = [BitConverter]::ToUInt32($cntB, 0)
        for ($i = 0; $i -lt $count; $i++) {
            # MINIDUMP_MODULE = 108 bytes
            $m = New-Object byte[] 108
            if ($fs.Read($m, 0, 108) -lt 108) { break }
            $base = [BitConverter]::ToUInt64($m, 0)
            $size = [BitConverter]::ToUInt32($m, 8)
            $nameRva = [BitConverter]::ToUInt32($m, 20)
            $name = ''
            if ($nameRva) {
                $save = $fs.Position
                $fs.Seek($nameRva, 'Begin') | Out-Null
                $lb = New-Object byte[] 4
                [void]$fs.Read($lb, 0, 4)
                $len = [BitConverter]::ToUInt32($lb, 0)
                if ($len -gt 0 -and $len -lt 4096) {
                    $nb = New-Object byte[] $len
                    [void]$fs.Read($nb, 0, $len)
                    $name = [Text.Encoding]::Unicode.GetString($nb).TrimEnd([char]0)
                }
                $fs.Seek($save, 'Begin') | Out-Null
            }
            $mods += [pscustomobject]@{ Base = $base; Size = $size; Name = $name }
        }
    }
    Write-Host "modulos: $($mods.Count)"
    Write-Host ''

    function Resolve-Addr([uint64] $addr) {
        foreach ($m in $mods) {
            if ($addr -ge $m.Base -and $addr -lt ($m.Base + $m.Size)) {
                $leaf = Split-Path $m.Name -Leaf
                return [pscustomobject]@{
                    Module = $leaf
                    Rva    = $addr - $m.Base
                    Text   = ('{0}+0x{1:X}' -f $leaf, ($addr - $m.Base))
                }
            }
        }
        return [pscustomobject]@{ Module = '?'; Rva = 0; Text = ('0x{0:X}' -f $addr) }
    }

    # ---- excecao (se houver) ---------------------------------------------
    if ($streams.ContainsKey($StreamException)) {
        $s = $streams[$StreamException]
        $fs.Seek($s.Rva, 'Begin') | Out-Null
        $eb = New-Object byte[] 168
        [void]$fs.Read($eb, 0, 168)
        $tid  = [BitConverter]::ToUInt32($eb, 4)
        $code = [BitConverter]::ToUInt32($eb, 8)
        $addr = [BitConverter]::ToUInt64($eb, 24)
        Write-Host '=== EXCECAO ==='
        Write-Host ("  thread    : {0}" -f $tid)
        Write-Host ("  code      : 0x{0:X8}" -f $code)
        Write-Host ("  address   : {0}" -f (Resolve-Addr $addr).Text)
        Write-Host ''
    } else {
        Write-Host '=== SEM STREAM DE EXCECAO ==='
        Write-Host '  Nenhuma excecao foi capturada - consistente com travamento,'
        Write-Host '  nao com crash. Um crash teria este stream preenchido.'
        Write-Host ''
    }

    # ---- threads ----------------------------------------------------------
    if ($streams.ContainsKey($StreamThreadList)) {
        $s = $streams[$StreamThreadList]
        $fs.Seek($s.Rva, 'Begin') | Out-Null
        $cb = New-Object byte[] 4
        [void]$fs.Read($cb, 0, 4)
        $count = [BitConverter]::ToUInt32($cb, 0)
        Write-Host "=== THREADS: $count ==="

        $rows = @()
        for ($i = 0; $i -lt $count; $i++) {
            # MINIDUMP_THREAD = 48 bytes
            $t = New-Object byte[] 48
            if ($fs.Read($t, 0, 48) -lt 48) { break }
            $tid      = [BitConverter]::ToUInt32($t, 0)
            $suspend  = [BitConverter]::ToUInt32($t, 4)
            $prioCls  = [BitConverter]::ToUInt32($t, 8)
            $prio     = [BitConverter]::ToUInt32($t, 12)
            $teb      = [BitConverter]::ToUInt64($t, 16)

            # MINIDUMP_MEMORY_DESCRIPTOR do stack = 16 bytes em +24
            $stackRva = [BitConverter]::ToUInt32($t, 32)

            # No topo do stack esta' o contexto (CONTEXT x64, com M128A etc). O campo
            # Rip fica em offset 0xF8 do CONTEXT a partir do inicio dos registros
            # inteiros. Em vez de depender disso, procuro o primeiro endereco do
            # stack que caia dentro de um modulo executavel - e' o return address
            # mais provavel e ja' aponta para codigo real.
            $top = $null
            if ($stackRva) {
                $save = $fs.Position
                $fs.Seek($stackRva, 'Begin') | Out-Null
                $mb = New-Object byte[] 16
                [void]$fs.Read($mb, 0, 16)
                $start = [BitConverter]::ToUInt64($mb, 0)
                $fs.Seek($save, 'Begin') | Out-Null
                $top = $start
            }

            $rows += [pscustomobject]@{
                Tid     = $tid
                Suspend = $suspend
                Priority= $prio
                Teb     = $teb
                Stack   = $top
                StackTxt= if ($top) { (Resolve-Addr $top).Text } else { '-' }
            }
        }

        # Ordena pondo as threads que pararam dentro de modulos reconhecidos primeiro
        $rows | Sort-Object { if ($_.StackTxt -eq '-') { 1 } else { 0 } }, Tid |
            Select-Object -First $MaxThreads |
            Format-Table Tid, Suspend, Priority, StackTxt -AutoSize
    }
}
finally {
    $fs.Close()
}
