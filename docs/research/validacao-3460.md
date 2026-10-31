# Validação ao vivo do 3460 — o que passou e o que falta

**Data:** 2026-10-31, build `95424FB4`. Jogo aberto, save carregado, personagem no mundo.

Este documento registra o resultado do primeiro teste do mod portado contra o jogo vivo. Ele
existe porque a diferença entre "o port funcionou" e "o port parece ter funcionado" é
exatamente o que este projeto errou várias vezes.

---

## O que PASSOU

### 1. O version guard aceitou o build

```
Host version: 1.0.0.3460  image base: 0x140000000  image size: 0x13EE0000  PE timestamp: 0x6AE58024
Game reader enabled (build 1.0.0.2976 offsets)
```

`kPeTimestamp = 0x6AE58024` e `kImageSize = 0x13EE0000` estão **corretos**. O mod não está mais
inerte — ele passa do guard e tenta ler o jogo.

(A linha "build 1.0.0.2976 offsets" é texto fixo em `mod.cpp:141`, não medição. Está errada como
descrição há três builds e não foi corrigida neste port.)

### 2. O array Troc funciona — e isto é a medição mais limpa do port

```
Troc: RemoveActorAck is opcode 3067 this build (was 2516)
Troc: MoveActorReq is opcode 2833 this build (was 2556)
Troc: MoveActorAck is opcode 3094 this build (was 2697)
Troc: StartActionReq is opcode 2202 this build (was 2223)
Troc: StartActionAck is opcode 2552 this build (was 2991)
Troc: RotateActorReq is opcode 2852 this build (was 2828)
Troc: RotateActorAck is opcode 3078 this build (was 2687)
Sniffer: injection enabled on this build's opcodes
```

`kTrocInstancesBegin = 0x6E86D10` / `kTrocInstancesEnd = 0x6EBA378` estão **corretos**. O mod
percorreu os 1175 handlers, identificou cada um pelo RTTI, e derivou os opcodes.

**Corroboração independente:** estes são os mesmos opcodes medidos por outras vias numa rodada
anterior, antes deste port existir. Duas derivações separadas concordam — a mais forte evidência
disponível para estes valores.

E há uma terceira: o `ActorLoadDataAck` continua `2005`, que é o que 13890 registros de captura
real mostraram num build anterior.

### 3. `kVtClientActorManager` está correto

Varredura da heap viva pelo ponteiro `0x14593DCF0`:

```
1 match(es)
  0x23D723D4600
```

Há **um** `ClientActorManager` vivo, e ele tem essa vtable. O valor está certo.

**E isto também estabelece que o `scan --heap` funciona.** As leituras contraditórias de uma
rodada anterior — onde `scan --heap` devolveu zero para uma vtable observada viva — foram erro
de uso meu, não defeito da ferramenta. Vale registrar, porque eu tinha escrito no header que o
instrumento "discorda de si mesmo", e isso agora está **provado falso**.

---

## O que FALHOU, e a causa

### `kWorldSystemSlot` está errado no 3460

O log repete, indefinidamente, com o personagem carregado e andando:

```
Local player: WorldSystem not created
Local: unavailable (ClientActorManager missing)
```

Lido ao vivo, o endereço em uso (`0x71B1A40`) contém um ponteiro para um objeto cuja vtable é
`GlobalVariableManager` — **não é o WorldSystem**.

### Por que, e por que o delta não ajuda

`GlobalVariableManager`:

| | 3446 | 3460 | delta |
|---|---|---|---|
| vtable | `0x5AA7028` | `0x5AAC6A8` | **+0x5680** |

O delta é `+0x5680`, diferente dos `+0x4000` (`.rdata` dos handlers), `+0x4010`/`+0x4018`
(vtables de componentes) e `+0x990` (métodos de movimento) medidos no mesmo port.

**Já são cinco deltas distintos num único patch.** A conclusão não é "tomar cuidado com deltas",
é que **um delta não é um instrumento de medição neste binário**. Qualquer um dos cinco,
aplicado à tabela inteira, teria acertado uma parte e errado o resto em silêncio.

A explicação provável do caso específico: o jogo **reordenou os objetos de sistema** em `.data`.
O `GlobalVariableManager` ocupa agora o endereço que era do WorldSystem. Não é deslocamento — é
troca de posição.

### `kStaticPlayerPos` também está errado

```
exe+0x71C0C20 (como f32): 97094178177024.0000
```

Não é coordenada. Lido como u64 são dois ponteiros. Mesma causa.

---

## O caminho para resolver (para a próxima rodada)

O que **não** funcionou, para não repetir:

- `xrefs` na imagem: reporta o endereço do **operando deslocado**, não o início da instrução.
  Os três "sites" de `0x71B1A40` no 3460 são a mesma instrução contada de formas diferentes
  (`0x3784A4` cai dentro de `mov rbx,rax`, que começa em `0x3784A2`).
- Procurar um global de módulo que aponte para a estrutura do `ClientActorManager`: **nenhum**.
  A estrutura em `0x13EC6xx` é alcançada por cadeia, não por global fixo.
- Assumir que `.data` não se move porque um endereço ainda tem 3 xrefs. Foi exatamente esse
  raciocínio que produziu a conclusão errada, e o número de xrefs era o mesmo nos dois builds.

O que **deve** funcionar, e ainda não foi tentado:

1. **`scan --heap` pelo ponteiro do `ClientActorManager`** (`0x23D723D4600`) — os endereços
   devolvidos foram `0x13EC6F0` (a própria estrutura), `0x13EC630` e `0x13EC650` (lista interna).
   Subir mais um nível a partir daí deve levar ao global, ou à cadeia que o jogo usa.
2. **Rastrear o construtor do WorldSystem**: achar a função que **escreve** em
   `kWorldSystemSlot` no 3446 e localizar a equivalente no 3460 pelo prólogo. Um escritor é
   mais estável que um leitor, e o endereço escrito está na instrução.
3. **Perguntar ao jogo**: o `GlobalVariableManager` agora ocupa `0x71B1A40`. O WorldSystem deve
   estar num endereço **vizinho** — as duas rodadas de medição mostraram que `.data` mantém os
   objetos de sistema numa faixa contígua (`0x70CDEA8` a `0x71C0C20` no 3446). Vale varrer essa
   faixa procurando um ponteiro cuja vtable resolva para um nome de "sistema" plausível.

---

## O que este teste NÃO prova

- Nada sobre o co-op em si. O mod não chega a ler o jogador, então nenhum caminho de rede foi
  exercitado com dados reais.
- Nada sobre os outros offsets de dados (`kCameraSlot`, `kChunkOrigin`, `kMinimapIconRoot`,
  `kClientClock*`). Eles estão nas mesmas condições e são suspeitos pela mesma razão.
- Os offsets de **código** (`kClientPostPacket`, `kClientOnRecvPacket`, `kActionLayerAdvance`,
  `kMinimapIconDecide`, os três `Enter`) **não** foram exercitados neste teste. Eles têm
  confirmação por bytes de prólogo, que é forte, mas é confirmação de identidade e não de
  funcionamento.
