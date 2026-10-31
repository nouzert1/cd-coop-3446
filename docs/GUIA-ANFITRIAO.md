# Guia do ANFITRIÃO — quem recebe o amigo no seu mundo

**O anfitrião é o dono da partida.** O mundo é seu, os inimigos são seus, as missões são suas. O
convidado visita. Isso significa que **o risco fica do seu lado** — e é por isso que este guia é mais
longo que o do convidado.

Siga na ordem. Leva uns 25 minutos.

---

## Parte 1 — Entenda o risco antes de começar

### 1.1 O mod escreve no seu jogo

O convidado só recebe dados. **Você**, como anfitrião, tem um mod que **injeta mensagens** no
client/servidor interno do jogo para criar o personagem do amigo. Isso é diferente de ler.

**Antes de cada sessão:**

1. Aperte `Win+R`
2. Cole e aperte Enter:
   ```
   %LOCALAPPDATA%\Pearl Abyss\CD
   ```
3. Copie a pasta **`save`** para outro lugar, com a data no nome:
   ```
   CD-save-backup-2026-10-31-noite
   ```

**Uma regra que não se quebra:**

> 🚫 **Ninguém salva o jogo enquanto o outro estiver no seu mundo.** Nem você, nem ele.
> Esta é a forma mais provável de estragar um save.

### 1.2 O travamento conhecido

Existe um **travamento sem causa conhecida**, e ele acontece do seu lado: quando o personagem do
convidado é **injetado no seu mundo**, o seu jogo pode fechar. Sem mensagem de erro, sem crash
registrado — só some.

Não é o save corrompendo, é o processo saindo. Ainda assim:

- **Salve antes** de convidar alguém.
- Se acontecer, **anote o contexto**: quem fez o quê, se tinha inimigo perto, se era chefe.
- `kit/coop/INVESTIGATION.md` tem o registro técnico completo. Se você souber usar um depurador,
  capturar uma pilha de chamadas resolveria isto.

---

## Parte 2 — Preparar o PC do anfitrião

### 2.1 Confira a versão do jogo

`CrimsonDesert.exe` → botão direito → Propriedades → Detalhes → **Versão do arquivo**:

```
1.0.0.3460
```

O jogo já se atualizou sozinho **duas vezes** no meio deste projeto. Nas duas, o mod parou de ler o
jogo, sem travar e sem estragar o save — só parou.

> **Coloque em "Só atualizar este jogo quando eu iniciar"** (Steam → botão direito → Propriedades →
> Atualizações). Assim você vê a atualização antes dela quebrar a noite de teste.

### 2.2 Instale o mod

```powershell
.\scripts\instalar-host.ps1
```

O script:
- **recusa** se o jogo estiver aberto (a menos que você use `-Force`, e não use)
- faz backup do `.asi` anterior com data e hora
- **verifica o SHA256 depois de copiar** — não confia que a cópia deu certo

### 2.3 Confira a instalação

Na pasta `bin64` do jogo devem existir:

| Arquivo | Estado esperado |
|---|---|
| `cdmp.asi` | o mod |
| `cdmp.ini` | perfil **host** |
| `winmm.dll` | o carregador (pode ter vindo como `dinput8.dll`, renomeado) |

O `cdmp.ini` do anfitrião precisa ter:

```ini
[net]
role=host                           ← você é o anfitrião
transport=steam

[steam]
peer_steamid=                       ← VAZIO. Ele descobre o convidado

[coop]
enabled=1                           ← o interruptor principal
```

**`role=host` é o que muda tudo.** Com `role=guest` você tentaria conectar a si mesmo.

### 2.4 O convidado precisa ser seu amigo na Steam

A descoberta usa a lista de amigos. **Não é amigo, não acha.**

---

## Parte 3 — Antes de abrir o jogo

### 3.1 Feche o que grava a tela

O painel do mod (ImGui sobre DX12) convive bem com DLSS e geração de quadros, mas **grave a tela pelo
Steam ou pelo Windows**, não por um overlay de terceiros, se puder.

### 3.2 Combine o ponto de encontro

Antes de abrir, combine com o convidado **o lugar exato** do mapa. Sugestão: a primeira cidade, ou um
acampamento conhecido dos dois.

Vocês precisam estar no mesmo lugar para a descoberta funcionar.

### 3.3 Avise o convidado para não abrir ainda

Você abre **primeiro**. Ele espera.

---

## Parte 4 — A sessão

### 4.1 Abra o jogo e carregue um save

Espere o mundo carregar de verdade — você andando, não na tela de carregamento.

### 4.2 Espere 30 segundos parado

### 4.3 Confira o log — esta é a verificação mais importante

Abra `bin64\cdmp.log` e procure estas linhas:

```
Host version: 1.0.0.3460  image base: 0x140000000  image size: 0x13EE0000  PE timestamp: 0x6AE58024
Game reader enabled (build 1.0.0.3460 offsets)
Local player: in world
Local: pos (-22349.06, 601.05, -10026.89) ... | check vs game global n/a
```

| Linha | O que significa |
|---|---|
| `Host version: 1.0.0.3460` | o build foi reconhecido |
| `Game reader enabled (build 1.0.0.3460 offsets)` | **o mod está lendo o jogo** |
| `Local player: in world` | o personagem foi encontrado |
| `Local: pos (x, y, z)` com números reais | a posição está sendo lida |
| `check vs game global n/a` | **normal e esperado** (veja abaixo) |

> **Sobre o `n/a`:** é o autocontrole do mod se abstendo, porque o segundo endereço de posição do jogo
> mudou de conteúdo neste build. **Abster-se é correto.** O que seria errado é aparecer um número tipo
> `21849.89 m` — aí o mod estaria reportando lixo como se fosse medida.

> **A verificação que funciona de verdade é o movimento.** Ande alguns passos e confira que o `pos`
> no log **muda junto**. Se mudar, a leitura está certa.

### 4.4 Se aparecer esta linha, PARE

```
Game reader DISABLED: unsupported game build. Only networking will run.
```

O jogo se atualizou de novo e o mod precisa ser re-portado. **Não insista** — vocês vão conectar e
nada vai aparecer. Me avise e pare por hoje.

### 4.5 Chame o convidado

Avise que você está no mundo. Ele abre, carrega o save dele e vai para o ponto combinado.

### 4.6 Cheguem perto um do outro

Menos de 50 m. Aí:

1. **Olhe em volta.** Você vê o personagem dele?
2. **Ele olha em volta.** Ele vê o seu?
3. **Os dois andam.** Cada um diz se vê o outro andando.

> **A pergunta que decide tudo:** vocês **se veem** no mundo?
>
> O painel mostrar `connected` e uma distância **não prova isso**. Já aconteceu de a distância
> funcionar e o personagem não existir na tela. São duas coisas, e as duas precisam ser sim.

---

## Parte 5 — Depois que vocês se encontrarem

Só siga se o passo 4.6 deu certo. Se não deu, pare e mande o log — **essa resposta já é o resultado**.

### 5.1 Inimigos compartilhados

1. Vá até um acampamento de bandidos **com o convidado perto**
2. **Ele olha:** aparecem inimigos no mundo dele?
3. **Ele bate** num inimigo. Você vê a barra de vida daquele inimigo cair?
4. **Deixe você dar o golpe final**

### 5.2 Loot compartilhado

1. Matem um inimigo comum juntos (não chefe)
2. **Ele vasculha o corpo.** Apareceu loot para ele?

### 5.3 Regra de chefe — importante

Em chefe: o convidado **vê e machuca**, mas **o golpe final é sempre seu**. Se ele matar, **a sua
missão trava**.

A missão dele **não avança** e o chefe **não dropa** para ele. Isso é de propósito: o chefe é do seu
mundo, não do dele.

### 5.4 Use o `Ctrl+F12` para marcar o momento

`Ctrl+F12` grava uma **marca numerada** no `cdmp.log` dos dois lados, com a hora exata. Quando vocês
apertam **no mesmo instante**, os dois logs ganham a mesma marca — e aí dá para **alinhar as duas
linhas do tempo** e ver o que cada lado fazia no instante de um problema.

Aperte junto com o convidado (combinem: *"agora!"*) nos momentos que importam:

- o boneco **apareceu**
- o boneco **sumiu**
- o dano **não contou**
- o jogo **travou**

É a ferramenta mais útil que existe para diagnosticar sem estar na frente do outro PC.

---

## Parte 6 — Encerrar

1. **Saia do mundo vocês dois** (voltem ao menu, ou fechem normalmente)
2. **Só então** salve, se quiser salvar
3. **Não apague nada:** os `cdmp.log` dos dois são o resultado do teste

---

## Parte 7 — Coletar o resultado

### Do seu PC

- `bin64\cdmp.log`
- se existirem: `bin64\cdmp_packets_*.bin` e `.log`
- uma foto do seu painel

### Do convidado

- o `cdmp.log` dele
- **uma foto do painel dele**, com a linha `Other player:` visível

### Responda em uma frase cada

1. Apareceu `connected`? Nos **dois**?
2. **Alguém viu o boneco do outro?** Quem viu o quê?
3. Os seus inimigos apareceram no mundo dele?
4. Ele conseguiu pegar loot?

---

## Se der errado — o que anotar

| Sintoma | O que fazer |
|---|---|
| **O jogo travou/fechou sozinho** | Anote o contexto: quem fez o quê, inimigo perto, chefe. Feche, anote, mande |
| `Different mod versions` | Você e ele usam `cdmp.asi` diferentes. **Os dois precisam do MESMO zip** |
| `Game reader DISABLED` | O jogo atualizou. Precisa re-portar. Pare |
| Conectou, mas ninguém vê boneco | **É o resultado que procurávamos.** Mande os logs e diga |
| Nenhum painel | O mod não carregou. Confira se o `winmm.dll` está em `bin64` |
| O convidado não aparece conectado | Vocês são amigos na Steam? Ele usou o mesmo zip? |
| `Camera: camera block sentinel mismatch` | Esperado. É por isso que o boneco aparece parado de frente |

### Estado atual conhecido

| Funciona | Não funciona |
|---|---|
| Conectar, distância, vida do outro no painel | **Ver o boneco** (nunca confirmado) |
| Inimigos do anfitrião no mundo do convidado | Rotação do personagem remoto |
| Dano do convidado contando | Ícone no minimapa |
| Loot de inimigo comum para o convidado | Sincronia de horário |
| Missões do convidado intactas | Missão/loot de chefe para o convidado |

---

## Checklist do anfitrião

```
ANTES
  [ ] Backup da pasta save (com a data no nome)
  [ ] Versão do jogo = 1.0.0.3460
  [ ] .\scripts\instalar-host.ps1 rodou
  [ ] cdmp.ini tem role=host
  [ ] O convidado é seu amigo na Steam
  [ ] Ponto de encontro combinado
  [ ] Avisou o convidado para esperar

DURANTE
  [ ] Abriu o jogo e carregou um save
  [ ] Esperou 30 s parado
  [ ] Log diz "Game reader enabled (build 1.0.0.3460 offsets)"
  [ ] Log diz "Local player: in world" com posição real
  [ ] Andou e a posição MUDOU no log
  [ ] Chamou o convidado
  [ ] Chegaram a menos de 50 m
  [ ] VOCÊS SE VEEM?   <- a pergunta principal

DEPOIS
  [ ] Saíram do mundo antes de salvar
  [ ] Guardou os cdmp.log dos dois
  [ ] Fotografou o painel do convidado
  [ ] Respondeu as 4 perguntas
```
