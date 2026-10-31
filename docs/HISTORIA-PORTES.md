# História dos ports — o que quebrou em cada atualização

Registro factual. Cada vez que o jogo se atualizou, o mod parou de ler o jogo do mesmo jeito, e cada
vez a causa foi **diferente** — é isso que torna este documento útil: o padrão que se repete não é a
causa, é o **modo de falha**.

| Port | Build | PE timestamp | Quem fez |
|---|---|---|---|
| Original | 1.0.0.2976 | `0x6AB28F00` | ByJunter |
| 1º port | 1.0.0.3424 | — | este fork |
| 2º port | 1.0.0.3446 | `0x6AE46DD0` | este fork |
| 3º port | 1.0.0.3460 | `0x6AE58024` | este fork |

O jogo se atualizou sozinho **duas vezes no meio do projeto** (3446 e 3460). Nas duas, o mod não
travou, não corrompeu save, e desligou a leitura com a mesma linha de log:

```
Game reader DISABLED: unsupported game build. Only networking will run.
```

---

## O que se repetiu em todos os ports

**A região de dados é reorganizada, não deslocada.** Isto apareceu duas vezes e é a lição mais cara:

- No 3460, `0x71B1A40` (que no 3446 era o `kWorldSystemSlot`) passou a conter um
  `GlobalVariableManager`.
- No 3460, os quatro globais restantes (`kCameraSlot`, `kMinimapIconRoot`, `kClientFrameClockMs`,
  `kStaticPlayerPos`) passaram a conter uma **string UTF-16**, `0xFFFF`, lixo e **ponteiros**.

Não existe delta a aplicar. Onde o 3446 guardava o mundo do jogo, o 3460 guarda strings de
configuração e tabelas de flags.

**Os offsets de struct sobrevivem.** `kWorldSystem_ActorManager 0x30`,
`kActorManager_ControlledActor 0x50`, `kActor_ComponentTable 0x68`,
`kComponents_CharacterControl 0x40`, `kActor_Key 0x60`, `kControl_Inner 0x140` — todos idênticos
através de 3424 → 3446 → 3460. Endereços e globais de dados não sobrevivem.

**Os nomes das seções PE são falsos** e são embaralhados a cada patch. Selecionar código por
`IMAGE_SCN_MEM_EXECUTE` e por conteúdo, nunca por nome.

---

## 3446 → 3460: os detalhes

**O que se moveu, medido vtable por vtable:**

| Item | Delta |
|---|---|
| `.rdata` dos handlers | `+0x4000` |
| `kVtControlledActor`, `kVtCharacterControl` | `+0x4010` |
| `kVtStatusComponent` | `+0x4000` |
| `kVtClientActorManager` | `+0x4018` |
| Métodos de movimento | `+0x990` |
| `GlobalVariableManager` | `+0x5680` |

**Cinco deltas diferentes num patch só.** Três vtables concordaram e a quarta não. Um delta único
teria produzido uma guarda que passa *às vezes* — pior que uma que nunca passa, porque gera um mod
meio-vivo e um log plausível.

**O tamanho encolheu 3,5 MB e não era código.** Era a seção `.debug` (o executável-isca de 195 MB).
`.text` moveu-se em centenas de bytes.

**Contagem de classes RTTI idêntica:** 15262 no 3446, 15262 no 3460.

**O array Troc:** `0x6E86D10` … `0x6EBA378`, 1175 handlers, span `0x33660` — **byte-idêntico ao
3446**, deslocado `+0x4000`.

---

## 3446: o que se sabe

Registrado em `offsets_3446.h`. O delta 3424 → 3446 também **não** foi uma constante, e o comentário
naquele arquivo já dizia isso — foi aprendido de novo no patch seguinte.

`kServerOtherEquipWriter` foi declarado errado **já no 3446**: a assinatura de 16 bytes no header não
bate com um byte sequer do endereço declarado. O `memcmp` falhava sempre, então equipamento nunca foi
transmitido, em build nenhum, silenciosamente.

---

## Erros de método que se repetiram

Três vezes neste projeto um valor **parecido com um resultado** foi aceito e estava errado:

| Valor | Parecia | Era |
|---|---|---|
| `-88.3066` | uma coordenada | um ponteiro lido como f32 |
| `(1.0, 0.0, 0.1745)` | uma posição | um vetor de direção normalizado |
| `check vs game global 0.00 m` | verificação perfeita | o default do struct; a verificação nunca rodou |

O terceiro tem correção estrutural (`static_pos_error` nasce `-1` e imprime `n/a`). Os dois primeiros
não têm — está sugerido em `BUGS-ABERTOS.md` §4.5.

**A regra que saiu disso:** validar contra algo que o código produtor **não controla**. Um dump cru
de bytes, um segundo candidato, o RTTI do próprio jogo, ou a coisa se movendo.

---

## Armadilhas da ferramenta

Todas atingidas neste projeto, todas produziram número confiante e errado:

1. **`troc <begin> <end>` é POSICIONAL.** `--begin X --end Y` é ignorado em silêncio e a faixa padrão
   é varrida. Devolveu 0, que parecia "não está aqui".
2. **`xrefs` reporta o operando deslocado**, não o início da instrução. Três "sites" para um global
   eram uma instrução contada três vezes.
3. **`scan` sem `--heap` não lê memória viva.** Devolveu 0 para uma vtable que existia.
4. **O prefixo é `exe+0x…`** lendo o módulo e `0x…` lendo a heap. Um regex ancorado em `^\s*0x` não
   casa nada.
5. **A saída pode terminar com `(decimal)`** e/ou `-> object .?AVName@pa@@`. Pegar o valor depois de
   `:`, não o primeiro hex (esse é o endereço).

---

## O build não é reproduzível

Medido: compilar o mesmo código commitado duas vezes produz binários diferentes em **575 KB**.
Causa: o MSVC mescla os `.obj` numa ordem dependente de paralelismo, então o pool de strings muda de
lugar e todo ponteiro para ele se move. As 33.660 strings são idênticas **como conjunto**.

Não afeta compatibilidade: o mod compara `kModBuild` (constante compilada), não hash. Duas pessoas
com o mesmo commit têm SHA256 diferentes e pareiam corretamente.

O SHA256 prova *"este é o arquivo que testei"*. **Não** prova *"veio do commit X"*.
