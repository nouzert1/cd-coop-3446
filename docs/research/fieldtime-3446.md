# kFieldTimeClient no 3446: o que foi medido e onde a busca parou

**Data:** 2026-10-31. **Build:** 1.0.0.3446 (PE `0x6AE46DD0`, base `0x140000000`).
Tudo aqui é ao vivo, com o mundo carregado (pid 37620, personagem em `-10497, 610, -4366`).

Este documento existe porque a busca chegou a um ponto onde **o que foi descartado vale mais
que o que foi achado**, e porque três das conclusões negativas custaram horas e seriam repetidas
por qualquer um que pegasse o item do zero.

---

## 0. Resumo

| pergunta | resposta |
|---|---|
| O `kFieldTimeClient = 0x6EB2AD8` herdado está certo? | **Não.** 32 bytes de zero, com o controle dando real |
| Isso quebra alguma coisa hoje? | **Não.** `[coop] time_sync` é 0 por padrão |
| A `FieldTime` de 2976 ainda descreve o 3446? | **Provavelmente não.** `kRawDay` não está mais no binário |
| Achei o endereço novo? | **Não.** Ver §5 para os dois caminhos que faltam |

---

## 1. O endereço herdado está zerado, e o controle prova que a leitura é válida

Medido com `cdmp_probe --pid 37620`:

```
exe+0x6EB2AD8   kFieldTimeClient    32 bytes de 0x00
exe+0x71C0C20   kStaticPlayerPos    -10497.2725, 610.6083, -4366.0308   <- real
exe+0x70CDCAD   kClientClockGlobal  1
```

O controle é o que torna isto conclusivo. Sem ele, "32 bytes de zero" não distingue
*"o endereço mudou"* de *"o mundo ainda não carregou"* — e as duas levam a ações opostas.
Com a posição do jogador em coordenadas de mundo reais e o relógio em 1, o mundo está
carregado e a sessão está viva. **O endereço mudou.**

`scripts/check-fieldtime.ps1` já faz exatamente essa leitura com esse controle, e é o que
deve ser rodado de novo depois de qualquer tentativa de conserto.

### Uma armadilha de ferramenta, registrada porque custou tempo

O `cdmp_probe` no modo live (`--pid`) quer **endereço absoluto**, não RVA:

```
--pid 37620 read 0x1406EB2AD8   -> <unreadable>        ERRADO
--pid 37620 read 0x146EB2AD8    -> 0x0, 0x0, ...       CERTO
```

O `--image` (arquivo em disco) aceita as duas formas e imprime `exe+0x...`, o que faz parecer
que `--pid` também aceita. Não aceita, e a falha é um `<unreadable>` silencioso que parece
"endereço inválido" em vez de "endereço mal formado". Um `read` de controle num endereço
sabidamente bom (a posição do jogador) separa os dois casos em um comando.

---

## 2. `kRawDay` não está mais no binário

`FieldTime::from_raw` (`src/common/field_time.h`) decompõe o tempo com
`kRawDay = 75'600'000` = `0x4819080`. Procurando essa constante no exe de 3446:

```
scan "80 19 48 04"        (u32)  -> 0 ocorrências
scan "80 19 48 04 00 00 00 00"  (u64)  -> 0 ocorrências
```

Ela não existe no binário em nenhuma das duas formas. Isso **não prova** que o layout mudou —
o compilador pode ter dobrado a constante numa sequência de multiplicações, ou o divisor pode
estar numa tabela de dados. Mas significa que o caminho "achar o escritor pela constante que
ele usa" está fechado, e que a suposição de que a struct de 2976 ainda vale precisa de
evidência própria antes de ser usada.

**Estado: não verificado.** A struct de `field_time.h` (day/hour/minute/second/ms/weekday/anchor,
32 bytes) é uma herança de 2976 que ninguém remediu.

---

## 3. O caminho que MAIS funcionou: handler Troc -> serviço -> escritor

O `FieldTime` chega ao cliente pela mensagem `TrocTrSetFieldTimeAck`. O caminho até o handler:

```
cdmp_probe --pid 37620 troc --max 2000 | findstr FieldTime
  exe+0x6E86DC0   .?AVTrocTrSetFieldTimeAck@pa@@
  exe+0x6EA4C70   .?AVTrocTrSetFieldTimeReq@pa@@
```

Lendo a instância do handler em `exe+0x6E86DC0` com os offsets que `troc_sniffer.cpp:366-367`
usa (`kTroc_Kind = +0x08`, `kTroc_Opcode = +0x0C`):

```
+0x00 = 0x598DE38        vtable do handler
+0x08 = 0xB8800000001    kind = 1 (Ack)
+0x0C = 0x7FC6            opcode = 32710
```

A vtable `exe+0x598DE38` tem três métodos (`0xC5EAB0`, `0xC5EA40`, `0xC9B8E0`); o terceiro é
o handler de verdade — é o único com corpo (`sub rsp,0x130`, oito registradores salvos), e
compara contra opcodes vizinhos (`mov eax,0x7FC1`) antes de despachar.

Dentro dele, a cadeia até o serviço de mundo:

```asm
exe+0xC9BAA7   mov rax, [0x00000001471B1A38]     <- kWorldSystemSlot
exe+0xC9BAAE   mov rcx, [rax+0x30]
exe+0xC9BAB2   ...
exe+0xC9BAC3   mov rcx, [rcx+0x11A0]
exe+0xC9BACA   call 0x0000000140B3F070           <- aplica o FieldTime
```

**`exe+0xB3F070` é a função que aplica o tempo.** Ela é grande (~900 instruções, `sub rsp,0x210`)
e faz um *lookup* em tabela pelo valor recebido:

```asm
exe+0xB3F168   mov r10, [0x00000001471B5728]     <- StageInfoManager
exe+0xB3F16F   mov ebx, [rbp+0x178]              <- o raw time da mensagem
exe+0xB3F17F   mov ecx, [r10+0x68]
exe+0xB3F18D   mov eax, ebx
exe+0xB3F18F   div ecx                            <- raw / [r10+0x68]
exe+0xB3F194   shl r8, 0x08
exe+0xB3F198   add r8, [r10+0x78]
exe+0xB3F1B2   cmp [r8+rax*8+0x08], ebx          <- procura o raw numa tabela
```

`[r10+0x68]` medido em `2081` — **não** é `75600000`. Seja o que for essa divisão, ela não é a
decomposição em dia/hora da `FieldTime` de 2976. **Isto é a evidência mais forte de que a
struct mudou**, e é o fio a puxar primeiro.

---

## 4. `kWorldSystemSlot` está 8 bytes à frente do que o jogo usa

O header tem `kWorldSystemSlot = 0x71B1A40`. O código do jogo, no handler acima, usa
**`0x71B1A38`**. Os dois endereços contêm ponteiros válidos e diferentes:

```
exe+0x71B1A38 -> 0x5CE904E4D40    (o do jogo)
exe+0x71B1A40 -> 0x5CE8A43E400    (o do header)
```

Seguindo cada um por `[+0x30] -> [+0x11A0]`:

| partida | `[+0x30]` | `[+0x11A0]` | destino |
|---|---|---|---|
| `0x71B1A38` (jogo) | `0x5CE8BF4DC00` | `0x5CE9002F660` | tabela de subsistemas, válida |
| `0x71B1A40` (header) | `0x5CE8A3F4600` | **`0xC000000000000000`** | ponteiro inválido |

**O valor do header leva a um ponteiro inválido seguindo a mesma cadeia que o jogo usa.**

Isto **não** significa que `kWorldSystemSlot` está errado para o que o mod faz com ele: o mod
o usa para chegar ao slot do mundo (`player_reader.cpp:41`, `actor_lookup.cpp:35`) e a posição
do jogador é lida corretamente por esse caminho — medido, `-10497, 610, -4366`, batendo com o
que o mod reporta. Provavelmente `0x71B1A40` é o slot certo e `0x71B1A38` é o endereço de um
campo vizinho que por acaso também é um ponteiro, e a cadeia do tempo passa por outro offset.

**Mas os dois não podem estar certos ao mesmo tempo para a mesma cadeia**, e isso precisa ser
resolvido antes de usar qualquer um dos dois para achar o tempo.

---

## 5. Os dois caminhos que faltam

### 5.1 Seguir `exe+0xB3F070` até a escrita final

A função aplica o tempo. Ela escreve apenas em `0x7225B3C`..`0x7225B64` (verificado: todas as
escritas em memória global da função, ~900 instruções, caem nessa faixa de 48 bytes), e essa
faixa está **toda zerada** em repouso — são registros de reflection, não o tempo.

Logo a escrita real acontece **fora** dela, numa das chamadas. A não explorada é
`call [rax+0x140]` em `exe+0xB3F205`, logo depois de
`mov rax,[r14+0x68] / mov rcx,[rax+0x1A0]`. Seguir esse ponteiro virtual ao vivo
(`rtti` no objeto, `dump` na vtable, slot `+0x140`) é o próximo passo concreto.

### 5.2 Achar um global que MUDE quando o tempo passa

Nenhuma varredura por "valores plausíveis" funcionou: `day` entre 1 e 4000 deu 13 candidatos e
todos eram falsos positivos (o `1486` recorrente é `0x5CE`, a metade alta dos ponteiros da heap,
não um dia). O critério que **não** engana é **mudança temporal**: ler a mesma faixa duas vezes
com minutos de intervalo e exigir que o valor tenha avançado na direção do tempo.

Uma varredura de 8 segundos no objeto do subsistema (`0x5CE9002F660`) deu **zero campos
alterados** — coerente com ser uma tabela de ponteiros, e é assim que se descarta.

O intervalo tem que ser de **minutos**, não segundos: `FieldTime` guarda dia/hora/minuto/segundo
como campos separados, então o byte que muda com o tempo muda devagar, e um `ms` que avança
rápido só aparece se o campo existir.

---

## 6. O que NÃO fazer (já tentado, já falhou)

- **Procurar o prólogo de uma função de tempo.** O prólogo de 3424 é genérico (20+ ocorrências
  no 3446). Foi assim que `kPointClimbEnter` ficou anos errado — ver o commit `8459937`.
- **Aceitar um endereço porque *algum* dado plausível está lá.** As 13 ocorrências de
  "day entre 1 e 4000" eram todas ponteiros. Um endereço só vale depois que se sabe o que
  **escreve** nele, ou que ele **muda** como o tempo muda.
- **Usar o `0x20D3360` que um comentário do header chama de `fromRaw`.** Desmontado, é
  interpolação de spline (`vsubss`/`vmulss` sobre pontos) — não tem nada a ver com tempo.
  O comentário está errado.
- **Ler com `--pid` usando a forma `exe+...` ou o RVA cru.** Ver §1.
