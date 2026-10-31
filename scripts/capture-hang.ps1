# capture-hang.ps1 - captura o travamento do host enquanto ele acontece.
#
# O problema que isto resolve: o jogo NAO morre por excecao, ele TRAVA (confirmado por
# QUATRO eventos AppHangTransient e nenhum APPCRASH - ver docs/DIAGNOSTICO-HANG.md). Um
# travamento nao gera dump de crash, entao ate agora nao havia evidencia nenhuma do
# ponto onde o frame parou.
#
# A vantagem de um travamento sobre um crash e' que o processo fica VIVO e parado por
# varios segundos. Isso da' uma janela para capturar.
#
# LICAO DA PRIMEIRA TENTATIVA, que vale mais que o script: a captura disparada PELO
# AppHang chega tarde demais. O dump que saiu assim tinha 12 GB de memoria real mas o
# diretorio de streams zerado -- MiniDumpWriteDump grava o indice por ultimo, e o
# watchdog encerrou o processo antes disso. Resultado: 12 GB sem ThreadList, sem
# ModuleList e sem Exception, ou seja, sem como achar a pilha.
#
# Por isso agora ha' DOIS modos, e o util e' o primeiro:
#   -Watch  : NAO espera o hang. Fica capturando periodicamente ENQUANTO o jogo roda,
#             mantendo sempre o ultimo dump completo. Quando o travamento acontecer, o
#             dump que interessa ja' esta no disco, gravado com o processo saudavel e o
#             indice intacto. E' o modo que produz evidencia.
#   -Hang   : comportamento antigo (dispara no AppHang). Mantido porque ainda serve
#             para confirmar que o travamento aconteceu, mas o dump tende a sair sem
#             indice.
#
# Nao precisa de admin e nao instala nada. Usa apenas recursos do Windows.
#
# Uso:
#   powershell -ExecutionPolicy Bypass -File .\capture-hang.ps1 -Watch
#   powershell -ExecutionPolicy Bypass -File .\capture-hang.ps1 -Hang
#   (deixe rodando numa janela enquanto joga; Ctrl+C encerra)

[CmdletBinding()]
param(
    [string] $ProcessName = 'CrimsonDesert',
    [string] $OutDir      = "$PSScriptRoot\hang-dumps",
    [int]    $PollMs      = 500,
    [switch] $Watch,
    [switch] $Hang
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $Watch -and -not $Hang) { $Watch = $true }   # -Watch e' o modo que produz evidencia

function Write-Log([string] $msg) {
    $line = "[{0:HH:mm:ss}] {1}" -f (Get-Date), $msg
    Write-Host $line
    Add-Content -Path (Join-Path $OutDir 'capture.log') -Value $line -Encoding UTF8
}

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
public static class Dumper {
    [DllImport("dbghelp.dll", SetLastError=true)]
    static extern bool MiniDumpWriteDump(IntPtr hProcess, uint pid, IntPtr hFile,
        uint dumpType, IntPtr exc, IntPtr user, IntPtr callback);
    public static string Dump(int pid, string path) {
        const uint MiniDumpWithFullMemory   = 0x00000002;
        const uint MiniDumpWithHandleData   = 0x00000004;
        const uint MiniDumpWithThreadInfo   = 0x00001000;
        const uint MiniDumpWithFullMemoryInfo = 0x00000800;
        try {
            using (var p = Process.GetProcessById(pid))
            using (var fs = new FileStream(path, FileMode.Create, FileAccess.Write)) {
                bool ok = MiniDumpWriteDump(p.Handle, (uint)pid, fs.SafeFileHandle.DangerousGetHandle(),
                    MiniDumpWithFullMemory | MiniDumpWithHandleData | MiniDumpWithThreadInfo
                    | MiniDumpWithFullMemoryInfo,
                    IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                return ok ? null : ("Win32 error " + Marshal.GetLastWin32Error());
            }
        } catch (Exception e) { return e.Message; }
    }
}
'@ -ErrorAction Stop

# ---------------------------------------------------------------------------
# -Watch: mantem sempre o ultimo dump COMPLETO enquanto o jogo roda.
# ---------------------------------------------------------------------------
if ($Watch) {
    Write-Log "modo -Watch: capturando periodicamente enquanto '$ProcessName' roda"
    Write-Log "dumps vao para: $OutDir"
    Write-Log "o dump util e' o ULTIMO antes do travamento (indice intacto)."
    Write-Log ''

    $seen = $false
    $last = $null

    while ($true) {
        $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $p) {
            if ($seen) {
                Write-Log 'jogo fechou. ultimo dump completo esta em:'
                if ($last) { Write-Log "   $last" }
                Write-Log 'rode:  .\scripts\dump-threads.ps1 -Dump <esse arquivo>'
                break
            }
            Start-Sleep -Milliseconds $PollMs
            continue
        }

        if (-not $seen) {
            $seen = $true
            Write-Log ("jogo encontrado: pid {0} - comecando a capturar" -f $p.Id)
        }

        $tmp = Join-Path $OutDir ("wip.{0}.dmp" -f $p.Id)
        $err = [Dumper]::Dump($p.Id, $tmp)
        if ($err) {
            Write-Log "captura falhou: $err"
        } else {
            # so' promove se o dump tiver diretorio de streams valido
            $fs = [System.IO.File]::OpenRead($tmp)
            $h = New-Object byte[] 32
            [void]$fs.Read($h, 0, 32)
            $dirRva = [BitConverter]::ToUInt32($h, 12)
            $fs.Seek($dirRva, 'Begin') | Out-Null
            $e0 = New-Object byte[] 12
            [void]$fs.Read($e0, 0, 12)
            $fs.Close()
            $firstType = [BitConverter]::ToUInt32($e0, 0)

            if ($firstType -gt 0 -and $firstType -lt 100) {
                $keep = Join-Path $OutDir ("CrimsonDesert.ok-{0}.dmp" -f (Get-Date -Format 'HHmmss'))
                if ($last -and (Test-Path $last)) { Remove-Item $last -Force -ErrorAction SilentlyContinue }
                Move-Item $tmp $keep -Force
                $last = $keep
                $mb = [math]::Round((Get-Item $keep).Length / 1MB, 1)
                Write-Log ("dump completo OK ({0} MB, primeiro stream tipo {1})" -f $mb, $firstType)
            } else {
                Write-Log 'dump sem indice; descartando e tentando de novo'
                Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            }
        }

        # Espaco: um dump full-memory pode ter 12 GB. Nao capturar em rajada.
        Start-Sleep -Seconds 30
    }
    Write-Log 'fim.'
    return
}

# ---------------------------------------------------------------------------
# -Hang: comportamento antigo, dispara no AppHang.
# ---------------------------------------------------------------------------
Write-Log "modo -Hang: observando '$ProcessName' (Ctrl+C para sair)"
Write-Log "dumps vao para: $OutDir"

# Notepad como "bomba de mensagens" e' desnecessario aqui: Responding ja' e' exposto
# pelo proprio objeto de processo do .NET e reflete se a thread de UI esta' atendendo.
$captured = $false
$seen     = $false

while ($true) {
    $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1

    if (-not $p) {
        if ($seen -and -not $captured) {
            Write-Log "processo desapareceu antes de travar. Sem captura."
            $seen = $false
        }
        Start-Sleep -Milliseconds $PollMs
        continue
    }

    if (-not $seen) {
        $seen = $true
        Write-Log ("jogo encontrado: pid {0}, inicio {1:HH:mm:ss}" -f $p.Id, $p.StartTime)
    }

    # Responding vira $false quando a janela principal para de bombear mensagens,
    # que e' exatamente o que o Windows chama de AppHang.
    if (-not $p.Responding) {
        $pid_ = $p.Id
        Write-Log "TRAVOU (pid $pid_). capturando..."

        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $dmp   = Join-Path $OutDir "CrimsonDesert.$pid_.$stamp.dmp"

        # Caminho 1: Task Manager ja' tem um dump pronto, feito pelo proprio Windows
        # quando detectou o hang. Pega o mais recente.
        $tmDirs = @("$env:LOCALAPPDATA\Temp", "$env:TEMP", "$env:LOCALAPPDATA\CrashDumps")
        $ready = $null
        foreach ($d in $tmDirs) {
            if (-not (Test-Path $d)) { continue }
            $cand = Get-ChildItem $d -Filter '*.DMP' -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) } |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($cand) { $ready = $cand; break }
        }

        if ($ready) {
            Copy-Item $ready.FullName $dmp -Force
            Write-Log "dump do Task Manager copiado: $($ready.Name) -> $(Split-Path $dmp -Leaf)"
            $captured = $true
        }

        # Caminho 2: escrita direta do despejo pelo proprio processo, via
        # MiniDumpWriteDump carregado de dbghelp.dll. Funciona sem procdump e sem
        # admin desde que o processo alvo esteja acessivel.
        if (-not $captured) {
            $err = [Dumper]::Dump($pid_, $dmp)
            if ($err) {
                Write-Log "MiniDumpWriteDump falhou: $err"
            } else {
                $len = (Get-Item $dmp).Length
                Write-Log ("dump gravado: {0} ({1:N1} MB)" -f (Split-Path $dmp -Leaf), ($len/1MB))
                $captured = $true
            }
        }

        if (-not $captured) {
            Write-Log 'nenhum dump automatico saiu desta vez.'
            Write-Log 'captura manual: Gerenciador de Tarefas -> botao direito no processo -> Criar arquivo de despejo'
        }

        # Uma captura basta; o processo vai morrer em seguida e nao queremos enxurrada.
        Write-Log 'aguardando o processo terminar...'
        while (Get-Process -Id $pid_ -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 500 }
        Write-Log 'processo terminou.'
        break
    }

    Start-Sleep -Milliseconds $PollMs
}

Write-Log 'fim.'
