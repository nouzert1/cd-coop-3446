# Monitor for the role-swap test: you are the GUEST this time.
#
# Watches the two things that decide the test:
#   1. that Exit watch installed   (without it the experiment is worthless)
#   2. whether an "Exit:" line ever appears (that is the answer we are after)
# and reports the connection and the spawn as they happen.
#
# Read-only. Never touches the game.

$g   = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
$log = Join-Path $g 'cdmp.log'
$out = Join-Path $env:TEMP 'cdmp_monitor_roleswap.log'

$seen = @{}
$prevPid = $null
$sawExitWatch = $false
$sawExit = $false
$alive = $false

"=== monitor do teste de papeis trocados, comecou $(Get-Date -Format 'HH:mm:ss') ===" |
    Set-Content $out -Encoding UTF8

for($i = 0; $i -lt 900; $i++){
    $t = (Get-Date).ToString('HH:mm:ss')
    $p = Get-Process -Name CrimsonDesert -ErrorAction SilentlyContinue
    $nowAlive = [bool]$p

    if($nowAlive -and -not $alive){
        "  $t  JOGO ABRIU (pid $($p.Id))" | Add-Content $out -Encoding UTF8
        $prevPid = $p.Id
    }
    if(-not $nowAlive -and $alive){
        "  $t  *** JOGO FECHOU ***" | Add-Content $out -Encoding UTF8
    }
    $alive = $nowAlive

    if(Test-Path $log){
        try {
            $fs = New-Object IO.FileStream($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $sr = New-Object IO.StreamReader($fs)
            $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()

            foreach($l in ($txt -split "`r?`n")){
                if(-not $l -or $seen.ContainsKey($l)){ continue }
                $seen[$l] = 1

                # the line that makes the whole experiment valid
                if($l -match 'Exit watch:'){
                    $sawExitWatch = $true
                    "  $t  [EXIT WATCH] $l" | Add-Content $out -Encoding UTF8
                }
                # THE ANSWER
                if($l -match 'Exit: '){
                    $sawExit = $true
                    "  $t  >>> $l" | Add-Content $out -Encoding UTF8
                }
                # role and room
                if($l -match 'your code is|Room: |will fall back to|no friends are playing'){
                    "  $t  [SALA] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                }
                if($l -match 'Steam: session with'){
                    "  $t  [SESSAO] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                }
                if($l -match 'Net: connected'){
                    if($l -match 'remote states (\d+).*last remote ([^|]+)'){
                        "  $t  [NET] states=$($matches[1]) remote=$($matches[2].Trim())" | Add-Content $out -Encoding UTF8
                    }
                }
                if($l -match 'Puppet: spawn|spawn refused|other player loaded|received the other'){
                    "  $t  [PUPPET] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                }
                if($l -match 'Local: pos'){
                    if($l -match 'pos \(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)'){
                        "  $t  [LOCAL] $($matches[1]), $($matches[2]), $($matches[3])" | Add-Content $out -Encoding UTF8
                    }
                }
                if($l -match 'loading|Loading'){
                    "  $t  [LOADING] $($l -replace '^.*?\] ','')" | Add-Content $out -Encoding UTF8
                }
            }
            if($seen.Count -gt 6000){ $seen = @{} }
        } catch {}
    }

    if(-not $sawExitWatch -and $alive -and $i -gt 15){
        # the game has been up a while and the line never came: say so once
        if(-not $seen.ContainsKey('__warned')){
            $seen['__warned'] = 1
            "  $t  !! EXIT WATCH NAO APARECEU -- o experimento nao vale sem essa linha" | Add-Content $out -Encoding UTF8
        }
    }
    Start-Sleep -Seconds 2
}

"" | Add-Content $out -Encoding UTF8
"=== fim: exit watch $sawExitWatch | Exit: $sawExit ===" | Add-Content $out -Encoding UTF8
