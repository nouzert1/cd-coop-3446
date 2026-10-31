# COMO INSTALAR O KIT HOST — leia isto primeiro

Você é o **ANFITRIÃO** (host) neste teste. O outro jogador é o convidado.

**Leia o arquivo inteiro antes de começar.** Há um passo que, se você errar, faz o mod
não carregar **sem dar erro nenhum** — e você vai achar que instalou certo.

---

## ⚠️ Três coisas que já custaram horas hoje

**1. O `dinput8.dll` PRECISA ser renomeado para `winmm.dll`.**

Não é preferência, é obrigatório. O jogo **importa `WINMM.dll`** e **não importa
`DINPUT8.dll`**. Com o nome original o arquivo fica lá, o jogo nunca o carrega, e **não
aparece erro nenhum** — sem painel, sem log, nada.

**2. Os dois jogadores precisam do MESMO build.**

O mod compara e recusa se forem diferentes. Este kit é o build **`D7FE9358`**.

**3. Não abra o jogo com o mod antigo instalado.**

Se houver `cdmp.asi` de antes na pasta, **apague**. Misturar restos de instalações
diferentes já causou travamento hoje.

---

## Passo a passo

### 1. Feche o jogo

O `cdmp.asi` fica travado enquanto o Crimson Desert está aberto. A cópia falha em
silêncio e deixa a pasta num estado misturado.

**Confirme que não há `CrimsonDesert.exe` no Gerenciador de Tarefas.**

### 2. Vá para a pasta do jogo

```
C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64
```

### 3. Apague o que houver do mod

Apague estes arquivos, **se existirem**:

- `cdmp.asi`
- `cdmp.ini`
- `winmm.dll`
- `cdmp.log`, `cdmp.1.log`, `cdmp.2.log` (logs antigos)

**Não apague mais nada.** O resto é do jogo.

### 4. Copie os 3 arquivos do kit

Do zip `cdmp-3460-role-swap-host.zip`:

| Arquivo no zip | → | Nome na `bin64` |
|---|---|---|
| `cdmp.asi` | → | `cdmp.asi` (igual) |
| `cdmp.ini` | → | `cdmp.ini` (igual) |
| `dinput8.dll` | → | ⚠️ **`winmm.dll`** (RENOMEAR) |

**O `LEIA-PRIMEIRO.md` e o `SHA256SUMS.txt` do zip são só documentação — não copie.**

**Não edite o `cdmp.ini`.** Ele já vem como `role=host`, com o código e o peer vazios.
Está correto assim.

### 5. Confira antes de abrir o jogo

Abra o **PowerShell** e cole:

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
foreach($f in @('cdmp.asi','winmm.dll')){
  $h = (Get-FileHash "$g\$f" -Algorithm SHA256).Hash
  Write-Output "$f : $h"
}
Select-String -Path "$g\cdmp.ini" -Pattern '^role=|^peer_steamid=|^code=' -Encoding unicode
```

**Tem que aparecer exatamente isto:**

```
cdmp.asi  : 43335AA91BA673EFE8EAA440E30535C03E302EA55467DA3F68969524A1992256
winmm.dll : 031A3E5576D91DCE1E438D36B9A3D462C7334AB4791990A8FF1E3DDC0E132DAF
role=host
peer_steamid=
code=
```

**Se algum hash não bater, o arquivo errado foi copiado. Recomece do passo 3.**

---

## 6. Abra o jogo e confirme que o mod carregou

Entre no jogo. Depois, com o jogo **aberto**, rode:

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Select-String -Path "$g\cdmp.log" -Pattern 'Crimson Desert Multiplayer|Exit watch|your code is' |
  Select-Object -First 5 | ForEach-Object { $_.Line }
```

**Você deve ver:**

```
=== Crimson Desert Multiplayer 0.2.0 (build D7FE9358, protocol 10) ===
Exit watch: TerminateProcess hooked | ExitProcess hooked | RtlExitUserProcess hooked (RaiseException not hooked: it fires as normal control flow)
Room: hosting, code XXXXXXX
```

**Se `cdmp.log` não existir**, o mod não carregou — quase sempre porque o `dinput8.dll`
ficou com o nome errado. Volte ao passo 4.

**Se aparecer um build diferente de `D7FE9358`**, você copiou um `cdmp.asi` antigo.

---

## 7. O que o painel mostra

No canto da tela aparece o painel do mod (`[F8]` alterna):

```
Crimson Desert Multiplayer 0.2.0 [F8]
Network: looking for the other player...
You: HP 1650/1650  Stamina 440/440
Room code: XXXXXXX  (tell your friend)
```

**Anote o código de 7 caracteres e mande para o convidado.** É assim que ele entra.

O código **muda a cada vez que você reinicia o jogo** — se reiniciar, mande o novo.

---

## 8. Ordem do teste

```
1. VOCÊ abre o jogo e entra no mundo
2. Anda alguns passos, depois fica 30 segundos parado
3. Lê o código e manda para o convidado
4. ESPERA ele entrar
```

**O passo 2 não é opcional.** Se o convidado entrar antes do seu mundo terminar de
carregar, a posição dele chega errada — isso já desviou uma investigação inteira hoje.

---

## 9. O que mandar de volta

**Se o jogo travar ou fechar**, capture o log **imediatamente** (antes de reabrir, senão
ele é rotacionado):

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Copy-Item "$g\cdmp.log" "$env:USERPROFILE\Desktop\cdmp-HOST-$(Get-Date -Format 'HHmm').log" -Force
Write-Host "log salvo na Area de Trabalho" -ForegroundColor Green
```

**Mande esse arquivo.** As últimas linhas antes da morte são o que importa.

**Depois**, com o jogo fechado:

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Write-Host "--- build ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'Multiplayer 0.2.0' | Select-Object -First 1 | ForEach-Object { $_.Line }
Write-Host "--- exit watch ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'Exit watch' | ForEach-Object { $_.Line }
Write-Host "--- registrou saida? ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'Exit: Terminate|Exit: ExitProcess|Exit: RtlExit' | ForEach-Object { $_.Line }
Write-Host "--- sala e conexao ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'your code is|Net: connected|peer timed out|version' | Select-Object -Last 6 | ForEach-Object { $_.Line }
Write-Host "--- ultimas 20 linhas ---" -ForegroundColor Cyan
Get-Content "$g\cdmp.log" | Select-Object -Last 20
```

**Cole a saída inteira na resposta.**

---

## Se algo der errado

**O jogo não abre / tela preta / fecha sozinho:**
Mande o log do passo 9. Não tente várias vezes seguidas — o mesmo travamento repetido não
acrescenta informação, e cada tentativa rotaciona o log e perde a evidência anterior.

**O mod não aparece no jogo:**
`cdmp.log` não existe = o `dinput8.dll` não foi renomeado para `winmm.dll`.

**Vocês não se encontram:**
Os dois precisam do build `D7FE9358`. O mod mostra na tela se forem diferentes.

---

## Por que este kit é novo

O kit anterior tinha um defeito **nosso**, não seu: o mod passou a interceptar uma função
(`RaiseException`) que o runtime do C++ usa como fluxo normal. Isso travava o jogo **antes
do menu**, nos dois PCs. Foi corrigido, e a correção tem um teste que falha se alguém
reintroduzir o erro.

**Os dois jogadores estavam com razão em reclamar.** O problema era o mod.
