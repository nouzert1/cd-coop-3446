<#
  Watches for the game's death and preserves everything the moment it happens.

  The crashes on 31 Oct 2026 were losing their evidence: the log was rotated by the next
  launch, and the Windows dump (which does exist -- CrashDumps had one from 17:34) was not
  being collected. This copies both the instant the process disappears, before a relaunch
  can overwrite anything.

  Read-only with respect to the game. It never touches the running process.
#>

$g   = 'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64'
$out = Join-Path $env:TEMP 'cdmp_vigia.log'
$dst = 'C:\Users\ACER\Desktop\CD-evidencias'

New-Item -ItemType Directory $dst -Force | Out-Null
"=== vigia comecou $(Get-Date -Format 'HH:mm:ss') ===" | Set-Content $out -Encoding UTF8

$wasAlive = $false
$lastPid  = 0
$started  = $null
$captured = 0

for ($i = 0; $i -lt 1500; $i++) {
    $p = Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue
    $t = (Get-Date).ToString('HH:mm:ss')

    if ($p) {
        if (-not $wasAlive) {
            $lastPid = $p.Id
            $started = Get-Date
            "  $t  ABRIU pid=$lastPid" | Add-Content $out -Encoding UTF8
        }
        $wasAlive = $true
    } else {
        if ($wasAlive) {
            $dur = [int]((Get-Date) - $started).TotalSeconds
            "  $t  *** FECHOU *** pid=$lastPid durou ${dur}s" | Add-Content $out -Encoding UTF8

            # Capture immediately: a relaunch rotates cdmp.log into cdmp.1.log and the
            # session that matters becomes one file older.
            Start-Sleep -Seconds 2
            $stamp = Get-Date -Format 'HHmmss'
            $cap = Join-Path $dst "morte-$stamp"
            New-Item -ItemType Directory $cap -Force | Out-Null

            foreach ($f in (Get-ChildItem $g -Filter 'cdmp*.log' -ErrorAction SilentlyContinue)) {
                Copy-Item $f.FullName (Join-Path $cap $f.Name) -Force -ErrorAction SilentlyContinue
            }
            # The Windows dump, if one was written for this pid.
            foreach ($d in (Get-ChildItem "$env:LOCALAPPDATA\CrashDumps" -Filter "CrimsonDesert*" -ErrorAction SilentlyContinue)) {
                Copy-Item $d.FullName (Join-Path $cap $d.Name) -Force -ErrorAction SilentlyContinue
            }
            # The WER report, which names the faulting module and the exception code.
            foreach ($w in @("$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
                             "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive")) {
                if (-not (Test-Path $w)) { continue }
                Get-ChildItem $w -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $started -and $_.Name -like '*CrimsonDesert*' } |
                    ForEach-Object {
                        Copy-Item $_.FullName (Join-Path $cap $_.Name) -Recurse -Force -ErrorAction SilentlyContinue
                    }
            }

            $n = (Get-ChildItem $cap -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
            "       -> $n arquivos guardados em $cap" | Add-Content $out -Encoding UTF8
            $captured++
            $wasAlive = $false
        }
    }

    # Also snapshot the tail of the live log every 30 s, so an AppHang that never exits
    # still leaves a record of what it was doing.
    if ($p -and ($i % 15 -eq 0)) {
        if (Test-Path "$g\cdmp.log") {
            try {
                $fs = New-Object IO.FileStream("$g\cdmp.log", [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
                $ls = $txt -split "`r?`n" | Where-Object { $_ }
                $tail = $ls | Select-Object -Last 4
                $tail | ForEach-Object { "  $t  | $_" | Add-Content $out -Encoding UTF8 }
                foreach ($l in $tail) {
                    if ($l -match 'Exit watch:') { "  $t  [EXIT WATCH OK]" | Add-Content $out -Encoding UTF8 }
                    if ($l -match 'Exit: Terminate|Exit: ExitProcess|Exit: RtlExit') {
                        "  $t  >>> MORTE REGISTRADA: $l" | Add-Content $out -Encoding UTF8
                    }
                }
            } catch {}
        }
    }

    Start-Sleep -Seconds 2
}

"" | Add-Content $out -Encoding UTF8
"=== fim: $captured mortes capturadas ===" | Add-Content $out -Encoding UTF8
