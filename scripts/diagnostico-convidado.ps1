<#
.SYNOPSIS
  Coleta o estado do mod de co-op do Crimson Desert no PC do CONVIDADO.

.DESCRIPTION
  Gera um unico arquivo de texto com tudo o que o anfitriao precisa para entender o que
  aconteceu do lado do convidado -- instalacao, versao do jogo, se o mod carregou, se
  conectou, e principalmente se a POSICAO do convidado esta sendo lida.

  Rode com o jogo FECHADO. O mod mantem o cdmp.log aberto enquanto roda, e a leitura
  falha com "sendo usado por outro processo" -- isso e' o Windows, nao um defeito.

  O arquivo gerado sai na Area de Trabalho com o nome
  cdmp-diagnostico-<data>-<hora>.txt

.EXAMPLE
  .\diagnostico-convidado.ps1
#>

[CmdletBinding()]
param(
    # Onde esta' o bin64 do jogo. O padrao e' o caminho normal do Steam.
    [string] $GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64',
    # Onde gravar o relatorio. Por padrao, a Area de Trabalho.
    [string] $OutDir  = [Environment]::GetFolderPath('Desktop')
)

$ErrorActionPreference = 'Continue'

# Sem isto o Set-Content no fim falha em silencio e o convidado fica sem arquivo para
# mandar, sem entender por que.
if (-not (Test-Path $OutDir)) {
    try { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    catch { $OutDir = $env:TEMP }
}

$stamp = Get-Date -Format 'yyyy-MM-dd-HHmm'
$out   = Join-Path $OutDir "cdmp-diagnostico-$stamp.txt"
$lines = [System.Collections.Generic.List[string]]::new()

function Add-Line([string] $s = '') { $lines.Add($s) }
function Add-Head([string] $s) {
    Add-Line
    Add-Line ('=' * 70)
    Add-Line $s
    Add-Line ('=' * 70)
}

Add-Line "cdmp -- diagnostico do CONVIDADO"
Add-Line "gerado em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ---------------------------------------------------------------- por que falhou
# Uma leitura do log pode falhar por tres motivos muito diferentes, e confundi-los custa
# uma rodada inteira de teste. Cada um ganha um texto proprio.
function Read-LogShared([string] $path) {
    if (-not (Test-Path $path)) { return @{ ok = $false; why = 'nao existe' } }
    try {
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $sr = New-Object IO.StreamReader($fs)
        $txt = $sr.ReadToEnd()
        $sr.Close(); $fs.Close()
        return @{ ok = $true; text = $txt }
    } catch {
        return @{ ok = $false; why = 'esta em uso pelo jogo (feche o jogo e rode de novo)' }
    }
}

# ------------------------------------------------------------------- 1. o jogo
Add-Head '1. O JOGO'

$exe = Join-Path $GameDir 'CrimsonDesert.exe'
if (Test-Path $exe) {
    $vi = (Get-Item $exe).VersionInfo
    Add-Line "  pasta        : $GameDir"
    Add-Line "  versao       : $($vi.FileVersion)"
    # O carimbo PE e' o que o mod compara para decidir se le' o jogo. Leio direto do
    # cabecalho em vez de converter a data do arquivo: a conversao erra e ainda por cima
    # depende do fuso, entao daria um numero plausivel e errado.
    try {
        $fs = [IO.File]::OpenRead($exe)
        $br = New-Object IO.BinaryReader($fs)
        $fs.Position = 0x3C
        $peOff = $br.ReadInt32()
        $fs.Position = $peOff + 8
        $ts = $br.ReadUInt32()
        $br.Close(); $fs.Close()
        Add-Line "  PE timestamp : 0x$($ts.ToString('X8'))"
        if ($ts -eq 0x6AE58024) {
            Add-Line "  -> bate com o que o mod espera (0x6AE58024)"
        } else {
            Add-Line "  -> NAO bate: o mod espera 0x6AE58024"
            Add-Line "     Mesmo com a versao certa no nome, o mod recusaria ler o jogo."
        }
    } catch {
        Add-Line "  PE timestamp : (nao consegui ler o cabecalho: $($_.Exception.Message))"
    }
    if ($vi.FileVersion -eq '1.0.0.3460') {
        Add-Line "  -> OK: e' a versao que o mod espera"
    } else {
        Add-Line "  -> ATENCAO: o mod so' funciona na 1.0.0.3460. Esta e' outra."
        Add-Line "     O sintoma e' 'Game reader DISABLED' no log, sem crash e sem aviso do jogo."
    }
} else {
    Add-Line "  NAO ENCONTREI CrimsonDesert.exe em $GameDir"
    Add-Line "  Passe o caminho certo:  .\diagnostico-convidado.ps1 -GameDir '<pasta bin64>'"
}

# ----------------------------------------------------- 2. o que esta' instalado
Add-Head '2. ARQUIVOS DO MOD NA PASTA DO JOGO'

$expected = @{
    'cdmp.asi'   = 'o mod'
    'cdmp.ini'   = 'a configuracao'
    'winmm.dll'  = 'o carregador (renomeado de dinput8.dll)'
}
foreach ($name in 'cdmp.asi', 'cdmp.ini', 'winmm.dll', 'dinput8.dll') {
    $p = Join-Path $GameDir $name
    if (Test-Path $p) {
        $f = Get-Item $p
        $note = if ($expected.ContainsKey($name)) { $expected[$name] } else { 'NAO DEVERIA ESTAR AQUI' }
        Add-Line ("  OK      {0,-14} {1,10:N0} bytes   {2}" -f $name, $f.Length, $note)
        if ($name -in 'cdmp.asi', 'winmm.dll') {
            Add-Line ("          sha256 {0}" -f (Get-FileHash $p -Algorithm SHA256).Hash)
        }
    } else {
        Add-Line ("  FALTA   {0,-14} {1}" -f $name, $expected[$name])
    }
}

Add-Line
Add-Line "  DIAGNOSTICO DE INSTALACAO:"
$have = @('cdmp.asi', 'cdmp.ini', 'winmm.dll') | Where-Object { Test-Path (Join-Path $GameDir $_) }
if ($have.Count -eq 3) {
    Add-Line "    os 3 arquivos estao no lugar"
} else {
    Add-Line "    FALTAM: $((@('cdmp.asi','cdmp.ini','winmm.dll') | Where-Object { -not (Test-Path (Join-Path $GameDir $_)) }) -join ', ')"
    Add-Line "    -> o mod nao vai carregar sem eles."
}
$stillDinput = Test-Path (Join-Path $GameDir 'dinput8.dll')
$hasWinmm    = Test-Path (Join-Path $GameDir 'winmm.dll')
if ($stillDinput -and -not $hasWinmm) {
    Add-Line "    O dinput8.dll ainda esta' com o nome original."
    Add-Line "    -> O jogo NAO importa DINPUT8.dll, entao ele nunca e' carregado."
    Add-Line "    -> Renomeie para winmm.dll (o jogo importa WINMM.dll)."
}

# outros arquivos que possam competir
Add-Line
Add-Line "  outros arquivos que poderiam competir (esperado: nenhum):"
$extra = Get-ChildItem $GameDir -Force -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -match '^(winmm|dinput8|version|dsound|d3d9)\.dll$' -and $_.Name -ne 'winmm.dll' }
if ($extra) {
    $extra | ForEach-Object { Add-Line ("    {0}  {1:N0} bytes  {2}" -f $_.Name, $_.Length, $_.LastWriteTime) }
} else {
    Add-Line "    nenhum"
}

# ------------------------------------------------------------ 3. a configuracao
Add-Head '3. CONFIGURACAO (cdmp.ini)'

$ini = Join-Path $GameDir 'cdmp.ini'
if (Test-Path $ini) {
    $want = @('role', 'transport', 'peer_steamid', 'code', 'delay_ms',
              'enemy_auto', 'guest_hits', 'boss_safe', 'guest_loot', 'overlay')
    $section = ''
    foreach ($r in (Select-String -Path $ini -Pattern '^\[.+\]|^\s*[a-zA-Z_]+\s*=' -Encoding unicode)) {
        $t = $r.Line.Trim()
        if ($t -match '^\[(.+)\]') { $section = $matches[1]; continue }
        if ($t -match '^([a-zA-Z_]+)\s*=\s*(.*)$') {
            $k = $matches[1]; $v = $matches[2].Trim()
            # 'enabled' aparece em varias secoes, entao o rotulo precisa da secao junto.
            if ($want -contains $k -or $k -eq 'enabled') {
                Add-Line ("  [{0}] {1,-16} = {2}" -f $section, $k, $v)
            }
            if ($section -eq 'net' -and $k -eq 'role' -and $v -ne 'guest') {
                Add-Line "        -> ATENCAO: role deveria ser 'guest' neste PC. Esta' '$v'."
                Add-Line "           Com 'host' ele tentaria hospedar em vez de entrar no mundo do amigo."
            }
            if ($section -eq 'coop' -and $k -eq 'enabled' -and $v -eq '0') {
                Add-Line "        -> CRITICO: [coop] enabled=0."
                Add-Line "           Voces conectam, aparecem as vidas, mas NENHUM boneco aparece."
            }
            if ($section -eq 'net' -and $k -eq 'enabled' -and $v -eq '0') {
                Add-Line "        -> CRITICO: [net] enabled=0. O mod nao tenta conectar."
            }
        }
    }
    Add-Line
    Add-Line "  trecho bruto de [net] e [coop]:"
    Select-String -Path $ini -Pattern '^\[net\]' -Context 0,12 -Encoding unicode |
        ForEach-Object { $_.Line; $_.Context.PostContext } | ForEach-Object { Add-Line "    $($_.Trim())" }
} else {
    Add-Line "  cdmp.ini NAO EXISTE."
    Add-Line "  -> O mod usa os padroes, e o padrao de [coop] enabled e' 0: o co-op nao liga."
}

# ------------------------------------------------------------------- 4. o log
Add-Head '4. O LOG DO MOD (cdmp.log)'

$log = Join-Path $GameDir 'cdmp.log'
$read = Read-LogShared $log

if (-not $read.ok) {
    Add-Line "  nao consegui ler: $($read.why)"
    Add-Line
    Add-Line "  ISTO E' UM RESULTADO, NAO UM ERRO:"
    if ($read.why -eq 'nao existe') {
        Add-Line "    O cdmp.log nao existe -> o mod NUNCA CARREGOU."
        Add-Line "    Causa quase certa: o rename do dinput8.dll para winmm.dll nao foi feito"
        Add-Line "    na secao 2. Confira a lista de arquivos no item 2 acima."
    } else {
        Add-Line "    O log existe e o jogo esta' com ele aberto (normal)."
        Add-Line "    Feche o jogo e rode este script de novo para ler o conteudo."
        Add-Line "    O log NAO se perde: fica no disco."
    }
} else {
    $logLines = $read.text -split "`r?`n" | Where-Object { $_ -ne '' }
    Add-Line "  $($logLines.Count) linhas, ultima escrita $((Get-Item $log).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Add-Line

    $grab = {
        param($pattern, $label, $count)
        $m = $logLines | Select-String $pattern | Select-Object -Last $count
        if ($m) {
            Add-Line "  --- $label"
            $m | ForEach-Object { Add-Line "      $($_.Line)" }
        } else {
            Add-Line "  --- $label : (nada no log)"
        }
    }

    & $grab 'Crimson Desert Multiplayer|Host version|Host process' 'APRESENTACAO / VERSAO' 3
    & $grab 'Game reader|unsupported game build'                  'O LEITOR DE MEMORIA'   3
    & $grab 'Steam:|Room:|Network:'                               'STEAM E A SALA'        6
    & $grab 'Net: connected'                                      'CONECTOU'              2
    & $grab 'Net: connecting'                                     'AINDA CONECTANDO'      2

    Add-Line
    Add-Line "  --- POSICAO LOCAL (a pergunta principal)"
    # Esta e' a medicao que decide tudo. Um leitor que funciona devolve numeros que MUDAM
    # quando o jogador anda. (0,0,0) significa mundo ainda carregando, ou leitor quebrado.
    $poss = $logLines | Select-String 'Local: pos \(' | Select-Object -Last 8
    if ($poss) {
        $vals = @()
        foreach ($p in $poss) {
            if ($p.Line -match '\[(\d+:\d+:\d+)\].*pos \(([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)') {
                $vals += "$($matches[1])  ($($matches[2]), $($matches[3]), $($matches[4]))"
            }
        }
        $vals | ForEach-Object { Add-Line "      $_" }
        $uniq = $poss | ForEach-Object { if ($_.Line -match 'pos \(([^)]+)\)') { $matches[1] } } | Select-Object -Unique
        Add-Line
        Add-Line "      posicoes DISTINTAS entre essas: $($uniq.Count)"
        if ($uniq.Count -le 1) {
            Add-Line "      -> A POSICAO NAO MUDOU. Se voce nao estava parado, o leitor nao funciona."
        } else {
            Add-Line "      -> a posicao MUDA. O leitor esta' lendo de verdade."
        }
        if ($uniq -contains '0.00, 0.00, 0.00') {
            Add-Line "      -> apareceu (0.00, 0.00, 0.00): era o mundo carregando."
        }
    } else {
        $unav = $logLines | Select-String 'Local: unavailable|Local player:' | Select-Object -Last 3
        if ($unav) {
            $unav | ForEach-Object { Add-Line "      $($_.Line)" }
            Add-Line "      -> nao ha posicao: o personagem nao chegou a entrar no mundo."
        } else {
            Add-Line "      (nada)"
        }
    }

    Add-Line
    Add-Line "  --- O BONECO DO ANFRITRIAO NO SEU MUNDO"
    & $grab 'Puppet:|other player|received the other|spawn' 'PUPPET' 8

    Add-Line
    Add-Line "  --- AVISOS E ERROS"
    $w = $logLines | Select-String 'WRN|ERR' | Select-Object -Last 15
    if ($w) { $w | ForEach-Object { Add-Line "      $($_.Line)" } } else { Add-Line "      nenhum" }

    Add-Line
    Add-Line "  --- ULTIMAS 25 LINHAS (o fim e' onde o problema aparece)"
    $logLines | Select-Object -Last 25 | ForEach-Object { Add-Line "      $_" }
}

# ------------------------------------------------------- 5. o crash do Windows
Add-Head '5. CRASH REGISTRADO PELO WINDOWS'

$found = $false
foreach ($wer in @("$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive",
                   "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportQueue",
                   "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive",
                   "$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue")) {
    if (-not (Test-Path $wer)) { continue }
    $reps = Get-ChildItem $wer -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*CrimsonDesert*' } | Sort-Object LastWriteTime -Descending | Select-Object -First 3
    foreach ($r in $reps) {
        $found = $true
        Add-Line "  $($r.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))  $($r.Name)"
        $rep = Join-Path $r.FullName 'Report.wer'
        if (Test-Path $rep) {
            foreach ($key in 'Sig\[3\]', 'Sig\[4\]', 'Sig\[6\]', 'Sig\[7\]') {
                $l = Select-String -Path $rep -Pattern "^$key" -Encoding unicode | Select-Object -First 1
                if ($l) { Add-Line "      $($l.Line.Trim())" }
            }
        }
    }
}
if (-not $found) {
    Add-Line "  nenhum. Se o jogo fechou sozinho sem aparecer aqui, o processo morreu de um jeito"
    Add-Line "  que o Windows nao registrou -- o que costuma apontar para o mod, nao para o jogo."
}

# ------------------------------------------------------------- 6. o veredito
Add-Head '6. VEREDITO'

if (-not (Test-Path $log)) {
    Add-Line "  O MOD NAO CARREGOU. Nada mais importa ate' isso ser resolvido."
    Add-Line "  1) o dinput8.dll foi renomeado para winmm.dll?"
    Add-Line "  2) os 3 arquivos (cdmp.asi, cdmp.ini, winmm.dll) estao na pasta bin64?"
} elseif (-not $read.ok) {
    Add-Line "  Provavelmente carregou (o cdmp.log existe), mas nao pude ler com o jogo aberto."
    Add-Line "  Feche o jogo e rode de novo para o veredito completo."
} else {
    $t = $read.text
    $carregou = $t -match 'Game reader enabled'
    $conectou = $t -match 'Net: connected'
    $boneco   = $t -match 'other player loaded|received the other player'
    $zerada   = $t -match 'position is the world origin|parked at the origin'
    $trava    = $found          # veio da secao 5
    $nao_leu  = $t -match 'unsupported game build'

    Add-Line "  mod carregou         : $(if($carregou){'SIM'}else{'NAO'})"
    Add-Line "  leu o jogo           : $(if($nao_leu){'NAO (build nao reconhecido)'}elseif($carregou){'SIM'}else{'?'})"
    Add-Line "  conectou ao anfitriao: $(if($conectou){'SIM'}else{'NAO'})"
    Add-Line "  boneco do amigo      : $(if($boneco){'SIM'}else{'NAO'})"
    Add-Line "  posicao invalida     : $(if($zerada){'SIM (mundo carregando, ou leitor quebrado)'}else{'nao'})"
    Add-Line "  travamento registrado: $(if($trava){'SIM (ver secao 5)'}else{'nao'})"
    Add-Line

    if (-not $carregou) {
        Add-Line "  O MOD NAO CARREGOU. Nada mais importa ate' isso ser resolvido."
        Add-Line "  1) o dinput8.dll foi renomeado para winmm.dll?"
        Add-Line "  2) os 3 arquivos estao na pasta bin64?"
    } elseif ($trava) {
        Add-Line "  O JOGO TRAVOU. A secao 5 diz qual modulo falhou."
        Add-Line "  Mande este arquivo: o fim do log (secao 4) mostra onde parou."
    } elseif ($zerada -and $boneco) {
        Add-Line "  CONECTOU E O BONECO FOI CRIADO, mas a posicao veio zerada."
        Add-Line "  Este e' o bug aberto: o personagem aparece no ceu, congelado."
        Add-Line "  O que importa agora e' a secao 4: se 'Local: pos' mostrou numeros que MUDAM"
        Add-Line "  quando voce andou, entao o leitor funciona e o defeito esta' no outro lado."
    } elseif ($conectou -and -not $boneco) {
        Add-Line "  Conectou mas o boneco nao apareceu."
        Add-Line "  Verifique se o mundo tinha terminado de carregar antes do encontro."
    } elseif ($boneco) {
        Add-Line "  TUDO FUNCIONOU. Mande este arquivo -- e' a primeira vez que chegamos aqui."
    } else {
        Add-Line "  Carregou mas nao conectou. Confira em ordem:"
        Add-Line "    - voces sao amigos na Steam?"
        Add-Line "    - o anfitriao estava com o jogo aberto e no mundo ANTES de voce?"
        Add-Line "    - os dois estao usando o MESMO cdmp.asi (mesmo sha256)?"
    }
}

Add-Line
Add-Line ('-' * 70)
Add-Line "Mande ESTE ARQUIVO INTEIRO para o anfitriao:"
Add-Line "  $out"

$lines | Set-Content -Path $out -Encoding UTF8

Write-Host ''
Write-Host 'Relatorio gerado:' -ForegroundColor Green
Write-Host "  $out" -ForegroundColor Green
Write-Host ''
Write-Host 'Mande esse arquivo para o anfitriao.' -ForegroundColor Cyan
Write-Host ''
