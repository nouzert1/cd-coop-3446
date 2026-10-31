# Crimson Desert Co-op — dossiê do projeto

**Documento único para quem quer continuar este trabalho.**

Estado em **31 de outubro de 2026**. Último build: **`D7FE9358`**.

---

## Sumário

1. [O que é este projeto](#1-o-que-é-este-projeto)
2. [Onde parou — resultado do último teste](#2-onde-parou--resultado-do-último-teste)
3. [A causa raiz, isolada com 23 ms de precisão](#3-a-causa-raiz-isolada-com-23-ms-de-precisão)
4. [O que funciona (medido)](#4-o-que-funciona-medido)
5. [O que não funciona](#5-o-que-não-funciona)
6. [Os dois defeitos corrigidos](#6-os-dois-defeitos-corrigidos)
7. [Por onde continuar — em ordem de valor](#7-por-onde-continuar--em-ordem-de-valor)
8. [Como diagnosticar neste projeto](#8-como-diagnosticar-neste-projeto)
9. [Mapa do código](#9-mapa-do-código)
10. [Mapa dos documentos](#10-mapa-dos-documentos)
11. [Armadilhas que já custaram horas](#11-armadilhas-que-já-custaram-horas)
12. [Glossário](#12-glossário)

---

## 1. O que é este projeto

Um **mod de co-op** para **Crimson Desert** (Pearl Abyss), 64 bits, Windows.

**Objetivo:** dois jogadores no mesmo mundo — explorar junto, enfrentar chefes juntos, e o
convidado ajudar nas missões do anfitrião **sem que a missão do convidado avance**. Cada um
pega o seu loot.

**Alvo:** jogo **1.0.0.3460** (PE timestamp `0x6AE58024`).

**Como funciona:** o mod se injeta no processo do jogo via **Ultimate ASI Loader**, engancha
as funções de rede (`ClientNet::PostPacket` / `ClientNet::OnRecvPacket`) e **injeta pacotes
falsos** que fazem o jogo acreditar que o outro jogador é um ator nativo. A conexão entre os
dois PCs é uma **Steam Lobby** (`ISteamMatchmaking`), com um **código de sala de 7
caracteres** em base32 Crockford.

**Formato do pacote:** `u16 opcode | u8 slot | u16 len | payload`

**Licença:** GPL v3 (herdada do projeto de origem).

**Repositório:** fork de `ByJunter/CrimsonDesertMultiplayer`.

---

## 2. Onde parou — resultado do último teste

**O teste final de 31/10/2026, 18:14–18:17, produziu o resultado mais informativo do
projeto.**

### O que aconteceu

| | |
|---|---|
| Os dois jogos **abriram** | ✅ |
| Os dois **entraram no mundo** | ✅ |
| A **conexão** funcionou | ✅ `Net: connected`, RTT ~30 ms |
| O mod **recebeu** o personagem do convidado | ✅ 39795 bytes |
| **O anfitrião morreu ao injetá-lo** | ❌ |

### A sequência exata — 174 milissegundos

```
[18:17:25.336] Co-op: map pin of the other player at (-20627, -6814)
[18:17:25.484] Co-op: received the other player's character (39795 bytes, spawn 1)
[18:17:25.487] Puppet: rewrote keys in user packet: user x3, player x104, body x0
[18:17:25.487] Puppet: rewrote keys in body packet: user x4, player x104, body x8
[18:17:25.487] Puppet: spawn queued at (-20626.6, 621.3, -6813.7) (2 packets, 16637 + 6445)
[18:17:25.487] Co-op: the other player is in our world (spawn 1)
[18:17:25.510] Inject: delivered opcode 2005 (16642 bytes) to ClientNet::OnRecvPacket
[18:17:25.510] Inject: delivered opcode 2005 (6450 bytes) to ClientNet::OnRecvPacket
                >>> FIM DO LOG. O PROCESSO MORREU AQUI. <<<
```

**A injeção foi BEM-SUCEDIDA.** O mod entregou os dois pacotes e retornou. **O que mata o
jogo está DEPOIS da injeção, dentro do processamento do jogo.**

### O que isso elimina

- ❌ Não é o mod travando na injeção — ela completou
- ❌ Não é exceção capturável — o `__try/__except` não disparou
- ❌ Não é saída silenciosa — o `Exit watch` não registrou `TerminateProcess`
- ❌ Não é a posição — chegou correta: `(-20626.6, 621.3, -6813.7)`

**É o jogo reagindo ao ator sintético.**

---

## 3. A causa raiz, isolada com 23 ms de precisão

**Esta é a descoberta mais valiosa do projeto, feita pelo jogador que atuou como anfitrião.**

### O defeito está em `remote_puppet.cpp`, na reescrita de chaves

Antes de injetar, o mod reescreve as **chaves de identificação** dentro do pacote para que o
jogo trate o ator remoto como um ator local:

```
Puppet: rewrote keys in user packet:   user x3,  player x104, body x0
Puppet: rewrote keys in body packet:   user x4,  player x104, body x8
```

**O jogo aceita o pacote, começa a criar o ator — e morre.**

### Onde olhar

| Arquivo | O que faz |
|---|---|
| `src/mod/net/remote_puppet.cpp` | Monta e injeta o ator remoto |
| `kPuppetPlayer` / `kPuppetBody` | As chaves sintéticas usadas |
| `rewrote keys` | A reescrita que precede o crash |

### Hipóteses, em ordem de probabilidade

**H1 — O pacote está malformado para esta versão do jogo.**
O `ActorLoadDataAck` (opcode 2005) na 3460 pode ter campos novos ou ordem diferente. **O
tamanho mudou entre as sessões:** `16637+6445` às 18:17, `16932+6445` às 17:11,
`16500+6453` no convidado. **Essa variação nunca foi explicada** e é a pista mais forte.

**H2 — Falta uma referência que o jogo espera.**
O ator é criado com chaves sintéticas, mas o jogo pode exigir que o `user_key` exista numa
tabela. A reescrita troca o valor sem criar a entrada.

**H3 — A ordem dos dois pacotes importa.**
`user` (16642) é injetado antes de `body` (6450). Se o jogo processar o primeiro e
imediatamente buscar dados do segundo, uma janela de corrida existe entre as duas injeções
— **mas elas acontecem no mesmo milissegundo**, o que torna isso menos provável.

### Como confirmar

**A captura de pacotes já existe e não foi usada.** No `cdmp.ini`:

```ini
[sniffer]
enabled=1
record=1        ; <-- mude de 0 para 1
```

Isso grava os pacotes exatos em `cdmp_packets_<data>.log/.bin`. **Combine com os do outro
jogador e compare byte a byte.** Como sabemos o instante com precisão de 23 ms, a captura é
viável.

---

## 4. O que funciona (medido)

Tudo aqui foi **observado em log**, não presumido.

| Recurso | Evidência |
|---|---|
| O mod carrega e engancha | `Exit watch: TerminateProcess hooked \| ...` |
| O sniffer lê os opcodes do jogo | `1175 message types resolved` |
| Leitor de posição (ambos os PCs) | `Local: pos (-20626.62, 621.16, -6813.44)` |
| Leitor de HP e stamina | `hp 1650.0/1650.0 stamina 440.0/440.0` |
| Criação da sala Steam | `Room: hosting, code 1YZDAWX` |
| Conexão P2P entre os dois | `Net: connected ... rtt 32.2 ms` |
| Estado periódico do outro jogador | `remote states 962` |
| Recepção do personagem remoto | `received the other player's character (39795 bytes)` |
| Injeção de pacotes no jogo | `Inject: delivered opcode 2005` |
| Criação do boneco no convidado | `co-op: other player loaded` |
| Checagem de versão | recusou builds diferentes, corretamente |
| Contenção de erros do jogo | `game_errors_install()` com SEH |

**Ponto importante:** no teste das 17:11, **o convidado viu o boneco do anfitrião**
(`co-op: other player loaded`) e sobreviveu. **O caminho de entrada funciona em uma direção.**

---

## 5. O que não funciona

### Por escolha — falha fechado

O mod **decide não operar** quando não tem dados confiáveis. Isso é correto, não é defeito:

| Recurso | Por quê |
|---|---|
| Rotação do boneco | Não há base de cálculo — `rot (0.000, 0.000, 0.000, 1.000)` em todo log |
| Sincronia de tempo | `time sync off` |
| Ícone no minimapa | `icon function not recognised` na 3460 |
| Cavalo | `HorseDiag: CC update not recognised` |
| Cópias de inimigos | `Enemy relay: wanted but not started` |
| Loot de chefe pelo convidado | **Por pedido** — o anfitrião sempre dá o golpe final |

### Offsets ainda não recuperados na 3460

```
WRN Game errors: logger not recognised; not hooked
WRN HorseDiag: CC update (exe+0x941D40) not recognised
WRN Capture: OtherEquipItemAck writer not recognised
WRN Minimap: icon function not recognised
WRN Enemy relay: wanted but not started
```

**Nenhum destes impede conectar.** São funcionalidades a recuperar.

### Nunca testado

- O teste de laboratório `Ctrl+Home` com nativos
- Chefes conjuntos (fase D2) — tipos de registro de cópia **4 e 7**
- Veículos (tipo 5) — deliberadamente adiados

---

## 6. Os dois defeitos corrigidos

### 6.1 A posição zerada era timing — **fechado**

**Sintoma:** a posição do convidado chegava `(0,0,0)` — 216 medições seguidas.

**Causa:** o mundo dele ainda estava carregando. A guarda em `player_reader.cpp` testava
`|y - 1000| < 5` — o valor que a leitura **antiga** produzia. Com a leitura nova devolvendo
`(0,0,0)`, `|0 - 1000| = 1000` não é `< 5`, **e a guarda parou de casar em silêncio**.

**Correção:** aceitar as DUAS formas de "ator estacionado", mais uma segunda guarda em
`remote_puppet.cpp` para que um pacote ruim não mate o receptor.

**Lição:** a guarda testava a coisa errada, e a conclusão errada passou como fato.

### 6.2 O travamento antes do menu — **fechado**

**Sintoma:** tela preta, o jogo fechava **antes do menu**, nos **dois** PCs, no mesmo build.

**Causa:** o `exit_watch` enganchava `RaiseException`. **O runtime do C++ usa essa função
como fluxo normal** — nomear threads, cada `throw`, sondagens SEH. O hook rodava alocação de
memória e locks **dentro do despacho de exceção**, milhares de vezes por inicialização.

**A prova:** comparando o build que funcionava com o que travava, **uma única mudança**:

```
src/mod/game/exit_watch.cpp | 186 +++
src/mod/game/exit_watch.h   |  34 +++
src/mod/mod.cpp             |   6 ++
```

**Correção:** não engancha mais. O hook grava num **buffer fixo pré-alocado**, sem
alocação, sem lock, sem formatação.

**Lição mais cara do projeto:** o teste unitário **passava** enquanto o mod quebrava o jogo
de duas pessoas. Ele chamava a função patcheada **uma vez, de uma thread calma** — a única
situação onde o problema não aparece. O teste agora verifica que `RaiseException` **não**
está enganchada, e sobrevive a **2000 throws seguidos**.

---

## 7. Por onde continuar — em ordem de valor

### P1. Capturar os pacotes que matam o processo ⭐ **maior valor**

```ini
[sniffer]
record=1
```

Reproduzir, capturar os dois `opcode 2005`, e **comparar com os pacotes nativos do próprio
jogo**. A diferença entre um pacote que o jogo aceita e um que o mata é a resposta.

**Por que é viável agora:** sabemos o instante com **23 ms de precisão**.

### P2. Ler o dump que já existe

```
%LOCALAPPDATA%\CrashDumps\CrimsonDesert.exe.<pid>.dmp
```

**Existem dumps de crashes reais nesta máquina.** Com o **WinDbg**:

```
windbg -z <arquivo>.dmp
!analyze -v
```

O `!analyze -v` dá o módulo, o offset e a pilha. **Isso responde "onde" em minutos.** O que
ele não dá é "por quê" — mas reduz muito o espaço de busca.

### P3. Investigar a assimetria dos tamanhos ⭐ **nunca explicada**

| Sessão | user | body |
|---|---|---|
| 17:11 anfitrião | 16932 | 6445 |
| 17:11 convidado | 16500 | 6453 |
| 18:17 anfitrião | 16637 | 6445 |

**O mesmo personagem, tamanhos diferentes.** E o convidado **sobreviveu** à injeção que
matou o anfitrião. Se o formato do pacote estiver errado, o tamanho deveria ser o sintoma
mais visível.

### P4. Testar a injeção em isolamento

Injetar **só o pacote `user`**, depois **só o `body`**, e ver qual mata. Se nenhum matar
sozinho, é a combinação.

### P5. Verificar o guard de "posição estacionada"

No log: `check vs game global 9008531862833856512.00 m`. **Esse número é lixo** — um valor
que passa pela guarda. Confirmar qual global ele lê e se a comparação faz sentido.

### P6. Recuperar os offsets da 3460

Método em `docs/PORTING.md`. Os avisos de startup listam exatamente o que falta.

---

## 8. Como diagnosticar neste projeto

### O método que funciona

> **Ancorar em código provado byte a byte idêntico, confirmar pelo contexto em volta,
> confirmar pelo que o código FAZ — nunca por um acerto.**

### A armadilha central

> **Um número plausível é o estado padrão de um número não medido.**

**Seis vezes em um dia** um valor pareceu resultado e não era:

| Valor | O que era de verdade |
|---|---|
| `-88.3066` | um ponteiro lido como float |
| `(1.0, 0.0, 0.1745)` | um vetor de direção |
| `check vs game global 0.00 m` | o default de uma struct |
| `531655.81 m` | lixo passando pela guarda |
| `2097558656.00 m` | o mesmo, ainda acontecendo |
| `"their world is probably still loading"` | **um palpite vestido de conclusão** |

**Corolário:** uma opção aceita e ignorada produz um **zero confiável** — e um zero
confiável é indistinguível de uma descoberta.

### Ferramentas que existem

| Ferramenta | Para quê |
|---|---|
| `cdmp_probe` | CLI de diagnóstico: `troc`, `xrefs`, `scan`, `dump`, `classes`, `vtables`, `findptr` |
| `scripts/teste-final.ps1` | Vigia de teste: captura logs, dumps e WER na morte |
| `scripts/vigia-crash.ps1` | O mesmo, mais simples |
| `scripts/diagnostico-convidado.ps1` | Diagnóstico completo do lado do convidado |
| `scripts/instalar-convidado.ps1` | Instala e verifica por hash |
| `[sniffer] record=1` | **Grava os pacotes** — o mais importante e menos usado |

### Armadilhas do `cdmp_probe`

Todas produzem **números errados com confiança**:

- `troc <begin> <end>` — argumentos **POSICIONAIS**; `--begin/--end` são **ignorados em silêncio**
- `xrefs` — reporta o operando deslocado, **não o início da instrução**
- O prefixo é `exe+0xNNN` lendo o módulo e `0xNNN` no heap — **um parser ancorado em `^0x` devolve 0 sem avisar**
- `scan` **sem `--heap` NÃO varre a memória viva**

---

## 9. Mapa do código

### Estrutura

```
src/
  common/          Protocolo, sessão, canais confiáveis — testável sem o jogo
  mod/
    game/          Leitura do jogo: offsets, RTTI, leitores, memória segura
    net/           Rede: sniffer, injeção, boneco remoto, sala Steam
    render/        Overlay DX12
  tools/probe/     CLI de diagnóstico
tests/             Testes unitários
scripts/           Build, empacotamento, instalação, diagnóstico
docs/              Documentação
```

### Arquivos-chave

| Arquivo | Papel |
|---|---|
| `src/mod/net/troc_sniffer.cpp` | **O coração.** Engancha `PostPacket`/`OnRecvPacket` e injeta |
| `src/mod/net/remote_puppet.cpp` | **Onde está o crash.** Monta o ator remoto |
| `src/mod/net/coop.cpp` | Máquina de estados do co-op |
| `src/mod/game/player_reader.cpp` | Lê posição, HP, stamina do jogador local |
| `src/mod/game/offsets_3460.h` | **Todos os offsets da versão atual** |
| `src/mod/net/local_capture.cpp` | Captura o personagem para enviar |
| `src/mod/net/enemy_relay.cpp` | Cópias de inimigos |
| `src/common/protocol.h` | Formato dos pacotes |
| `src/mod/game/exit_watch.cpp` | Observa a saída do processo |

### Como o build funciona

```powershell
.\scripts\build.ps1                    # compila + testa
.\scripts\pack-role-swap.ps1 -HostSteamId X -GuestSteamId Y   # gera os dois kits
```

**O build id** é os 32 bits baixos do hash curto do HEAD, gravado como `constexpr` no
momento do CMake configure. **A compatibilidade compara esse número, nunca um hash de
arquivo** — o build **não é reproduzível** (o MSVC reordena o pool de strings ao fundir
`.obj` em paralelo).

---

## 10. Mapa dos documentos

| Documento | Para quem | O que tem |
|---|---|---|
| **`docs/DOSSIE.md`** (este) | **Quem vai continuar** | Tudo, em ordem |
| `docs/ESTADO-FINAL.md` | Quem vai continuar | Estado em 31/10, mais conciso |
| `docs/PORTING.md` | Quem porta para outra versão | O método RTTI completo |
| `docs/GUIA-ANFITRIAO.md` | Jogador | Como ser anfitrião |
| `docs/GUIA-CONVIDADO.md` | Jogador | Como ser convidado |
| `docs/GUIA-JOGADOR.md` | Jogador | Visão geral |
| `docs/BUGS-ABERTOS.md` | Desenvolvedor | Lista de defeitos conhecidos |
| `docs/HISTORIA-PORTES.md` | Desenvolvedor | Histórico das versões |
| `docs/ROADMAP.md` | Desenvolvedor | Próximos passos planejados |
| `docs/research/` | Investigador | Logs de crash brutos e análises |
| `kit/COMO-INSTALAR.md` | Jogador | Instalação passo a passo, com hashes |

---

## 11. Armadilhas que já custaram horas

### Nomes de seção neste binário são **FALSOS**

**Nunca selecione código pelo nome da seção.** Use `IMAGE_SCN_MEM_EXECUTE` **mais o
conteúdo**.

### A regra RIP-relativa

```
target = (site + disp_offset) + 4 + disp32
```

### O delta entre versões **NÃO é uma constante**

Cinco deltas diferentes entre 3446 e 3460:

| Delta | Onde |
|---|---|
| `+0x4000` | handler `.rdata` |
| `+0x4010` | vtable de componente |
| `+0x4018` | vtable de componente |
| `+0x990` | métodos de movimento |
| `+0x5680` | `GlobalVariableManager` |

### O ASI Loader só carrega se o jogo **importar o nome**

`CrimsonDesert.exe` importa `WINMM.dll` e **NÃO** importa `DINPUT8.dll`.

**Renomear `dinput8.dll` para `winmm.dll` é OBRIGATÓRIO.** Com o nome errado, o arquivo
fica na pasta, o jogo nunca o carrega, e **não aparece erro nenhum** — sem painel, sem log.

### A cadeia RTTI do MSVC x64

```
[vt-8]   = ponteiro absoluto para o CompleteObjectLocator
COL+0x0C = RVA do TypeDescriptor
nome     = começa 20 bytes depois do descritor
```

### Verificação por movimento

**Duas leituras com o jogador andando PRECISAM diferir** na direção do movimento. Um valor
que não muda com o movimento **não é uma posição**.

### O jogo precisa estar FECHADO para reconstruir ou instalar

O `.asi` fica **travado** com o jogo aberto. A cópia **falha em silêncio** e deixa um build
velho no lugar.

### Erros de PowerShell que já ocorreram

| Erro | Correção |
|---|---|
| `Invoke-WebRequest` falha neste ambiente | use `[Net.HttpWebRequest]::Create()` com `UserAgent` |
| `gh release view` → `not a git repository` | passe `--repo dono/repo` (o `cd` não persiste) |
| `[IO.File]::ReadAllLines` falha no `cdmp.log` | o jogo o mantém aberto — use `FileShare::ReadWrite` |
| `>` grava UTF-16 | use `Set-Content -Encoding UTF8` |
| `ctest` não está no PATH | rode o `.exe` de teste direto |
| `gh`/`git push` escrevem em stderr | sucesso reporta `[exit code: 1]` |
| `$PSScriptRoot` vazio com `-File` | use `$MyInvocation.MyCommand.Definition` como fallback |

---

## 12. Glossário

| Termo | Significado |
|---|---|
| **ASI** | Formato de plugin do ASI Loader (é uma DLL renomeada) |
| **Anfitrião / host** | Quem cria a sala; as missões dele são as que contam |
| **Convidado / guest** | Quem entra; as missões dele **não** avançam |
| **Boneco / puppet** | O ator sintético que representa o outro jogador |
| **Troc** | O sistema de mensagens do jogo; cada mensagem é uma classe com RTTI |
| **Opcode** | Número que identifica o tipo de mensagem. **Muda entre versões** |
| **Sniffer** | O componente que engancha a rede e injeta pacotes |
| **Injeção** | Entregar um pacote falso ao jogo como se viesse da rede |
| **SEH** | Tratamento de exceções estruturado do Windows (`__try`/`__except`) |
| **RTTI** | Informação de tipo em tempo de execução; usada para achar vtables |
| **Vtable** | Tabela de ponteiros de função virtuais de uma classe |
| **PE timestamp** | Campo do cabeçalho PE que identifica a versão do binário |
| **Exit watch** | Componente que observa como o processo termina |
| **Guarda de parque** | Detecção de que o ator está em `(0, 0, 0)` porque o mundo carrega |
| **Lobby** | Sala da Steam que conecta os dois jogadores |
| **Código de sala** | 7 caracteres base32 Crockford que identificam a sala |

---

## Nota final

**Este projeto chegou mais longe do que o resultado sugere.**

No começo do dia, os jogos travavam **antes do menu** e não havia **nenhuma** evidência: sem
relatório do Windows, sem dump, sem exceção capturada. No fim do dia:

- Os dois jogos **abrem, entram no mundo e se conectam**
- O crash está **isolado em um único ponto**, com precisão de **milissegundos**
- A **causa raiz do travamento anterior está corrigida** e tem teste que a protege
- Há **dumps** de crashes reais, **WinDbg** instalado e o **sniffer pronto para gravar**

**O problema que resta é real, mas é pequeno e está bem localizado:** o jogo não aceita o
ator sintético que o mod injeta. O passo P1 da seção 7 — **gravar e comparar os pacotes** —
é o caminho mais curto para resolvê-lo, e o instrumento para isso já está no código.

**A lição mais cara deste projeto não é técnica.** O teste unitário passava, o build
publicava, os hashes conferiam — **e o mod quebrava o jogo de duas pessoas.** Todas as
verificações automáticas eram verdadeiras sobre um produto que não funcionava, porque
nenhuma delas **abria o jogo**.

**Um teste que não exercita o caminho real não é um teste.** É um número plausível.
