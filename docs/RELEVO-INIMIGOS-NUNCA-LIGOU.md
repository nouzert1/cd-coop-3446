# O relevo de inimigos nunca ligou — e ninguém sabia

Descoberto em **2026-10-30**, numa sessão ao vivo com o jogo aberto, o mundo carregado e a
cópia do jogador aparecendo (teste de eco com `cdmp_peer --mode relay`).

Build 1.0.0.3446 (PE `0x6AE46DD0`).

---

## O sintoma

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

## Como confirmar que está consertado

1. `powershell -File scripts\testar-um-pc.ps1 -Prepare`
2. Abrir o jogo, carregar o save, andar
3. `powershell -File scripts\testar-um-pc.ps1 -Run`

E procurar no `cdmp.log`:

| linha | significa |
|---|---|
| `Puppet: action-layer crash guard installed` | **as guardas instalaram** (era o que faltava) |
| ausência de `Enemy copies disabled` | o relevo está armado |
| `Enemy relay: zone … WOULD copy N of M` | chegando ao acampamento, o relevo veio |

Sem a primeira linha, nada disto mudou.
