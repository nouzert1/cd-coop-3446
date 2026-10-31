# COMO INSTALAR O KIT CONVIDADO — leia isto primeiro

Você é o **CONVIDADO** (guest) neste teste. O outro jogador é o anfitrião.

**Leia o arquivo inteiro antes de começar.** Há um passo que, se você errar, faz o mod
não carregar **sem dar erro nenhum**.

---

## ⚠️ Três coisas que já custaram horas hoje

**1. O `dinput8.dll` PRECISA ser renomeado para `winmm.dll`.**

Obrigatório. O jogo **importa `WINMM.dll`** e **não importa `DINPUT8.dll`**. Com o nome
original o arquivo fica lá, o jogo nunca o carrega, e **não aparece erro nenhum**.

**2. Os dois jogadores precisam do MESMO build.**

Este kit é o build **`D7FE9358`**.

**3. Apague o mod antigo antes de copiar.**

Misturar restos de instalações diferentes já causou travamento hoje.

---

## Passo a passo

### 1. Feche o jogo

O `cdmp.asi` fica travado com o Crimson Desert aberto, e a cópia falha em silêncio.

### 2. Vá para a pasta do jogo

```
C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64
```

### 3. Apague o que houver do mod

`cdmp.asi`, `cdmp.ini`, `winmm.dll`, e os `cdmp*.log`.

### 4. Copie os 3 arquivos

| Arquivo no zip | → | Nome na `bin64` |
|---|---|---|
| `cdmp.asi` | → | `cdmp.asi` |
| `cdmp.ini` | → | `cdmp.ini` |
| `dinput8.dll` | → | ⚠️ **`winmm.dll`** (RENOMEAR) |

Não copie o `LEIA-PRIMEIRO.md` nem o `SHA256SUMS.txt`.

**Não edite o `cdmp.ini` agora.** Ele já vem com `role=guest` e o SteamID do anfitrião.
**Falta só o código da sala**, que ele vai te mandar.

### 5. Confira antes de abrir o jogo

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
foreach($f in @('cdmp.asi','winmm.dll')){
  $h = (Get-FileHash "$g\$f" -Algorithm SHA256).Hash
  Write-Output "$f : $h"
}
Select-String -Path "$g\cdmp.ini" -Pattern '^role=|^peer_steamid=|^code=' -Encoding unicode
```

**Esperado:**

```
cdmp.asi  : 43335AA91BA673EFE8EAA440E30535C03E302EA55467DA3F68969524A1992256
winmm.dll : 031A3E5576D91DCE1E438D36B9A3D462C7334AB4791990A8FF1E3DDC0E132DAF
role=guest
peer_steamid=<STEAMID-ANFITRIAO>
code=
```

---

## ⚠️ IMPORTANTE: espere o anfitrião

**Não abra o jogo ainda.**

A ordem correta é:

```
1. ELE abre o jogo e entra no mundo
2. Ele espera o mundo carregar (anda um pouco, para 30 s)
3. Ele lê o código e manda para você
4. SÓ ENTÃO você abre o seu
```

**Se você entrar antes do mundo dele carregar**, a posição dele chega como `(0,0,0)` e a
sincronização falha. É exatamente o que aconteceu nas tentativas de hoje.

---

## 6. Coloque o código da sala

Quando ele mandar o código de 7 caracteres (ex.: `1YZDAWX`):

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
$c = Read-Host "Cole o codigo de 7 caracteres"
$t = [IO.File]::ReadAllText("$g\cdmp.ini", [Text.Encoding]::Unicode)
$t = [regex]::Replace($t, '(?m)^code=.*$', "code=$c")
[IO.File]::WriteAllText("$g\cdmp.ini", $t, [Text.Encoding]::Unicode)
Write-Host "codigo definido: $c" -ForegroundColor Green
```

**Faça isso com o jogo fechado**, ou use o campo do painel dentro do jogo (os dois
funcionam).

---

## 7. Abra o jogo e confirme

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Select-String -Path "$g\cdmp.log" -Pattern 'Multiplayer 0.2.0|Exit watch|Local: pos|Net: connected' |
  Select-Object -Last 6 | ForEach-Object { $_.Line }
```

**Você deve ver:**

```
=== Crimson Desert Multiplayer 0.2.0 (build D7FE9358, protocol 10) ===
Exit watch: TerminateProcess hooked | ExitProcess hooked | ...
Local: pos (-20626.62, 621.16, -6813.44)      <- so' depois de entrar no mundo
Net: connected | ... | remote states N
```

**Se `cdmp.log` não existir** → o `dinput8.dll` não foi renomeado.

**Se o build não for `D7FE9358`** → copiou um `cdmp.asi` antigo.

---

## 8. O que mandar de volta

**Se travar ou fechar**, capture o log imediatamente:

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Copy-Item "$g\cdmp.log" "$env:USERPROFILE\Desktop\cdmp-CONVIDADO-$(Get-Date -Format 'HHmm').log" -Force
```

**Depois**, com o jogo fechado:

```powershell
$g = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64"
Write-Host "--- sua posicao (deve MUDAR quando voce anda) ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'Local: pos' | Select-Object -Last 3 | ForEach-Object { $_.Line }
Write-Host "--- viu o personagem dele? ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'other player loaded|spawn queued|spawn refused' | Select-Object -Last 4 | ForEach-Object { $_.Line }
Write-Host "--- conexao ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'Net: connected|peer timed out|version' | Select-Object -Last 4 | ForEach-Object { $_.Line }
Write-Host "--- registrou saida? ---" -ForegroundColor Cyan
Select-String -Path "$g\cdmp.log" -Pattern 'Exit: Terminate|Exit: ExitProcess|Exit: RtlExit' | ForEach-Object { $_.Line }
```

**Responda também, em uma linha cada:**

1. Você viu o personagem dele? Andando ou parado?
2. Seu jogo sobreviveu o teste inteiro?
3. O jogo dele fechou em algum momento?

---

## Por que este kit é novo

O kit anterior tinha um defeito **nosso**: o mod passou a interceptar uma função
(`RaiseException`) que o runtime do C++ usa como fluxo normal. Isso travava o jogo **antes
do menu**, nos dois PCs. Foi corrigido.

**Você estava certo em reclamar.** O problema era o mod.
