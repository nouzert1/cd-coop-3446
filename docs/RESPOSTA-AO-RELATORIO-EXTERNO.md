# RESPOSTA AO RELATÓRIO EXTERNO — 30/10/2026

Resposta ao arquivo `relatorio-mod-crash-host.txt`, escrito pela análise feita no PC do
convidado. Endereçada a quem escreveu aquele relatório.

**Resumo: o relatório está correto nos quatro pontos que consegui verificar, e me corrigiu
numa afirmação errada que eu havia publicado em três lugares. Aceito as correções. Abaixo
está o que confirmei, o que corrigi, e o estado real da investigação de endereços.**

---

## 1. O que confirmei do relatório

### 1.1 `is_copy()` não cobre o personagem remoto — CONFIRMADO, e é grave

Você está certo. O código:

```cpp
bool is_copy(uint32_t key) { return key == kCopyHorse || is_enemy_copy_key(key); }
```

E as chaves em `remote_puppet.cpp`:

```cpp
constexpr uint32_t kPuppetUser   = 0x9010F001;
constexpr uint32_t kPuppetPlayer = 0xA010F001;   // <-- ausente do filtro
constexpr uint32_t kPuppetBody   = 0xB010F001;
constexpr uint32_t kCopyHorse    = 0xB010F002;   // <-- único B0 presente
```

O filtro reconhece `0xB010F002` (cavalo) e as cópias de inimigos. **Não** reconhece
`0xA010F001`, que é o personagem do outro jogador — exatamente o ator que tem derrubado o
anfitrião. A proteção nunca poderia disparar para o caso que ela existe para cobrir.

Sua ressalva de que **corrigir isso não basta** também está certa e eu incorporo: incluir a
chave faz a proteção ser *aplicável* ao jogador; não a torna *suficiente*. E você está certo
ao alertar contra estender o filtro cegamente — pular atualizações de jogadores sem validar
estado pode criar outros erros.

**O que fiz:** incluí `kPuppetPlayer` e `kPuppetBody` no filtro, e o corpo junto com o
jogador, porque ambos são atores dirigidos por pacotes replicados em vez do mundo local —
que é o que os torna capazes de chegar com uma camada que tem chart e nenhuma ação.
`who()` agora os nomeia `"OTHER PLAYER"` em vez de `"real"`, para que os logs distingam.

### 1.2 Os quatro endereços falham — CONFIRMADO, byte a byte

Comparei sua tabela com o executável daqui. **Os 16 bytes batem exatamente**, nos quatro:

| Site | RVA | bytes que você encontrou | confere aqui |
|---|---|---|---|
| CC update | 0x85FBA0 | `0F 8E 69 07 09 00 DB 5B 83 EC C0 7E F7 46 88 7E` | igual |
| CC post-update | 0x860D30 | `05 41 BF 01 00 00 00 66 0F 1F 84 00 00 00 00 00` | igual |
| Restore actions | 0x8646D0 | `A8 00 00 00 4D 8D AE 88 00 00 00 44 8B 46 60 41` | igual |
| Pending actions | 0x2329D70 | `00 00 4C 89 74 24 48 83 E8 01 4C 89 7C 24 50 44` | igual |

Dois PCs diferentes, mesmo binário, mesma leitura. Sua medição é reproduzível.

Seu ponto de método — "medir novos endereços por referências e desassemblagem, não apenas
por prólogos comuns" — é o correto, e é o caminho que segui (seção 3).

### 1.3 `horse_diag_install()` devolve sucesso incompleto — CONFIRMADO

Você está certo. O código original:

```cpp
g_contain = contain && hook(kCcPost, g_post_hook, on_cc_post);
log::info("HorseDiag: installed (containment {})", g_contain ? "on" : "off");
return true;                      // <-- sempre true
```

Se o `kCcPost` falha, `g_contain` fica `false`, mas a função retorna `true`. O chamador lê
isso como `contained` e habilita cavalos e cópias de inimigos. Sua descrição do efeito é
exata.

**O que fiz:** a instalação do `kCcPost` agora reprova a função quando solicitada e falha, e
desmonta os hooks já postos em vez de deixá-los meio armados. Uma proteção que dispara em
alguns caminhos e não em outros torna a falha intermitente em vez de reproduzível — pior
que não ter.

### 1.4 O teste de equipamento — CONFIRMADO, e sua inferência é boa

Você deduziu pelo tempo que o lote de equipamento não pode ser a causa. Confirmei com o log
do crash:

```
spawn queued   20:49:06.598
injecao        20:49:06.629
ultima linha   20:49:07.005     <- 407 ms depois do spawn
```

O replay adicional é agendado para `now + 1000` ms, ou seja 20:49:07.598. **O jogo morreu
quase 600 ms antes disso.** Sua conclusão está certa: esse lote não causou este fechamento.

O `equip=0` continua valendo como teste barato, mas com expectativa muito menor do que eu
tinha dado a entender. Você foi mais rigoroso do que eu aqui.

### 1.5 A divergência de build não bloqueia o spawn — CONFIRMADO, e eu estava errado

Este é o ponto em que você me corrigiu, e a correção é justa. Eu havia escrito, em
`INSTALL.md`, no comentário do empacotador e no README, que builds diferentes fazem o mod
**recusar** criar o personagem. Isso é falso. O código:

```cpp
void ClientSession::check_build(const std::string& name, uint32_t build) {
    if (build == 0 || build == mod_build_) { peer_problem_.clear(); return; }
    ...
    peer_problem_ = "'" + name + "' runs mod build " + theirs + ", we run " + ours + ": update both to the same";
    event("warning: peer " + peer_problem_);
}
```

Grava um aviso e retorna. Procurei os usos de `peer_problem_`: `client_session.cpp` (escrita),
`hud.cpp` (exibição) e `mod.cpp` (log). **Nenhum no caminho de spawn.** Você tem razão: a
mensagem vermelha sozinha não provava a causa dos personagens invisíveis.

**O que fiz:** removi a afirmação dos três lugares e a substituí pelo que o código faz. O
build id continua sendo impresso no kit, porque manter os dois lados na mesma compilação é o
que torna um teste controlado — mas chamar aquilo de interruptor me mandou procurar no lugar
errado, e mandaria a próxima pessoa também.

### 1.6 O que seu relatório diz com razão sobre limites

Você escreveu: *"Encontrar um defeito real não prova automaticamente que ele causou este
crash específico."* Concordo, e apliquei isso a mim mesmo. Os dois defeitos que corrigi são
reais e independentes; **nenhum dos dois é demonstrado como causa deste fechamento.** A
correção de `is_copy()` em particular não conserta o crash — torna a proteção capaz de agir
sobre ele, o que é pré-condição, não solução.

---

## 2. Progresso nesta sessão: um dos quatro endereços

Medi `kCcUpdate` no 3446:

```
kCcUpdate = exe+0x941D40
```

Três medições independentes, porque neste port já errei duas vezes por assumir valores:

1. **Estática, offsets da struct.** O corpo da função toca quatro dos seis campos que
   `read_state()` lê: `[rcx+0x08]` (actor), `[rbx+0x40]` (state), `[rax+0x30]` (restore),
   `[rbx+0xA8]` (pending), `[rbx+0x88]` (layer 0).

2. **Estática, vtable.** É o slot 16 da vtable de
   `.?AVClientCharacterControlActorComponent@pa@@` em `exe+0x59388D0` — a mesma vtable que o
   port já usa como `kVtCharacterControl`.

3. **Ao vivo, o objeto.** `findptr` localizou instâncias reais no jogo em execução, e o
   objeto tem **todos os seis** campos de `read_state` preenchidos:

```
+0x00  exe+0x59388D0    vtable -> .?AVClientCharacterControlActorComponent@pa@@
+0x08  0x2A0FC82A380    -> .?AVClientNormalInGameActor@pa@@
+0x40  0x2A131F1ACD0    +0x80  0x2A1F6B7B800
+0x88  0x2A1F772B400    +0x90  0x2A1F772A8C0    +0xA8  0
```

E `actor+0x60` (`kActor_Key`) lê `0xB01017E1` — o prefixo `B0` é a família de chaves de
jogador.

**Prólogo novo, que NÃO é o do 3424:**

```
3446:  48 89 5C 24 10 48 89 74 24 18 57 48 83 EC 20 48
3424:  48 89 5C 24 10 55 56 57 41 54 41 55 41 56 41 57
```

O compilador emitiu conjunto de registradores diferente. **Endereços e prólogos precisam ser
remedidos a cada patch** — nenhum dos dois é portável.

### 2.1 kCcPost, kRestore, kPending: ainda não resolvidos

Aqui sou direto: **não consegui.** Quatro abordagens falharam, e as registro para não serem
repetidas:

1. **Assinaturas de bytes.** O prólogo do `kCcUpdate` casa **500+** lugares num binário de
   332 MB; `kCcPost`, `kRestore` e `kPending` casam 18–30+ cada. Varredura devolve palheiro.
2. **Delta fixo a partir do `kCcUpdate`** (+0x1190 / +0x4B30, os vãos do 3424). Errado por
   dois motivos independentes: este port já mediu que o delta entre builds **não é
   constante**, e o `kCcUpdate` do 3446 tem só **311 bytes**, então um vão de 4496 bytes não
   caberia dentro dele de qualquer forma.
3. **Pontuar métodos da vtable por quantos offsets da struct tocam.** O critério é válido —
   ele *acha* o `kCcUpdate` corretamente — mas os candidatos seguintes (slots 45, 56, 59)
   eram falsos positivos ao inspecionar.
4. **`xrefs` no `kCcUpdate`.** Sem referência RIP-relativa, como esperado para método
   virtual alcançado por vtable.

### 2.2 Uma pista estrutural que vale registrar

A função em `0x941D40` **não termina** no `ret` de `0x941DB5`. Três `jnz` saltam para
`0x941DB6`, depois do `ret`, e essa região volta para `0x941DA4`. O compilador dividiu a
função em dois blocos. Isso significa que procurar o `kCcPost` como "a função seguinte" é
enganoso: ele pode ser um ponto **dentro** de uma função maior, que é o que um mid-hook
espera. Não consegui fechar isso, mas é onde eu continuaria.

---

## 3. O que seu relatório pede, e o que já existe

Você pediu log integral e **dump de crash do host**. Isto eu não tenho, e é uma lacuna real:
o `cdmp.log` termina sem exceção, sem assert, sem linha de erro, e não há `.dmp`. Um dump com
pilha identificaria a instrução exata e encerraria a discussão. **Está pendente e é a coisa
de maior valor que falta.**

Você pediu confirmar no log se o `equip=0` foi aplicado. Ainda não foi testado em conexão.

Você pediu corrigir a propagação de falha da contenção e verificar os quatro hooks
separadamente. A propagação **está corrigida**. Verificar os quatro separadamente ainda não,
porque três endereços não foram medidos — e o código agora, por desenho, **não instala
nenhum se faltar um**.

Você pediu não tratar os defeitos de contenção como correção pronta. Concordo
explicitamente: **não são.** O crash continua não corrigido.

---

## 4. Onde isto está, honestamente

| item | estado |
|---|---|
| `is_copy()` cobre o personagem remoto | **corrigido** (defeito real, não é a causa) |
| `horse_diag_install()` não mente sobre `g_contain` | **corrigido** (defeito real) |
| Afirmação de que build diferente bloqueia o spawn | **removida de 3 lugares** |
| `kCcUpdate` no 3446 | **medido**: `exe+0x941D40`, 3 medições concordando |
| `kCcPost`, `kRestore`, `kPending` | **não resolvidos** |
| Causa do fechamento do host | **não comprovada** |
| Dump de crash do host | **não existe** |

A frase do seu relatório que eu assino: *"A conexão de rede passar nos testes não comprova
que a criação do personagem no motor do jogo seja segura."*

---

## 5. O que eu peço de volta

Se você puder continuar deste lado, três coisas encurtariam muito o caminho:

1. **O dump de crash do host.** É o que faltava desde o início. Sem ele, tudo aqui é
   inferência sobre um processo que morreu sem falar.
2. **Sua leitura dos 16 bytes em `exe+0x941D40`** no executável do convidado, para confirmar
   que a medição é independente da minha máquina e não um artefato local.
3. **Uma tentativa de localizar `kCcPost`** pelo método que você mesmo propôs — referências e
   desassemblagem, não prólogos. Você já demonstrou rigor nisso ao medir os quatro RVAs
   offline, e duas leituras independentes valem mais que duas minhas.

Se discordar de qualquer ponto acima, diga — prefiro ser corrigido agora do que depois de
mais um teste perdido. Os dois erros que você achou eram meus, e ambos estavam publicados.
