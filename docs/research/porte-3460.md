# Re-porte 3446 → 3460: o que foi medido

**Data:** 2026-10-31. **Build novo:** 1.0.0.3460, PE `0x6AE58024`, `SizeOfImage 0x13EE0000`,
329.084.312 bytes em disco. **Build antigo:** 1.0.0.3446, PE `0x6AE46DD0`, `0x14268000`.

A Steam atualizou o jogo durante a madrugada de 30 para 31/10, às 12:56. O `cdmp.log` da
primeira execução depois disso confirma o efeito exato que o version guard produz:

```
Host version: 1.0.0.3460  image base: 0x140000000  image size: 0x13EE0000  PE timestamp: 0x6AE58024
Game reader DISABLED: unsupported game build. Only networking will run.
Local player: unsupported game build
```

O mod carrega, conecta, e **não lê o jogo**. É exatamente o comportamento desenhado — e é a
razão de o teste de 2 PCs não poder ter acontecido antes do re-porte.

---

## 1. A boa notícia: a estrutura do jogo não mudou

| | 3446 | 3460 |
|---|---|---|
| Classes RTTI | 15262 | **15262** |

Idêntico. E todas as classes que o mod usa continuam presentes: `ClientActorManager`,
`ClientCharacterControlActorComponent`, `ClientStatusActorComponent`, `TrocTrStartActionAck`,
`TrocTrMoveActorAck`, `TrocTrSetFieldTimeAck`.

Os 3,5 MB a menos são da seção `.debug` (a decoy executável de 195 MB), não de código.

**Consequência prática:** o método RTTI, que resolveu o `PointClimb` em 31/10, **continua
funcionando**. Isso é o que torna este re-porte barato em vez de caro, e é o motivo de valer a
pena fazê-lo em vez de fazer downgrade: o custo por atualização cai, não sobe.

---

## 2. Os deslocamentos NÃO são uniformes — não usar delta cego

Medido por RTTI, vtable a vtable:

| vtable | classe RTTI | 3446 | 3460 | delta |
|---|---|---|---|---|
| `kVtControlledActor` | `ClientChildOnlyInGameActor` | `0x5907C90` | `0x590BCA0` | **+0x4010** |
| `kVtCharacterControl` | `ClientCharacterControlActorComponent` | `0x59388D0` | `0x593C8E0` | **+0x4010** |
| `kVtStatusComponent` | `ClientStatusActorComponent` | `0x590F6E0` | `0x59136E0` | **+0x4000** |
| `kVtClientActorManager` | `ClientActorManager` | `0x5939CD8` | `0x593DCF0` | **+0x4018** |

Três batem em `+0x4010` e o quarto é `+0x4018`. **Não é uma região que se moveu inteira** — é uma
faixa de `.rdata` de ~4 KB com conteúdo alterado dentro. Aplicar um delta único a tudo teria
acertado 3 de 4 e falhado silenciosamente no quarto, que é o pior resultado possível: um guard
que às vezes passa.

**Regra para este porte: resolver cada endereço pelo RTTI e confirmar pelo conteúdo. Nunca por
delta.**

---

## 3. Recuperados e CONFIRMADOS por conteúdo

Estes três são as correções de 31/10 — as que fizeram o `PointClimb` finalmente funcionar. Os
deltas são idênticos (`+0x990`), o que é o esperado do mesmo bloco de código:

| | 3446 | 3460 | vtable 3460 |
|---|---|---|---|
| `kPointClimbEnter` | `0x75F630` | **`0x75FFC0`** | `PointClimbMovementMethod` @ `0x591D6A8` |
| `kRideOnEnter` | `0x74E8E0` | **`0x74F270`** | `RideOnMovementMethod` @ `0x591D868` |
| `kRideOffEnter` | `0x74F8B0` | **`0x750240`** | `RideOffMovementMethod` @ `0x591D758` |
| `kVtWallUpMovementMethod` | `0x5918F78` | **`0x591CF78`** | `WallUpMovementMethod` @ `0x591CF78` |

**Não aceitos pelo número.** Os prólogos foram lidos byte a byte:

```
0x75FFC0   4C 8B DC 49 89 5B 10 49 89 6B 18 49 89 73 20 57   == kPointClimbEnterHead  OK
0x74F270   48 8B C4 48 89 58 10 48 89 70 18 55 57 41 54 41   == kRideEnterHead        OK
```

É o mesmo código, não uma coincidência de RTTI.

O slot `Enter` está em **`+0x38`** nas três, como no 3446.

---

## 4. Recuperados, com a distância como corroboração

| | 3446 | 3460 | confirmação |
|---|---|---|---|
| `kClientPostPacket` | `0x3A55B0` | **`0x3A5A30`** | prólogo limpo |
| `kClientOnRecvPacket` | `0x3A5940` | **`0x3A5DC0`** | distância `0x390` **igual nos dois builds** |

O par é o mesmo: a distância entre as duas funções não mudou. Isso é corroboração independente
do nome ou da assinatura.

**Achado colateral:** o valor do **3446** (`0x3A55B0`) não cai num prólogo — desmontado, lê
`add [rax],al` / `cmp byte ptr [rbp],0x0`, que é meio de instrução. O valor do 3460
(`0x3A5A30`) cai num prólogo limpo (`mov [rsp+0x10],rbx` / `push rbp` / ...). Ou seja: o
endereço do 3446 estava deslocado, e o hook do sniffer provavelmente **nunca** foi instalado
nesse build — o que explicaria parte do que se atribuiu a outras causas.

---

## 5. Um SEGUNDO endereço errado no 3446: kServerOtherEquipWriter

Isto não é sobre o 3460, é sobre o 3446 — e é o mesmo padrão do `kPointClimbEnter`.

O header declara:

```c
inline constexpr uintptr_t kServerOtherEquipWriter = 0x29EDD11;
inline constexpr uint8_t kServerOtherEquipWriterHead[] = {0x48,0x8B,0x84,0x24,0xE0,0x10,0x00,0x00,
                                                          0x48,0x8B,0x10,0x48,0x85,0xD2,0x74,0x0A};
```

Lido o endereço no 3446:

```
exe+0x29EDD11:  74 5A 33 FF 39 87 76 20 66 0F 1F 44 00 00 ...
esperado:       48 8B 84 24 E0 10 00 00 48 8B 10 48 85 D2 74 0A
```

**Não bate em byte nenhum.** O guard em `capture_install_equip_hook()` faz `memcmp` e sempre
falha, então o mod sempre loga `OtherEquipItemAck writer not recognised; equipment changes won't
be sent` — e **nunca** engancha. Equipamento do outro jogador nunca foi transmitido, em build
nenhum.

E a assinatura, procurada no binário inteiro, dá **12+ ocorrências no 3446 e 12+ no 3460**, todas
do mesmo idioma:

```asm
call [0x...45589040]        ; xacquire lock / unlock
mov rax, [rsp+0x10E0]       ; <- a "assinatura"
mov rdx, [rax]
test rdx, rdx
```

Isto é **`std::unique_lock` inlined**, não um escritor de equipamento. Cada ocorrência é um
mutex diferente. A assinatura de 16 bytes não identifica classe nenhuma — ela identifica um
idioma do compilador.

**Estado: não resolvido.** O que se sabe é que o valor do 3446 está errado e que a assinatura
não serve para reencontrá-lo. Achar o escritor de verdade exige outro caminho — provavelmente
pelo handler de `TrocTrOtherEquipItemAck`, do mesmo jeito que o `SetFieldTimeAck` levou ao
escritor do tempo (§6).

---

## 6. O método que está funcionando, escrito para o próximo

Para **vtables** e **métodos virtuais** (resolve tudo, não depende de assinatura):

```
cdmp_probe --image <exe> classes <substring>            # acha o TypeDescriptor
cdmp_probe --image <exe> vtables ".?AVNome@@@pa@@"      # acha a vtable pelo nome EXATO
cdmp_probe --image <exe> dump 0x<base+vt+0x38> --size 8 # lê o slot
```

Duas armadilhas, as duas custaram tempo hoje:

1. **O nome tem que ser o exato do RTTI.** `kVtControlledActor` NÃO é
   `.?AVControlledActor@pa@@` — esse nome não existe. O certo é
   `.?AVClientChildOnlyInGameActor@pa@@`, e ele só aparece no comentário do `offsets_3424.h`.
   Buscar pelo nome que se *imagina* devolve "0 shown", que lê como "a classe sumiu" e não como
   "o nome está errado".

2. **Exigir o `COL`.** Uma vtable tem o CompleteObjectLocator em `[vt-8]`, e `COL+0x0C` é a RVA do
   TypeDescriptor. Se `[vt-8]` aponta para código (`0x5C2A50`, `0x941EE0`) em vez de `.rdata`
   (`0x61xxxxx`), não é vtable. Foi assim que se descobriu que um delta de `+0x4010` produzia
   endereços plausíveis mas errados.

Para **funções de código**, a ordem que funcionou:

1. Procurar a assinatura do prólogo, se houver.
2. Se a assinatura for genérica (mais de ~3 ocorrências), **comparar as ocorrências entre os dois
   builds** — as listas se alinham e o delta por linha identifica o par. Foi assim que os 5
   candidatos do equip writer apareceram.
3. Confirmar por **estrutura de contexto** (distância até a função vizinha conhecida, como o
   `0x390` do Post/OnRecv), não pelo hit.
4. Desmontar e exigir um **prólogue plausível**. `add [rax],al` no endereço significa que o valor
   está no meio de uma instrução, e o valor está errado.
