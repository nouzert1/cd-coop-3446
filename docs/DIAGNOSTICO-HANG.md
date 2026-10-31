# O host não está travando por exceção — ele está TRAVANDO (hang)

Achado de 30/10/2026. É a descoberta mais consequente da investigação, e ela veio de
um lugar inesperado: da **ausência** de um arquivo.

## O que foi encontrado

A configuração `LocalDumps` do Windows nesta máquina já existe, e o diretório de dumps
**funciona** — contém dumps de vários outros programas:

```
cs2.exe.22964.dmp                  35 KB
mspaint.exe.9232.dmp               42 MB
powershell.exe.21272.dmp           30 MB
SkyrimTogether.exe.24268.dmp     1,22 GB
steam.exe.3200.dmp                 18 MB
```

**Não há nenhum dump do `CrimsonDesert.exe`.** E, consultando o Log de Eventos do
Windows, aparece exatamente um registro para ele:

```
Nome do Evento: AppHangTransient
P1: CrimsonDesert.exe
P2: 1.0.0.3446
P3: 6ae46dd0          <- o timestamp PE da build que estavamos depurando
P4..P7: unknown
ID do Relatório: 887bf76c-ca57-45b0-8f1e-9ce58cf429af
```

`AppHangTransient` significa que **a janela parou de responder** e o Windows encerrou o
processo. Não é uma exceção não tratada.

## Por que isso importa mais do que parece

O evento explica, de uma vez, cada sintoma que vinha sendo tratado como mistério
separado:

| sintoma observado | explicação |
|---|---|
| fecha ~0,4 s depois da entrada do personagem | um watchdog encerra o processo após o travamento |
| **nenhuma exceção no log** | não houve exceção para registrar |
| **nenhum `.dmp` de crash** | travamento não gera dump de crash — o WER geraria se fosse exceção |
| nenhum assert disparado | nenhum assert foi atingido |
| só o host cai, o convidado continua | o travamento está no caminho de execução do host |
| `Inject: delivered` aparece no log | a chamada de injeção retornou; o que trava vem **depois** dela |

Vale sublinhar o raciocínio que leva ao diagnóstico: o WER **está funcionando** nesta
máquina e **gera dump para outros jogos**. Se o fechamento do host fosse uma exceção não
tratada, haveria um `.dmp` do CrimsonDesert. Não haver. Somado ao
`AppHangTransient`, a leitura mais provável é que o motor (ou um watchdog próprio)
detecta o frame travado e chama `ExitProcess`/`TerminateProcess` — uma saída **limpa**,
do ponto de vista do sistema operacional.

## O que isso muda na investigação

### 1. A contenção é a defesa certa — e antes ela não existia

A contenção do `horse_diag.cpp` pula a atualização de ação/animação quando a camada não
tem ação válida — que é exatamente o tipo de laço/estado inconsistente capaz de travar um
frame. Até esta rodada, **ela não instalava**: os quatro endereços estavam velhos e
`horse_diag_install()` desmontava tudo em silêncio. Ou seja, o travamento acontecia com a
defesa ausente, em toda tentativa.

Isso não prova que a contenção corrige o travamento. Prova que ela nunca foi testada de
verdade.

### 2. A prioridade de busca muda

Procurar um *crash handler* deixa de ser o alvo principal. O alvo passa a ser o
**watchdog**: o código que percebe o frame parado e decide encerrar. Duas frentes:

* localizar o watchdog no executável (procura por chamadas a `ExitProcess`,
  `TerminateProcess`, `FatalExit` ou equivalentes, que não sejam caminho normal de saída);
* descobrir **onde o frame travou**, que é a pergunta original — o watchdog só explica a
  saída, não a causa.

### 3. Como capturar evidência da próxima vez

Um dump de *hang* é diferente de um dump de *crash*, e é obtido de outra forma:

* **dump manual durante o travamento** — enquanto o processo ainda está vivo e travado,
  capturar com o Gerenciador de Tarefas (botão direito → Criar arquivo de despejo) ou
  `procdump -ma -h` (o `-h` dispara em hang, não em exceção). Isto é o mais direto: o
  processo precisa estar **vivo e travado**, o que dá uma janela de vários segundos;
* **`LocalDumps` com `DumpType=2`** (dump completo) e uma subchave para
  `CrimsonDesert.exe`, para o caso de o WER capturar;
* observar se a janela realmente congela antes de fechar — se congelar, o `procdump -h`
  pega o processo no ato.

O ponto prático: **o travamento oferece uma janela que o crash não oferecia.** Um crash
mata o processo instantaneamente; um hang deixa o processo parado e residente por
segundos. É possível capturá-lo.

## O que continua não provado

* Que a contenção corrige o travamento. Ela agora instala; se basta, só um teste real diz.
* Onde o frame trava. O `AppHangTransient` diz que travou, não onde.
* Se o `kPending` observa o que se pensa — ver `docs/PORT-3446-containment.txt`.
* O evento é de **30/10 15:45**, e a sessão documentada no `INVESTIGATION.md` foi por
  volta de 20:49. São registros diferentes; o evento confirma o **mecanismo**, não
  necessariamente aquela sessão específica. Vale procurar se há mais eventos em outras
  datas antes de tratar este como o único.

## Verificação final: três eventos, todos de travamento

Depois de escrito o texto acima, a busca foi refeita para cobrir 30 dias inteiros em vez
de uma amostra:

```
29/10/2026 20:08:37   1001   Windows Error Reporting   AppHangTransient
29/10/2026 20:08:55   1001   Windows Error Reporting   AppHangTransient
30/10/2026 15:45:09   1001   Windows Error Reporting   AppHangTransient
```

**Três eventos. Todos `AppHangTransient`. Nenhum `APPCRASH` (Id 1000).**

Isso fecha a questão do mecanismo. Um jogo que morre por exceção não tratada produz o
evento Id 1000 e um dump; um que trava e é encerrado produz Id 1001 `AppHangTransient` e
nenhum dump. Só o segundo caso aparece aqui, três vezes. E confirma o raciocínio por
ausência: o WER está funcional nesta máquina — há dumps de `cs2.exe`, `SkyrimTogether`,
`mspaint`, `powershell`, `steam` — e nenhum do `CrimsonDesert`.

Os dois eventos de 29/10 separados por 18 segundos sugerem duas tentativas na mesma
sessão, ou uma tentativa que travou, foi encerrada e travou de novo.

Não há relatório arquivado do WER para o jogo (`ReportArchive` / `ReportQueue` contêm
apenas entradas de outros programas), então a pilha do travamento não foi preservada.

### O que fazer com isso

O travamento **deixa o processo vivo e parado por vários segundos** — é uma janela de
captura que um crash não oferece. É possível obter a pilha do local exato onde o frame
parou, que é a pergunta central e continua em aberto:

```
procdump -ma -h -e 1 CrimsonDesert.exe cdmp-hang.dmp
```

O `-h` dispara em travamento (não em exceção), e `-e 1` captura também exceções de
primeira chance. Como alternativa manual, com o jogo já travado na tela:
Gerenciador de Tarefas → botão direito no processo → *Criar arquivo de despejo*.

Nenhuma dessas opções exige admin para o dump em si, mas armazenar via `LocalDumps`
(que é o que daria captura automática) exige escrever em `HKLM` e portanto admin.
