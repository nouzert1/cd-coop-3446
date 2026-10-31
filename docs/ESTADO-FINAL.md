# Estado do projeto — 31 de outubro de 2026, 18:15

**Documento de encerramento.** Escrito antes do teste final, para que o resultado — seja
qual for — não precise ser reconstruído depois.

---

## O que existe hoje

Um mod de co-op para Crimson Desert **1.0.0.3460**, build **`D7FE9358`**, com dois kits de
instalação prontos e publicados.

**Repositório:** https://github.com/nouzert1/cd-coop-3446
**Release atual:** https://github.com/nouzert1/cd-coop-3446/releases/tag/v0.18.0-3460-fix

| Kit | Para quem | Papel |
|---|---|---|
| `cdmp-3460-role-swap-host.zip` | luan26david | anfitrião |
| `cdmp-3460-role-swap-guest.zip` | Nouzert SKINS | convidado |

---

## O que está comprovadamente funcionando

Estas coisas foram **medidas**, não presumidas:

| | Evidência |
|---|---|
| O mod carrega | `Exit watch: ... hooked` em 6 sessões seguidas |
| O sniffer lê os opcodes | 1175 tipos resolvidos |
| O leitor de posição funciona nos dois PCs | `Local: pos (-20626.62, 621.16, -6813.44)` |
| Os dois personagens foram criados | `Puppet: spawn queued` nos dois lados |
| O convidado viu o anfitrião | `co-op: other player loaded` |
| A sala Steam é criada | `Room: hosting, code 1YZDAWX` |
| A checagem de versão funciona | recusou builds diferentes corretamente |

**No teste de 17:11 os dois bonecos apareceram.** O co-op funcionou. O que falhou foi o
processo do anfitrião, ~1 segundo depois.

---

## O que foi corrigido hoje

### 1. A posição zerada era timing (fechado)

Nas duas primeiras tentativas a posição do convidado chegou `(0,0,0)` em 216 medições
seguidas. No terceiro teste chegou correta. **O mundo dele ainda estava carregando.**

A guarda em `player_reader.cpp` testava `|y - 1000| < 5` — o valor que a leitura antiga
produzia. Com a leitura nova devolvendo `(0,0,0)`, a guarda parou de casar em silêncio.

**Corrigido:** aceita as duas formas, mais uma segunda guarda em `remote_puppet.cpp` para
que um pacote ruim não mate o receptor.

### 2. O travamento antes do menu era meu erro (fechado)

A build `A8AE702B` travava o jogo **dos dois jogadores**, antes do menu, em PCs diferentes.

Comparando com a build que funcionava, **uma única mudança**:

```
src/mod/game/exit_watch.cpp | 186 +++
src/mod/game/exit_watch.h   |  34 +++
src/mod/mod.cpp             |   6 ++
```

Eu interceptei `RaiseException`, que o runtime do C++ usa como **fluxo normal** — nomear
threads, cada `throw`. Meu hook rodava alocação e lock dentro do despacho de exceção,
milhares de vezes por inicialização.

**Corrigido:** não intercepta mais. O hook grava num buffer fixo, sem alocação, sem lock,
sem formatação. E o teste ganhou três verificações que teriam pego o erro — inclusive
**2000 throws seguidos**.

### 3. A lição que se repetiu cinco vezes

> **Um número plausível é o estado padrão de um número não medido.**

Cinco valores pareceram resultado e não eram:

| Valor | O que era |
|---|---|
| `-88.3066` | um ponteiro lido como float |
| `(1.0, 0.0, 0.1745)` | um vetor de direção |
| `check vs game global 0.00 m` | o default de uma struct |
| `531655.81 m` | lixo passando pela guarda |
| `2097558656.00 m` | o mesmo, ainda acontecendo |

E uma sexta, que não era número: **`"their world is probably still loading"`** — um palpite
vestido de conclusão, que atrasou o diagnóstico em horas.

**Corolário:** uma opção aceita e ignorada produz um zero confiável, e um zero confiável é
indistinguível de uma descoberta.

---

## O que NÃO funciona (por escolha, não por defeito)

O mod **falha fechado** de propósito nestes pontos:

- Rotação do boneco — não há base de cálculo (`rot (0.000, 0.000, 0.000, 1.000)`)
- Sincronia de tempo
- Ícone no minimapa
- Cavalo e cópias de inimigos na 3460
- Loot de boss pelo convidado — **a missão do convidado não avança, que é o pedido**

Os avisos de startup na 3460 são offsets ainda não recuperados e **não impedem conectar**.

---

## O que nunca foi testado

- O teste `Ctrl+Home` de laboratório com nativos
- Chefes conjuntos (fase D2): tipos de registro 4 e 7
- `kServerOtherEquipWriter` — errado também na 3446; a rota é o handler `TrocTrOtherEquipItemAck`

---

## Se o teste final falhar

**O que fazer com o que existe:**

1. **Os dumps.** `C:\Users\ACER\AppData\Local\CrashDumps\CrimsonDesert.exe.*.dmp` guardam a
   pilha de crashes reais. O WinDbg está instalado nesta máquina. Um dump de crash vale
   mais que qualquer quantidade de logs.

2. **A pista mais forte não investigada.** No teste de 17:11 o anfitrião morreu logo após
   `Inject: delivered opcode 2005 (16937 bytes)`, **mas o convidado passou pela injeção
   equivalente e sobreviveu**. Os payloads eram de tamanhos diferentes:
   `16932 + 6445` de um lado, `16500 + 6453` do outro. **Essa assimetria nunca foi
   explicada.**

3. **As duas assimetrias descartadas.** `remote states 0` vs `962` é idade de sessão, não
   defeito. `session 1` (connecting) enquanto funcionava é rótulo atrasado. Ambas
   verificadas lendo o código; registradas para não serem reinvestigadas.

---

## O que aprendi sobre este problema

**O método que funciona:**

> Ancorar em código provado byte a byte idêntico, confirmar pelo contexto em volta,
> confirmar **pelo que o código faz** — nunca por um acerto.

**O que não funciona:**

> Aceitar um número porque ele apareceu.

**E a lição mais cara de hoje, que não é técnica:**

O teste unitário passava enquanto o mod quebrava o jogo de duas pessoas. Ele chamava a
função patcheada **uma vez**, de uma thread calma — a única situação onde o problema não
pode aparecer.

**"Compila, instala e o teste passa" era verdade de um hook que quebrou dois jogos.**

---

## Agradecimento, registrado porque é merecido

**O agente do outro jogador foi competente e agiu como par.** Leu o repositório, fez só
chamadas de leitura, **recusou corretamente instalar um kit incompatível**, identificou que
um hash vinha de nenhum release publicado, e fez um backup verificado antes de mexer.

**A única premissa errada dele veio de um arquivo velho que nós deixamos na pasta do jogo.**
A culpa foi nossa, não dele — e foi o que motivou o `COMO-INSTALAR.md` que agora acompanha
cada kit.
