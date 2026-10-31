# Co-op no Crimson Desert — guia do jogador

Este guia é para quem quer **jogar**, não programar. Se você quer mexer no código, leia o
[README.md](../README.md) e o [PORTING.md](PORTING.md).

---

## O que este mod faz

Duas pessoas, cada uma no seu PC, no mesmo mundo. Um é o **anfitrião** (dono da partida), o outro é o
**convidado** (quem visita).

- Vocês se veem e andam juntos pelo mundo.
- Os inimigos do anfitrião aparecem para o convidado, e o convidado pode ajudar a matá-los.
- **Cada um pega o seu loot** — o item é compartilhado, os dois recebem.
- **As missões do convidado não são afetadas.** Ele ajuda, mas o progresso é do anfitrião.
- Em chefe: o convidado vê e machuca, mas **o golpe final é sempre do anfitrião** — se o convidado
  matar, a missão do anfitrião trava.

---

## O que NÃO funciona ainda — leia antes de testar

Ser honesto aqui economiza o seu tempo.

| Coisa | Estado |
|---|---|
| **Ver o personagem do outro no mundo** | **NUNCA foi confirmado.** É o que vocês vão testar |
| Ícone do amigo no minimapa | Não aparece |
| Rotação do personagem remoto | Aparece **parado de frente**, sempre |
| Sincronia de horário do jogo | Não funciona |
| Missão do convidado em chefe | Não avança (é de propósito) |
| Loot de chefe para o convidado | Não dropa |
| Cavalo montado em co-op | Desligado |

**Conectar NÃO é o mesmo que funcionar.** O painel mostrar `connected` e uma distância não prova que
o boneco aparece. Já aconteceu de a distância funcionar e o personagem não existir na tela.

---

## Antes de começar

### 1. Backup do save — faça isto

1. Aperte `Win+R`, cole `%LOCALAPPDATA%\Pearl Abyss\CD` e aperte Enter.
2. Copie a pasta `save` para a Área de Trabalho.

Se algo der errado, você restaura essa pasta e volta ao normal.

### 2. Confira a versão do jogo — os dois

O mod só funciona na versão **exata**. Clique com o botão direito em `CrimsonDesert.exe` →
Propriedades → Detalhes → **Versão do arquivo**. Tem que ser:

```
1.0.0.3460
```

Se estiver diferente, **pare** e avise. O jogo já se atualizou sozinho duas vezes durante este
projeto (3424 → 3446 → 3460), e nas duas o mod parou de ler o jogo sem travar e sem estragar o save.

> No Steam, coloque em: botão direito em Crimson Desert → Propriedades → Atualizações →
> **"Só atualizar quando eu iniciar o jogo"**. Assim você vê antes de quebrar.

### 3. O MESMO arquivo nos dois computadores

Use o **mesmo ZIP** nos dois PCs. Se um usar um arquivo e o outro usar outro, o painel mostra
`Different mod versions`.

### 4. Sejam amigos na Steam

O mod procura o anfitrião pela lista de amigos. **Se vocês não forem amigos, ele não acha ninguém.**

---

## Instalar

1. No Steam: botão direito em Crimson Desert → Gerenciar → **Procurar arquivos locais**. Abra a pasta
   `bin64`.
2. Copie **3 arquivos** para dentro de `bin64`:
   - `cdmp.asi`
   - `cdmp.ini`
   - `dinput8.dll` → **RENOMEIE para `winmm.dll`**
3. O terceiro **precisa** ser renomeado. Se ficar `dinput8.dll`, ele não carrega e nada funciona.
4. Se a pasta `bin64` **já tiver** um `winmm.dll`, pare e avise.

Não precisa editar nada. O `cdmp.ini` já vem pronto.

---

## Jogar

1. **O anfitrião abre primeiro** e carrega um save. Espere 30 segundos parado.
2. **O convidado abre** e carrega o save dele.
3. **Fiquem no mesmo lugar do mapa.** Combinem antes — um ponto conhecido, tipo a primeira cidade.
4. **Cheguem perto um do outro** (menos de 50 m).
5. Olhem em volta. **Vocês se veem?**

O painel fica no canto superior esquerdo, e **F8** mostra ou esconde.

---

## O que aparece no painel

```
Network: connected to '<nome>' (XX ms)      ← conectou
Other player: HP xxxx/xxxx   XX m away      ← a distância
```

**As duas linhas precisam aparecer E vocês precisam se ver andando no mundo.** As duas coisas.

---

## Se der errado

### Não aparece painel nenhum

O mod não carregou. Confira:
- Você renomeou o `dinput8.dll` para `winmm.dll`?
- Os 3 arquivos estão em `bin64`?

### Aparece `Different mod versions`

Os dois arquivos `cdmp.asi` são diferentes. **Os dois precisam usar o mesmo ZIP.**

### Aparece `check vs game global n/a`

**Normal e esperado.** É o mod se abstendo de um autocontrole que não funciona neste build. O que
seria errado é aparecer um número tipo `21849.89 m`.

### Aparece `Camera: camera block sentinel mismatch`

**Esperado neste build.** Significa que a câmera do convidado não foi recuperada depois da
atualização. É por isso que o personagem aparece parado de frente. Não tente consertar.

### Conectou mas não vejo o personagem

É o resultado do teste anterior, e é **uma resposta útil** — não é fracasso de vocês. Anotem e
avisem. É exatamente isto que estamos tentando descobrir.

### O jogo travou ou fechou sozinho

É um problema conhecido. Anote **o que estava acontecendo no momento**: quem fez o quê, se tinha
inimigo por perto, se era chefe. Feche, anote e mande.

---

## Regras durante o teste

1. **Ninguém salva o jogo** enquanto o outro estiver no mundo. É a forma mais provável de estragar um
   save.
2. **Não apague o `cdmp.log`** — ele é o resultado do teste.
3. Se o anfitrião pedir, aperte **Ctrl+F12** junto com ele.

---

## Onde ficam as coisas

| O quê | Onde |
|---|---|
| Log do mod | `<jogo>\bin64\cdmp.log` |
| Config | `<jogo>\bin64\cdmp.ini` |
| Saves | `%LOCALAPPDATA%\Pearl Abyss\CD\save` |

---

## Como mandar o resultado

Do **convidado**:
- o `cdmp.log`
- **uma foto do painel**, com a linha `Other player:` visível

Do **anfitrião**:
- o `cdmp.log`

E respondendo em uma frase cada:

1. Apareceu `connected`? **Nos dois?**
2. Alguém viu o boneco do outro? **Quem viu o quê?**
3. Os inimigos do anfitrião apareceram no mundo do convidado?
4. O convidado conseguiu pegar loot?

---

## Privacidade

- O mod só fala com o outro jogador, pelo Steam, e só aceita amigos. Não tem telemetria nem servidor
  próprio.
- A gravação de pacotes vem **desligada**. Se ligar, os arquivos contêm dados do jogo (posições,
  ids) — confira antes de compartilhar.
