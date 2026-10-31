# O relevo de inimigos nunca ligou — e ninguém sabia

Descoberto em **2026-10-30**, numa sessão ao vivo com o jogo aberto, o mundo carregado e a
cópia do jogador aparecendo (teste de eco com `cdmp_peer --mode relay`).

Build 1.0.0.3446 (PE `0x6AE46DD0`).

---

## TRÊS defeitos, não um

O relevo ficou morto por **três causas independentes**, todas encontradas nesta sessão. Cada
uma sozinha bastava para desligá-lo, e cada uma **falhava em segurança** — deixando a sessão
com aparência perfeitamente normal.

| # | defeito | onde | consequência |
|---|---|---|---|
| 1 | assinaturas dos guards não batiam em build nenhum | `offsets_3446.h` | `puppet_install_layer_guards()` → `false` → `enemy_set_receive_enabled(false)` |
| 2 | endereços com valores de 3424 | `offsets_3446.h` | idem |
| 3 | **a thread testava a flag de DEV** | `mod.cpp:787` | o loop nunca subiu; `g_auto` ficou setado e **ninguém leu** |

O terceiro é o mais instrutivo:

```cpp
// ANTES
if (init->enemy_relay && guarded) { /* sobe a thread */ }
// init->enemy_relay = in_game && cfg.dev_enemy_relay   <- [dev], default FALSE
```

A flag que o **usuário** configura, `[coop] enemy_auto` (default `true`, lida em
`config.cpp:199`), **nunca era consultada ali**. E o `run_network` chamava
`enemy_set_auto(cfg.coop_enemy_auto)` corretamente, então:

- `g_auto` era setado ✅
- o log de config não mostrava erro ✅
- o guard de crash instalava ✅
- e **nada consumia `g_auto`**, porque o loop que o lê não existia ❌

> **Uma flag que é escrita e nunca lida é indistinguível de uma função que funciona** — até
> alguém procurar a saída dela.

---

## LIMITE DO TESTE DE ECO (descoberto na rodada 33)

**O teste de eco NÃO consegue exercitar o relevo de inimigos.** Não é um defeito do mod — é
uma limitação do `cdmp_peer`.

`auto_tick()` (`enemy_relay.cpp:1030`) começa assim:

```cpp
PartnerZone zone;
{ std::lock_guard lock(g_mutex); zone = g_partner_zone; ... }
if (zone.on && !zone.dry) { zone_tick(...); return; }
```

E `g_partner_zone` **só é setado por `enemy_on_zone_request`** (linha 1367) — a mensagem
`EnemyZoneMsg` que **o convidado envia** dizendo onde ele está e o que quer copiado.

O `cdmp_peer` tem três modos, `relay` / `ghost` / `bot`, e **todos ecoam**. Nenhum gera
mensagem de zona, porque a zona é derivada da **posição do convidado no mundo dele** — algo
que um eco não tem.

Logo: com o peer, `zone.on` é sempre `false`, e `auto_tick` **retorna sem fazer nada** a cada
500 ms. O relevo está armado, o loop roda, e não há o que copiar porque **ninguém pediu nada**.

### O que isto significa para o plano de teste

| o que o eco prova | o que o eco NÃO prova |
|---|---|
| o boot instala os guards | a zona chegando do parceiro |
| a thread do relevo sobe | `zone_tick` escolhendo inimigos |
| `g_auto` sendo lido | cópias aparecendo |
| a cópia do jogador, movimento, equipamento | loot compartilhado, golpes, jefes |

**O relevo de inimigos — e com ele o loot compartilhado, os golpes do convidado e o dano
conjunto em jefes — só se prova com DOIS jogadores reais.** O eco chegou ao fim do que podia
provar.

Para o teste de 2 PCs, o `[coop] suppress=dry` faz o convidado pedir a zona **registrando o
que copiaria** sem copiar nada. É o primeiro teste a rodar: as linhas `WOULD SWEEP` do
convidado e `WOULD copy N of M` do host têm que **casar**.

---

## O sintoma (primeira descoberta)

Numa sessão inteira de eco, com o mundo carregado e a cópia do outro jogador visível:

- **nenhuma** linha `EnemyRelay`
- **nenhum** `WOULD COPY`
- **nenhuma** cópia de inimigo, de nenhum tipo

E, no meio do log, **duas linhas**:

```
WRN Puppet: PointClimb::Enter not recognised; wall climbs will freeze
WRN Enemy copies disabled: their crash guards could not be installed
```

A segunda é a explicação. Ela passa fácil: aparece uma vez, no boot, entre dezenas de
linhas de estado.

---

## A causa

`mod.cpp:771`:

```cpp
const bool contained = net::horse_diag_install(/*contain=*/true);
const bool guarded = contained && net::puppet_install_layer_guards();
...
} else if (!guarded) {
    log::warn("Enemy copies disabled: their crash guards could not be installed");
}
net::enemy_set_receive_enabled(guarded);
```

`guarded` era **falso**, então `enemy_set_receive_enabled(false)` — **o relevo de inimigos
ficou desligado a sessão inteira**.

E `puppet_install_layer_guards()` (`remote_puppet.cpp:2489`) exige que **duas** assinaturas
batam:

```cpp
if (game::safe_read(base + off::kActionLayerAdvance, h, sizeof h) &&
    std::memcmp(h, off::kActionLayerAdvanceHead, sizeof h) == 0) { ... }
```

---

## O defeito de verdade: as assinaturas nunca foram válidas

Medido contra o executável do 3424:

| site | bytes reais no endereço | head registrado | bate? |
|---|---|---|---|
| `kActionLayerAdvance` `0x1F63F70` | `18 B9 02 EB 05 E8 86 17 B9 02 …` | `48 8B C4 57 48 81 EC 80 …` | **não** |
| `kActionLayersAdvance` `0x2329700` | `74 51 4C 89 3F 44 38 3E 74 32 …` | `48 8B C4 41 54 41 56 48 83 EC 68 …` | **não** |

E a assinatura de `kActionLayersAdvance` **não existe em lugar nenhum** da imagem do 3424
(`scan`: **0 resultados**). Ela nunca descreveu função alguma naquele build.

**Um guard cuja assinatura foi escrita a partir do mesmo endereço errado que o alvo concorda
consigo mesmo e passa enquanto ninguém remedir.** É a **segunda vez** que isto acontece nesta
portagem: o `kServerOtherEquipWriter` (rodada 20) estava **um byte** fora, e o head tinha sido
escrito do mesmo endereço errado — a checagem confirmava o erro em vez de pegá-lo.

---

## O que `0x2329700` realmente é

Desmontado no 3424:

```
mov rbx, -1
inc rbx
cmp [rsi+rbx], r15b
jnz ...
mov ecx, ebx
call 0x15FE890            ; alocar
mov qword ptr [rbp+0x40], 0x105   ; um campo de tamanho
```

É **`strlen` + alocação + cópia de string**. Não há ação, camada nem componente.

E no 3446, o candidato análogo `0x232ABA0` é **a mesma função de string** — mesma sequência.
Então a identidade da "função-mãe" era coincidência de layout.

A família inteira (`0x232A530…0x232AED0` no 3446, `0x231C470…` no 3424) é manipulação de
string — **incluindo a que o mod chama de `kPending`**. Isso põe `kPending` em dúvida também,
e as notas da portagem já o chamam de elo mais fraco: *"em mais de 300 instruções a função
NÃO toca em `ClientCharacterControl`"*. Esta medição é **consistente com `kPending` estar
errado também**.

---

## O que foi corrigido

`kActionLayerAdvance`: 3424 `0x1F63F70` → 3446 **`0x2148D50`**. Encontrado por assinatura e
**confirmado pelo comportamento**, não pelos bytes: abre com
`push rdi / sub rsp,0x80 / vmovaps [rax-0x28],xmm7 / vxorps xmm7,xmm7,xmm7 / vcomiss xmm7,xmm3
/ mov rdi,rcx` — parâmetros float, comparações float, `rcx` como `this`. É um *advance*
movido por um delta.

`kActionLayersAdvance`: **continua 0**. Um endereço chutado instalaria um mid-hook sobre
código não relacionado, e a falha viraria **um fechamento** em vez de uma função desligada.

---

## Por que isto importa mais que o endereço

O relevo de inimigos — a base do **loot compartilhado**, dos **golpes do convidado** e do
**combate de jefe conjunto** — **nunca rodou**. Não numa sessão quebrada: em **nenhuma**.

Todas as medições de "protocolo provado" que fizemos foram de **código que compila**, não de
código que **já executou**. A verificação offline (`verify-port.ps1`) confere que os
endereços e assinaturas **concordam entre si** — e eles concordavam, porque os dois estavam
errados do mesmo jeito.

**A lição:** uma assinatura escrita do mesmo endereço errado que o alvo não é uma checagem,
é uma tautologia. E uma função que falha em segurança, silenciosamente, **parece exatamente
uma função que funciona** — até alguém ligar o log e reparar numa linha `WRN` no boot.

---

## RESOLVIDO — os dois sites medidos e provados

**`kActionLayerAdvance`**: 3424 `0x2147BA0` → 3446 **`0x2148D50`**
**`kActionLayersAdvance`**: 3424 `0x2329700` → 3446 **`0x232A8B0`**

```
kActionLayerAdvance  @0x2148D50  >>> PASSA: True
kActionLayersAdvance @0x232A8B0  >>> PASSA: True
```

**Os dois guards passam.** `puppet_install_layer_guards()` retorna `true` pela primeira vez.

### O método que funcionou

Não foi a assinatura, não foi o scan, não foi o prologo. Foi **âncora em código provado
idêntico** e depois **confirmação por contexto**:

1. **Achar uma âncora.** `kPending` é **byte a byte idêntico** entre os builds — medido,
   32 bytes de `0x2329D60` (3424) e `0x232AF10` (3446) batem exatamente. Isso fixa o
   deslocamento daquela região em **`0x11B0`**, e fixa a partir de código **provado ser o
   mesmo código** — não de dois endereços que só parecem relacionados.

2. **Aplicar o deslocamento.** `0x2329700 + 0x11B0 = 0x232A8B0`.

3. **Confirmar por contexto, não por semelhança.** 64 bytes em volta nos dois endereços:
   **63 idênticos**. O único diferente é o deslocamento de um `call rel32` no fim — que
   **tem** que diferir quando o alvo se move. Ou seja, a diferença é **evidência a favor**,
   não contra.

### E o `kActionLayerAdvance`?

O mesmo padrão, com uma volta a mais: o head **existe no 3424**, em `0x2147BA0` — **não** em
`0x1F63F70`. O valor no código estava errado por **`0x1E3C30`** desde sempre.

```
3424 exe+0x2147BA0: 48 8B C4 57 48 81 EC 80 00 00 00 C5 F8 29 78 D8  ← head
3446 exe+0x2148D50: 48 8B C4 57 48 81 EC 80 00 00 00 C5 F8 29 78 D8  ← idêntico
```

**O head estava certo. O endereço é que não.** Os dois sites falhavam por razões
**diferentes**, e tratá-los como um defeito só teria jogado fora um head correto.

### A armadilha que quase me pegou

No meio do caminho eu concluí que `kPending` também estava errado, porque a "função-mãe"
dele parecia uma `strlen`. **Estava errado.** O `kPending` é válido — a medição dos 32 bytes
idênticos provou isso. A lição: a função-mãe não é o hook, e julgar o hook pela mãe leva a
condenar código correto.

### O que mudou na verificação

`verify-port.ps1` agora tem uma seção **`code-address guards`** que lê os bytes **no
executável real** e compara com cada head do fonte. Isto existe porque a checagem antiga
comparava os endereços **entre si** — e eles concordavam, porque os dois estavam errados do
mesmo jeito. **Uma assinatura escrita do mesmo endereço errado que o alvo não é uma
checagem, é uma tautologia.**

Se um guard falhar ali, a mensagem agora diz o que isso custa:
*"the guard CANNOT pass; whatever it protects is disabled"*.

