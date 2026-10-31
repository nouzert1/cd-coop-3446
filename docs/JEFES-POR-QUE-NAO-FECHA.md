# Jefes: por que a missão do convidado não avança e por que o jefe não dropa para ele

Duas frases da meta, tratadas como "pela metade" há várias rodadas. Investigadas até o
código e os dados. **Nenhuma das duas é um defeito de implementação** — são consequências
de decisões de desenho, e cada uma tem um caminho conhecido que a pesquisa já mapeou e
adiou.

Build 1.0.0.3446 (PE `0x6AE46DD0`). Endereços de pesquisa são do 1.0.0.2976 e estão
marcados como tal nos documentos originais.

---

## 1. O jefe não dropa para o convidado

**Não é bug. É uma exclusão deliberada, numa tabela de segurança — e a razão é boa.**

### O mecanismo do loot do convidado

O loot vive no cadáver e é entregue pelo **servidor que o matou** (`botin-invitado.md` §0.1).
A cópia do inimigo existe **só no cliente do convidado**, então matá-la não gera loot:
não há servidor nenhum atrás dela.

A solução do mod é o **gêmeo**: o servidor do próprio convidado cria um ator que faz o papel
do inimigo, e o loot sai dele — loot **por jogador**, como num co-op normal. Cada um tem o
seu.

### Onde ele é bloqueado

`loot_twin.cpp:224`:

```cpp
if (enemy_load::is_excluded_variant(variant)) {
    why = "a boss or unique enemy";
}
```

E a tabela que alimenta isso, `enemy_tables_2976.h:72`:

```cpp
// 957 characterinfo variants (load +0x18) never hidden nor relayed by zone:
// their name has Boss, MiddleBoss or Unique (each player sees their own).
inline constexpr uint32_t kExcludedVariants[] = { ... };
```

**957 variantes.** O comentário diz o essencial: *cada jogador vê o seu*.

### Por que a exclusão existe (e é correta)

`botin-invitado.md` §6 lista as regras de segurança do gêmeo. A linha da variante:

> `V` hostil segundo a tabela de facções, **sem jefes, élites, únicos nem atores de cenário
> ou missão**

O gêmeo é criado no mundo **do convidado**. Um gêmeo de jefe seria:

- um jefe aparecendo no mundo de quem **nunca teve aquela etapa**;
- e o loot dele sairia do servidor do convidado, por uma variante cujo **estado de missão
  não existe** ali.

O documento é explícito sobre o limite de confiança: *"Todo lo decide G con datos propios.
H solo puede afirmar 'la copia C murió'".* O convidado **não pode verificar** se aquela
variante é legítima de jefe no mundo dele, porque o jefe **nunca esteve** no mundo dele.

### O que **funciona** hoje com jefes

`pendiente-jefes.md` §4.5, e isto importa para não vender menos do que existe:

- **HP e morte do jefe** por `VaryHPAck` e `NotifyHandleDeadAck`;
- **ações e posições da IA**, que roda no cliente do host;
- **os golpes do jefe na marionete**;
- **a mudança de fase**, porque quem a decide é a IA do host ao ver o HP — e serve o HP que
  o convidado tirou.

Ou seja: **o combate conjunto de jefe funciona**. O que não existe é o **loot** do jefe
para o convidado.

### O caminho conhecido, e por que está adiado

`pendiente-jefes.md` §3, **enfoque D**: *jefes gêmeos* — cada mundo joga a sua própria
etapa. É o único desenho que faria as duas pontas avançarem.

Está adiado no próprio documento, e a razão é de risco: exige que o mundo do convidado
execute uma etapa de missão que ele **não tem**. `botin-invitado.md:456` já alerta sobre a
variante errada: *"No pedir nunca una variante que no sea de tipo 3: se crearía..."*.

**Liberar jefes no gêmeo sem o enfoque D daria loot de um jefe que não existe no mundo do
convidado** — exatamente o tipo de ator órfão que a pesquisa marca como risco médio
(`botin-invitado.md` §7, tabela de riscos).

---

## 2. A missão do convidado não avança

**Também por desenho.** `pendiente-jefes.md` §4.8:

> a etapa, a recompensa e o avanço de missão são de H;
> **G não avança sua missão nem recebe loot** (como em Genshin)

A razão é estrutural: **a etapa é do mundo do host**. O convidado luta o jefe, causa dano
real, vê a barra — mas o script que decide "a missão avançou" vive no mundo do host e
escreve no save do host.

Isso **é o comportamento pedido** numa das quatro exigências originais:

> *"realizar missões para ajudar o anfitrião dono da missão (isso não afeta o convidado no
> sentido de suas missões)"*

A missão do convidado **não avançar** é a mesma coisa que **não ser afetada**. Está
funcionando como especificado.

O que faria os dois avançarem é o mesmo **enfoque D** acima, e o documento também o adia.

---

## 3. Tipos de registro 4, 5 e 7

`pendiente-jefes.md:100` põe *"tipos 4 e 5, partes do jefe, agarres e jefes gemelos"* em
**"después"**, e a razão está na linha 67:

> o revezamento só copia o tipo 3. Se um jefe chega como tipo 4 (personagem com nome) ou
> **5 (veículo: tanques, dragão, avião)**, hoje não se copia. Um tipo 5 tem ainda o
> **risco de fechamento conhecido** (`0x925F0E`)

O dragão é **tipo 5**. Ligar isso sem validação ao vivo é o caminho direto para o
fechamento que já custou uma sessão inteira de diagnóstico (ver `DIAGNOSTICO-HANG.md`).

### ATUALIZAÇÃO (rodada 30): o tipo 4 foi implementado; o 5 continua recusado

A regra saiu do `enemy_relay.cpp` e virou uma função **pura e testável** em `boss_rules.h`:

```cpp
inline bool is_relayable_record_type(uint32_t type, bool is_boss) {
    if (type == 3) return true;    // pessoa, sempre
    if (type == 4) return is_boss; // nomeado: SÓ jefe (pesquisa linhas 400 e 458)
    return false;
}
```

O `load_is_relayable` do `enemy_relay.cpp` é agora um invólucro de uma linha que fornece o
que a regra não pode ver sozinha: se a chave é um jefe conhecido. Nove `CHECK`s prendem o
comportamento, incluindo o que mais importa:

```cpp
CHECK(!net::is_relayable_record_type(5, true));   // veículo jefe (dragão): ainda recusado
```

**Se alguém relaxar o tipo 5 para fazer jefes dragão funcionarem, essa linha falhando é o
objetivo.** Leia a linha 401 e a linha de risco R2 antes: o dragão é tipo 5, e ligá-lo sem
resolver o ramo de veículos fecha o jogo.

| tipo | o que é | estado |
|---|---|---|
| 3 | pessoa | relevado, sempre |
| **4** | **nomeado** | **SÓ se for jefe** — implementado, **não verificado ao vivo** |
| 5 | veículo (tanque, avião, **dragão**) | **recusado** — risco `0x925F0E` |
| 7 | armas/partes do jefe | não relevado sozinho; são **ATACANTES válidos** |

O tipo 4 nunca rodou numa luta de jefe real. O que o valida até agora: compila, os nove
testes passam, a regra segue a pesquisa. **Isso não é o mesmo que ter visto funcionar.**

---

## 4. Resumo honesto

| Item da meta | Estado real |
|---|---|
| exploração conjunta | implementado |
| **combate de jefe conjunto** | **funciona** — HP, IA, golpes, fases |
| missão do host sem afetar o convidado | **funciona** — é o desenho |
| loot comum compartilhado | implementado, provado no protocolo |
| **loot de jefe para o convidado** | **bloqueado por desenho** (§1) |
| **missão do convidado avançar** | **não acontece por desenho** (§2) |
| tipos 4/5/7 | 4 implementado, **não testado**; 5 recusado por risco; 7 são atacantes (§3) |
| **teste real 2 PCs** | ❌ **o bloqueio de verdade** |

### A conclusão que interessa

Os dois itens que a meta chama de "pela metade" **não são trabalho inacabado** — são
fronteiras de desenho que a pesquisa identificou antes de escrever código, com o caminho de
saída (enfoque D) mapeado e **conscientemente adiado por risco**.

Escrever o enfoque D agora, sem jogo ao vivo, significaria implementar uma etapa de missão
inteira no mundo do convidado **sem nunca ter visto uma etapa rodar**. É o mesmo erro que
custou cinco rodadas de endereços errados, numa escala maior.

**Nada aqui se destrava sem o teste de 2 PCs.**
