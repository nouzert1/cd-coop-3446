<#
  Final-test watcher. Captures everything, automatically, and writes a single verdict file.

  This runs for the test that decides whether the project continues. Two consequences shape
  it:

    * Nothing may be lost. The 31 Oct crashes rotated their own logs away and their dumps
      sat unnoticed for an hour. Every capture here happens at the moment of death, into a
      folder named for the time, and the folder is never reused.

    * The answer must be readable without me. When the test ends, VEREDITO.txt says what
      happened in plain words, including the case where nothing happened at all -- because
      "the games opened, we saw each other, nothing crashed" is a result and should not
      have to be reconstructed from a log.

  Read-only with respect to the game: it never touches the running process.
#>

$g    = 'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64'
$log  = Join-Path $g 'cdmp.log'
$base = 'C:\Users\ACER\Desktop\CD-TESTE-FINAL'
$out  = Join-Path $base 'andamento.txt'

New-Item -ItemType Directory $base -Force | Out-Null
"=== vigia do teste final: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss') ===" |
    Set-Content $out -Encoding UTF8

$wasAlive   = $false
$started    = $null
$lastPid    = 0
$sessions   = 0
$deaths     = 0
$sawWatch   = $false
$sawPos     = $false
$sawPuppet  = $false
$sawConnect = $false
$sawMismatch= $false
$build      = ''
$deathsInfo = New-Object System.Collections.ArrayList

for ($i = 0; $i -lt 1800; $i++) {
    $p = Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue
    $t = (Get-Date).ToString('HH:mm:ss')

    if ($p) {
        if (-not $wasAlive) {
            $sessions++
            $lastPid = $p.Id
            $started = Get-Date
            "  $t  ABRIU (sessao $sessions, pid $lastPid)" | Add-Content $out -Encoding UTF8
        }
        $wasAlive = $true

        if (Test-Path $log) {
            try {
                $fs = New-Object IO.FileStream($log, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()

                foreach ($l in ($txt -split "`r?`n")) {
                    if ($l -match 'Multiplayer 0\.2\.0 \(build ([0-9A-Fa-f]{8})') {
                        if ($build -ne $matches[1]) {
                            $build = $matches[1]
                            "  $t  [BUILD] $build" | Add-Content $out -Encoding UTF8
                        }
                    }
                    if ($l -match 'Exit watch: TerminateProcess hooked' -and -not $sawWatch) {
                        $sawWatch = $true
                        "  $t  [EXIT WATCH OK]" | Add-Content $out -Encoding UTF8
                    }
                    if ($l -match 'Exit watch:.*FAILED') {
                        "  $t  [EXIT WATCH FALHOU] $l" | Add-Content $out -Encoding UTF8
                    }
                    if ($l -match 'Local: pos \(-?[0-9]') {
                        if (-not $sawPos) { $sawPos = $true; "  $t  [POSICAO OK - entrou no mundo]" | Add-Content $out -Encoding UTF8 }
                    }
                    if ($l -match 'Puppet: spawn queued') {
                        if (-not $sawPuppet) { $sawPuppet = $true; "  $t  [BONECO CRIADO] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8 }
                    }
                    if ($l -match 'other player loaded') {
                        "  $t  [VIU O OUTRO JOGADOR] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                    }
                    if ($l -match 'Net: connected' -and -not $sawConnect) {
                        $sawConnect = $true; "  $t  [CONECTOU]" | Add-Content $out -Encoding UTF8
                    }
                    if ($l -match 'runs mod build|update both to the same') {
                        if (-not $sawMismatch) { $sawMismatch = $true; "  $t  [VERSAO DIFERENTE] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8 }
                    }
                    if ($l -match 'spawn refused') {
                        "  $t  [SPAWN RECUSADO] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                    }
                    if ($l -match 'Exit: Terminate|Exit: ExitProcess|Exit: RtlExit') {
                        "  $t  >>> SAIDA REGISTRADA: $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                    }
                }
            } catch {}
        }
    } else {
        if ($wasAlive) {
            $dur = [int]((Get-Date) - $started).TotalSeconds
            $deaths++
            "  $t  *** FECHOU (sessao $sessions, durou ${dur}s) ***" | Add-Content $out -Encoding UTF8
            [void]$deathsInfo.Add([pscustomobject]@{ when = $t; pid = $lastPid; secs = $dur })

            Start-Sleep -Seconds 2
            $cap = Join-Path $base "morte-$((Get-Date).ToString('HHmmss'))"
            New-Item -ItemType Directory $cap -Force | Out-Null
            foreach ($f in (Get-ChildItem $g -Filter 'cdmp*.log' -ErrorAction SilentlyContinue)) {
                Copy-Item $f.FullName (Join-Path $cap $f.Name) -Force -ErrorAction SilentlyContinue
            }
            foreach ($d in (Get-ChildItem "$env:LOCALAPPDATA\CrashDumps" -Filter 'CrimsonDesert*' -ErrorAction SilentlyContinue)) {
                Copy-Item $d.FullName (Join-Path $cap $d.Name) -Force -ErrorAction SilentlyContinue
            }
            foreach ($w in @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
                             "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive")) {
                if (-not (Test-Path $w)) { continue }
                Get-ChildItem $w -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $started -and $_.Name -like '*CrimsonDesert*' } |
                    ForEach-Object { Copy-Item $_.FullName (Join-Path $cap $_.Name) -Recurse -Force -ErrorAction SilentlyContinue }
            }
            $n = (Get-ChildItem $cap -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
            "       -> $n arquivos guardados em $cap" | Add-Content $out -Encoding UTF8
            $wasAlive = $false
        }
    }
    Start-Sleep -Seconds 2
}

# ---------------------------------------------------------------------------- verdict
$v = Join-Path $base 'VEREDITO.txt'
$lines = @()
$lines += "TESTE FINAL - build $build - $(Get-Date -Format 'dd/MM/yyyy HH:mm')"
$lines += ("-" * 66)
$lines += ""
$lines += "sessoes do jogo abertas : $sessions"
$lines += "vezes que o jogo fechou : $deaths"
$lines += ""
$lines += "RESPOSTAS:"
$lines += "  Exit watch instalou       : $(if($sawWatch){'SIM'}else{'NAO'})"
$lines += "  Entrou no mundo (posicao) : $(if($sawPos){'SIM'}else{'NAO'})"
$lines += "  Conectou com o outro      : $(if($sawConnect){'SIM'}else{'NAO'})"
$lines += "  Boneco do outro apareceu  : $(if($sawPuppet){'SIM'}else{'NAO'})"
$lines += "  Versao diferente detectada: $(if($sawMismatch){'SIM'}else{'NAO'})"
$lines += ""
$lines += "O QUE ISSO QUER DIZER:"
if ($sawPuppet) {
    $lines += "  FUNCIONOU. Os dois personagens apareceram no mundo um do outro."
} elseif ($sawConnect -and $sawPos) {
    $lines += "  PARCIAL. Os dois entraram no mundo e se conectaram, mas o boneco"
    $lines += "  do outro nao apareceu. A conexao esta' boa; o spawn e' que falhou."
} elseif ($sawPos) {
    $lines += "  PARCIAL. Cada um entrou no mundo, mas nao se encontraram."
} elseif ($sawWatch) {
    $lines += "  NAO FUNCIONOU. O mod carregou, mas o jogo nao chegou ao mundo."
} else {
    $lines += "  NAO FUNCIONOU. O mod nem carregou (verifique o rename para winmm.dll)."
}
$lines += ""
if ($deaths -gt 0) {
    $lines += "MORTES REGISTRADAS:"
    foreach ($d in $deathsInfo) { $lines += "  $($d.when)  pid $($d.pid)  durou $($d.secs)s" }
    $lines += ""
    $lines += "  Os arquivos de cada morte estao nas pastas morte-HHMMSS."
}
$lines | Set-Content $v -Encoding UTF8

"=== FIM ===" | Add-Content $out -Encoding UTF8
