# Instalação do CONVIDADO — passo a passo

Você vai entrar no mundo do anfitrião. Este arquivo tem **os comandos prontos para copiar e colar**.

> **Se você usa o DeepSeek Harness:** este guia foi escrito para você. Os comandos abaixo podem ser
> colados direto no chat, ou pedidos ao agente em linguagem natural — ele executa e te mostra a
> saída. Se preferir fazer à mão, é PowerShell comum.

**Tempo:** ~15 minutos. **Nível:** nenhum conhecimento técnico necessário.

---

## ⚠️ Leia isto primeiro — dois fatos medidos

**1. Nada neste mod deveria estragar o seu save.** Ele foi feito para **recusar** em vez de arriscar:
se a versão do jogo não for a esperada, ele desliga a leitura e não toca em nada. Mas o backup leva
1 minuto e é a diferença entre um susto e perder tudo. **Faça o backup.**

**2. O mod ainda não está funcionando por completo.** O co-op conecta de verdade — testado em
31/10/2026, com 685 pacotes trocados e 38 ms de latência — mas a **posição do convidado chega zerada**
e o boneco aparece **no céu, congelado**. Estamos consertando isso. Você é parte do teste.

---

## PARTE 1 — Antes de instalar

### 1.1 Backup do save (obrigatório)

Cole no PowerShell:

```powershell
$src = "$env:LOCALAPPDATA\Pearl Abyss\CD\save"
$dst = "$env:USERPROFILE\Desktop\CD-save-backup-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
Copy-Item $src $dst -Recurse -Force
Write-Host "Backup em: $dst" -ForegroundColor Green
```

**Se algo der errado:** apague `%LOCALAPPDATA%\Pearl Abyss\CD\save` e copie a pasta do backup de volta.

### 1.2 Conferir a versão do jogo

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
(Get-Item "$game\CrimsonDesert.exe").VersionInfo.FileVersion
```

**Tem que imprimir exatamente:**

```
1.0.0.3460
```

**Se for diferente, PARE e avise o anfitrião.** O jogo já se atualizou sozinho duas vezes durante
este projeto, e nas duas o mod parou de ler o jogo. Não tem como adivinhar que o problema é esse: o
jogo não avisa, o mod só para de funcionar.

> 💡 Para evitar surpresa: Steam → botão direito em Crimson Desert → Propriedades → **Atualizações** →
> **"Só atualizar este jogo quando eu iniciar"**.

### 1.3 Confirmar que vocês são amigos na Steam

O mod encontra o anfitrião pela **lista de amigos**. Se vocês não forem amigos, ele não acha ninguém
e nada acontece.

### 1.4 Fechar o jogo

```powershell
Get-Process CrimsonDesert -ErrorAction SilentlyContinue | Stop-Process
```

---

## PARTE 2 — Instalar

### 2.1 Onde está a pasta do jogo

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Test-Path $game
```

Tem que dar `True`. Se der `False`, o jogo está em outro lugar — descubra com:

```powershell
Get-ChildItem "C:\Program Files (x86)\Steam\steamapps\common" -Directory |
  Where-Object { $_.Name -like "*Crimson*" }
```

### 2.2 Checar o que já existe na pasta

**Antes de copiar qualquer coisa**, veja se já não há um `winmm.dll` de outro mod instalado:

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Get-ChildItem $game -Force | Where-Object { $_.Name -match 'winmm|dinput8|cdmp' } |
  Select-Object Name, Length, LastWriteTime
```

**Resultado esperado: vazio.** Se aparecer algo, **pare e avise o anfitrião** antes de continuar —
pode ser de outro mod, e sobrescrever quebra os dois.

### 2.3 Copiar os 3 arquivos

Extraia o zip em algum lugar (Área de Trabalho serve) e depois:

```powershell
$zip     = "$env:USERPROFILE\Downloads\cdmp-3460-test-kit.zip"   # ajuste se estiver noutro lugar
$extrair = "$env:USERPROFILE\Desktop\cdmp-kit"
$game    = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"

Expand-Archive $zip -DestinationPath $extrair -Force
Copy-Item "$extrair\cdmp.asi"   $game -Force
Copy-Item "$extrair\cdmp.ini"   $game -Force
Copy-Item "$extrair\dinput8.dll" $game -Force

Write-Host "Copiados 3 arquivos." -ForegroundColor Green
```

### 2.4 RENOMEAR `dinput8.dll` → `winmm.dll`

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Rename-Item "$game\dinput8.dll" "winmm.dll" -Force
Get-ChildItem $game -Force | Where-Object { $_.Name -match 'winmm|cdmp' } |
  Select-Object Name, Length
```

**Tem que mostrar exatamente 3 arquivos:** `winmm.dll`, `cdmp.asi`, `cdmp.ini`.

### 🔴 Por que esse rename é obrigatório

`dinput8.dll` é o **Ultimate ASI Loader**. Ele funciona **sequestrando uma DLL pelo nome**: o Windows
só o carrega se o jogo **importar** aquele nome. Medido no import table de `CrimsonDesert.exe`:

| Nome | O jogo importa? | Resultado |
|---|---|---|
| `WINMM.dll` | ✅ **sim** | **carrega** — é o nome certo |
| `DINPUT8.dll` | ❌ **não** | fica parado na pasta, **sem fazer nada** |

**Sintoma se você esquecer:** o jogo abre normalmente, **nenhum painel aparece**, e **não existe
`cdmp.log`** na pasta. Nenhum erro, nenhum aviso — o arquivo simplesmente nunca é lido.

> ⚠️ **Se aparecer `Ponto de entrada não encontrado: waveInStart`** ao clicar em Jogar: o arquivo está
> **corrompido** (download incompleto). O ASI Loader 9.7.4 **exporta** `waveInStart`. Confira o
> SHA256 na seção 2.6 e extraia o zip de novo — **não copie de dentro dele**.

### 2.5 Conferir o `cdmp.ini`

O `cdmp.ini` é **UTF-16**, então precisa do `-Encoding unicode`:

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Select-String -Path "$game\cdmp.ini" -Pattern '^\[|^role=|^peer_steamid=|^transport=' -Encoding unicode |
  ForEach-Object { $_.Line.Trim() }
```

**Tem que aparecer:**

```ini
[net]
transport=steam
role=guest                          ← você é o convidado
[steam]
peer_steamid=76561199441047799      ← SteamID do anfitrião, já preenchido
[coop]
enabled=1                           ← o interruptor principal
```

**[coop] enabled=1 é o mais importante.** É ele que faz o personagem do anfitrião **aparecer** no seu
mundo. Se estiver `0`, vocês conectam mas você **não vê o boneco**.

### 2.6 Verificar a integridade (10 segundos)

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Get-FileHash "$game\winmm.dll" -Algorithm SHA256 | Select-Object -ExpandProperty Hash
```

**Tem que dar:**

```
E196DAB4302D48C9597C678F14A0F23C217F02D913D74E075CC4CDE834F2E33A
```

> **Atenção:** esse é o hash do `cdmp.asi` do kit atual. Se você baixou uma versão anterior, o número
> será diferente — nesse caso use o `SHA256SUMS.txt` que veio no seu zip.

---

## PARTE 3 — Jogar

### 3.1 Esperar o anfitrião abrir primeiro

**Ele abre o jogo e carrega um save primeiro.** Espere ele avisar que está no mundo.

### 3.2 Abrir o jogo e carregar seu save

1. Abra o Crimson Desert normalmente
2. Carregue o **seu** save
3. **Espere o mundo carregar completamente** — ande alguns passos, veja o cenário aparecer
4. Espere mais 30 segundos parado

> ⚠️ **Este passo importa mais do que parece.** No teste de 31/10, a posição do convidado chegou
> zerada em **216 medições seguidas** — provavelmente porque o mundo dele ainda não tinha terminado
> de carregar. Não tenha pressa aqui.

### 3.3 Confirmar que o mod carregou — ANTES de ir ao encontro

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Select-String -Path "$game\cdmp.log" -Pattern 'Game reader|Local player|Local: pos' |
  Select-Object -Last 5 | ForEach-Object { $_.Line }
```

**Você precisa ver estas três coisas:**

```
Game reader enabled (build 1.0.0.3460 offsets)
Local player: in world
Local: pos (x, y, z) ...
```

> **Se o arquivo `cdmp.log` não existir**, o mod não carregou. Volte para a seção 2.4 — quase sempre é
> o rename que faltou.

> ⚠️ **O jogo mantém o `cdmp.log` aberto enquanto roda**, e às vezes a leitura falha com
> *"sendo usado por outro processo"*. **Não é erro do mod** — é o Windows. Espere alguns segundos e
> rode de novo, ou **feche o jogo** e leia o log depois. O log **não se perde**: ele fica no disco e
> você lê tudo quando quiser.

### 3.4 ⭐ A verificação que realmente funciona: MOVIMENTO

**Ande alguns passos** e rode de novo:

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Select-String -Path "$game\cdmp.log" -Pattern 'Local: pos' |
  Select-Object -Last 2 | ForEach-Object { $_.Line }
```

**O número tem que mudar entre as duas linhas.** Se muda quando você anda, a leitura está certa.

> **Se aparecer sempre `(0, 0, 0)` ou `Local: unavailable`, PARE e avise o anfitrião.** Este é
> exatamente o bug que estamos investigando, e saber que acontece no *seu* PC é a informação que
> falta.

### 3.5 Ir ao mesmo lugar que ele

Combine **antes** onde vocês se encontram — a primeira cidade, ou um acampamento conhecido. Vocês
precisam estar no mesmo lugar do mapa.

### 3.6 Olhar o painel

O painel fica no **canto superior esquerdo**. **`F8`** mostra ou esconde.

Você deve ver:

```
Network: connected to '<nome do anfitrião>' (XX ms)
Other player: HP xxxx/xxxx   XX m away
```

### 3.7 ⭐ A pergunta que decide o teste

> **Você VÊ o personagem dele no mundo, andando?**

**Se aparecer:** ele provavelmente estará **no céu e congelado** — é o bug conhecido da posição
zerada. **Anote e avise.** Não é culpa sua.

**Se aparecer no chão e andando:** 🎉 **é a primeira vez que isso funciona no projeto.** Avise na hora.

⚠️ **A distância no painel NÃO é a mesma coisa que ver o boneco.** Já aconteceu de a distância
funcionar e o personagem não existir na tela. São duas coisas, e as duas precisam ser sim.

---

## PARTE 4 — O que NÃO funciona (já é conhecido)

**Não reporte isto como bug novo** — já sabemos e estamos consertando:

| Coisa | O que você vai ver |
|---|---|
| **Posição do convidado** | ✅ **corrigido o crash** — agora o mod recusa em vez de derrubar o jogo |
| **Boneco no céu** | Bug aberto: a posição chega zerada |
| **Rotação do personagem remoto** | Aparece **parado de frente**, sempre |
| Ícone no minimapa | Não aparece |
| Horário do jogo sincronizado | Não sincroniza |
| Sua missão de chefe | Não avança (de propósito — o chefe não é seu) |
| Loot de chefe | Não dropa para você |
| Inimigos compartilhados | Desligados neste build (as proteções não instalaram) |
| Cavalo montado | Desligado |

### Regras de chefe

Em chefe, você **vê e machuca**, mas **o golpe final é sempre do anfitrião**. Se você matar, a missão
dele trava.

**Suas próprias missões e seu XP não são afetados** por nada disso. Você está visitando.

---

## PARTE 5 — Mensagens que você pode ver

| Mensagem | Significa | O que fazer |
|---|---|---|
| `check vs game global n/a` | **Normal.** O mod se abstém de um autocontrole quebrado | Nada |
| `Camera: camera block sentinel mismatch` | **Esperado.** É por isso que o boneco aparece de frente | Nada |
| `loading (actor parked at the origin)` | **A correção funcionando.** O mod recusou um estado inválido | Espere o mundo carregar |
| `Different mod versions` | Os `cdmp.asi` são diferentes | **Os dois precisam do MESMO zip** |
| Nenhum painel **e nenhum `cdmp.log`** | O rename da seção 2.4 faltou | Renomeie |
| `Ponto de entrada não encontrado: waveInStart` | Arquivo corrompido | Extraia o zip de novo |
| `Game reader DISABLED: unsupported game build` | A versão do jogo mudou | Avise o anfitrião |

---

## PARTE 6 — Regras durante o teste

1. **NINGUÉM salva o jogo** enquanto o outro estiver no mundo. É a forma mais provável de estragar um
   save.
2. **Não apague o `cdmp.log`.** Ele é o resultado do teste.
3. Se o anfitrião pedir, aperte **`Ctrl+F12`** junto com ele.

### Por que o `Ctrl+F12`

Ele grava uma **marca numerada** no `cdmp.log` com a hora exata. Quando vocês apertam **no mesmo
instante**, os dois logs ganham a mesma marca — e aí dá para **alinhar as duas linhas do tempo** e ver
o que cada lado fazia no instante de um problema.

Aperte junto com ele (combinem: *"agora!"*) nos momentos que importam: o boneco apareceu, sumiu,
travou, o dano não contou.

---

## PARTE 7 — Mandar o resultado

### 7.0 ⭐ O jeito mais fácil: rode o diagnóstico

Um script faz **tudo** de uma vez — confere a instalação, lê a configuração, analisa o log inteiro e
escreve um relatório pronto para mandar.

**Feche o jogo primeiro** (o mod mantém o log aberto enquanto roda):

```powershell
Get-Process CrimsonDesert -ErrorAction SilentlyContinue | Stop-Process
```

Depois:

```powershell
cd $env:USERPROFILE\Downloads
Invoke-WebRequest "https://raw.githubusercontent.com/nouzert1/cd-coop-3446/master/scripts/diagnostico-convidado.ps1" -OutFile diagnostico.ps1
powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1
```

**Ele cria um arquivo na sua Área de Trabalho:**

```
cdmp-diagnostico-2026-10-31-1730.txt
```

**Mande esse arquivo inteiro para o anfitrião.** Ele responde sozinho as perguntas abaixo — você não
precisa interpretar nada.

### 7.1 Se o jogo fechar sozinho — capture isto IMEDIATAMENTE

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Copy-Item "$game\cdmp.log" "$env:USERPROFILE\Desktop\cdmp-convidado-$(Get-Date -Format 'HHmm').log" -Force
Write-Host "Log salvo na Area de Trabalho" -ForegroundColor Green
```

Depois mande o arquivo. **A última linha antes da morte é a informação mais valiosa do teste.**

### 7.2 O resumo do teste

**Rode isto com o jogo FECHADO** (assim a leitura do log não falha):

```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Write-Host "=== VIDA DO LOG ===" -ForegroundColor Cyan
Select-String -Path "$game\cdmp.log" -Pattern 'build 1\.0|Game reader|Local player' |
  Select-Object -First 4 | ForEach-Object { $_.Line }
Write-Host "`n=== CONECTOU? ===" -ForegroundColor Cyan
Select-String -Path "$game\cdmp.log" -Pattern 'Net: connected' |
  Select-Object -Last 1 | ForEach-Object { $_.Line }
Write-Host "`n=== POSICAO (muda quando anda?) ===" -ForegroundColor Cyan
Select-String -Path "$game\cdmp.log" -Pattern 'Local: pos' |
  Select-Object -Last 3 | ForEach-Object { $_.Line }
Write-Host "`n=== BONECO ===" -ForegroundColor Cyan
Select-String -Path "$game\cdmp.log" -Pattern 'Puppet:|other player' |
  Select-Object -Last 5 | ForEach-Object { $_.Line }
```

**Mande a saída inteira disso.**

### 7.3 E responda em uma frase cada

1. Apareceu **`connected`**? Nos **dois**?
2. **Você viu o boneco do anfitrião?** No chão ou no céu?
3. A sua posição **mudou** quando você andou?
4. O jogo **fechou** em algum momento?

---

## RESUMO EM 8 LINHAS

```
1. Backup:   %LOCALAPPDATA%\Pearl Abyss\CD\save   ->  Area de Trabalho
2. Versao:   1.0.0.3460  (tem que ser exatamente)
3. Steam:    ser amigo do anfitriao
4. Fechar o jogo
5. Copiar 3 arquivos para bin64:  cdmp.asi, cdmp.ini, dinput8.dll
6. RENOMEAR dinput8.dll -> winmm.dll        <- obrigatorio
7. Nao editar o cdmp.ini (ja vem pronto, role=guest)
8. Esperar ele abrir -> abrir -> mundo carregar 100% -> mesmo lugar -> F8
```

---

## Se você usa o DeepSeek Harness

Você pode pedir tudo em linguagem natural. Exemplos que funcionam:

> *"Faz o backup do meu save do Crimson Desert"*
>
> *"Confere se a versão do meu Crimson Desert é 1.0.0.3460"*
>
> *"Instala o mod de co-op que está em `~/Downloads/cdmp-3460-test-kit.zip` na pasta do jogo, e
> renomeia o dinput8.dll para winmm.dll"*
>
> *"Lê o meu `cdmp.log` e me diz se o mod carregou, se conectou, e se a minha posição está mudando"*
>
> *"O jogo travou, salva o log na Área de Trabalho"*

**O comando mais útil durante o teste:**

> *"Lê as últimas 20 linhas do meu cdmp.log e me diz o que está acontecendo"*

O agente consegue ler o log, identificar o estado da conexão e te dizer se o problema é seu ou do
anfitrião — em vez de você ter que interpretar as linhas cruas.
