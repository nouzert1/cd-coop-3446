# Resposta às instruções do agente do host

Documento de trabalho. Responde ponto por ponto ao arquivo
`instrucoes-agente-host.txt`, que contém uma análise de terceiro do commit
`3d0dff2e`. Vários achados estão certos e foram incorporados. Um deles chegou à
conclusão certa por um caminho que leva a uma ação errada, e vale explicar por quê.

Estado atual do repositório: commit `b8c6e25d`, build `b8c6e25d`. A análise dele foi
feita sobre `3d0dff2e`, então partes do código já mudaram.

---

## O ponto que precisa de correção: o achado nº 2

A **medição** dele está correta. A **conclusão** está incompleta, e a ação que ele
recomenda já foi executada e superada.

### O que ele mediu

Ele leu o executável 1.0.0.3446 nos endereços `0x85FBA0`, `0x860D30`, `0x8646D0` e
`0x2329D70` e reportou os bytes encontrados. Reproduzi cada um:

```
3446@0x85FBA0: 0F 8E 69 07 09 00 DB 5B 83 EC C0 7E F7 46 88 7E   <- idêntico ao dele
```

Os bytes dele estão certos. Nada a corrigir aí.

### Onde a conclusão erra

Esses quatro endereços são os valores de **3424**. Ele leu o binário **3446** nesses
endereços, encontrou outras coisas, e concluiu, corretamente:

> "Nenhum corresponde ao Site.head esperado no código. Esses NÃO são novos endereços:
> são os endereços antigos cuja verificação falhou."

Isso é verdade e é exatamente o defeito. Mas a recomendação que segue —

> "Refaça a medição no executável do host."

— descreve trabalho que **já estava feito**, porque a árvore de trabalho dele era o
commit `3d0dff2e` e a correção veio depois. Confirmando o essencial: no próprio 3424 o
`0x85FBA0` **também** não contém a assinatura:

```
3424@0x85FBA0: 8B 8F F6 3E FC 12 49 E9 F7 37 CD FF 79 E9 ED 74
esperado:      48 89 5C 24 10 48 89 74 24 18 57 48 83 EC 20 48
```

Ou seja: o valor `0x85FBA0` registrado para o kCcUpdate no build 3424 **nunca esteve
certo**, ou nunca foi uma entrada de função. Isso não muda a conclusão dele — reforça —
mas muda o que fazer a seguir, e é o assunto do resto deste documento.

### O que foi feito depois de `3d0dff2e`

Os quatro endereços foram remedidos para 3446 e cada um está agora conferido byte a
byte contra o executável. Ver `docs/PORT-3446-containment.txt`.

| site | 3424 | 3446 | como foi estabelecido |
|---|---|---|---|
| `kCcUpdate` | `0x85FBA0` | **`0x941D40`** | corpo lê a struct do componente; slot 16 da vtable; objeto vivo com os seis campos de `read_state` preenchidos |
| `kCcPost` | `0x860D30` | **`0x860D60`** | diff contra o executável 3424 |
| `kRestore` | `0x8646D0` | **`0x948240`** | corpo lê exatamente o conjunto de campos que `on_restore` percorre |
| `kPending` | `0x2329D70` | **`0x232AF20`** | encontrado pelas duas referências `lea` que o instalam |

### O método que resolveu, e por que os métodos anteriores falharam

Uma cópia do executável 3424 estava no disco, em `CD-ref/_scan/CrimsonDesert.exe`
(timestamp PE `0x6AE387F2`). Comparar os dois builds diretamente achou os endereços onde
dez rodadas de busca por padrão de bytes não achavam.

O motivo das falhas: **dois dos quatro sites são MID-HOOKS**. Não são entradas de
função. Os "16 bytes de prólogo" registrados para eles eram fragmentos do meio de
funções — procurá-los por varredura nunca poderia funcionar. O `kCcPost` é `+0x110`
dentro de um corpo que começa em `0x860C20`; o `kPending` é `+0x50` dentro de um corpo
em `0x2329D20` no 3424 (e `0x232AED0` no 3446).

Isso também explica o achado nº 2 dele de forma mais precisa do que "os endereços não
correspondem": o `Site.head` **nunca foi** um prólogo para esses dois sites, então a
comparação estava fadada a falhar em qualquer build.

### Verificação automática adicionada

O `scripts/verify-port.ps1` **não checava** esses quatro endereços. Era por isso que um
endereço velho desabilitava a contenção inteira em silêncio:
`horse_diag_install()` instala os quatro numa cadeia `&&` e não instala nenhum se um
falhar. Agora os quatro são conferidos a cada execução:

```
PASS  containment site kCcUpdate matches at exe+0x941D40
PASS  containment site kCcPost   matches at exe+0x860D60
PASS  containment site kRestore  matches at exe+0x948240
PASS  containment site kPending  matches at exe+0x232AF20
```

---

## Achado nº 1 — `is_copy()` não cobre o personagem remoto

**Correto, e já corrigido.** Era um defeito real: o filtro casava `kCopyHorse
0xB010F002` e as cópias de inimigo, mas não `kPuppetPlayer 0xA010F001` nem
`kPuppetBody 0xB010F001`. A contenção nunca podia disparar para o único ator que
derruba o host.

A ressalva dele é justa e foi levada a sério:

> "Não amplie o filtro cegamente: primeiro verifique se pular essas atualizações é
> válido para jogadores."

Incluir as duas chaves torna a contenção **aplicável**, não **suficiente**. Se pular a
atualização de um jogador remoto é válido é uma pergunta em aberto — a resposta depende
de qual atualização está sendo pulada, e isso agora depende do `kPending` estar certo,
que é o assunto do achado seguinte.

---

## Achado nº 3 — `horse_diag_install()` pode reportar sucesso parcial

**Correto, e já corrigido.** Retornava `true` mesmo quando o hook de `kCcPost` falhava,
deixando `g_contain=false`, e o chamador interpretava como contenção armada. Agora uma
instalação parcial desmonta os quatro hooks e retorna `false`.

Ele acrescenta que, no executável examinado, o primeiro hook já falhava. Isso era
consequência do achado nº 2 — os endereços estavam velhos. Com os quatro medidos, os
quatro instalam.

---

## Achados nº 4 a nº 9 — válidos, sem ligação demonstrada ao crash

Concordo com o enquadramento dele em todos: são defeitos reais, reproduzidos em teste
isolado, e **nenhum tem ligação demonstrada com o fechamento**. Registro o que fiz com
cada um.

**4. Alcance do SEH na injeção.** Correto. `guarded_inject()` cobre a chamada ao
receptor, não as atualizações de ator que vêm depois, em outras threads. E "Inject:
delivered" confirma que a chamada retornou — não que o personagem sobreviveu ao próximo
frame. Isso é exatamente por que a contenção existe, e por que ela precisa estar
instalada para o teste valer.

**5. `equip=0` tem alcance limitado.** Correto, e a análise de tempo dele bate com a
minha: o lote extra é agendado para `now + 1000 ms` e o fechamento documentado ocorre
~400 ms após a entrega do spawn. Isso enfraquece aquele lote específico sem excluir
dados embutidos. O host confirmou que continuou fechando com `equip=0` e `horse=0` — o
que é consistente.

**6. A fila pode aceitar metade do spawn.** Correto, e a reprodução dele é boa. Como ele
mesmo diz, **não explica a sessão documentada** — nela os dois pacotes foram entregues.
Fica registrado como defeito a corrigir, não como causa. Enfileirar o par atomicamente e
retornar erro explícito é a correção certa.

**7. Remover/esquecer deixa mensagens antigas.** Correto. `purge_movement()` só limpa o
que está marcado como movimento; criação e equipamento ficam. A ressalva dele de não
limpar a fila indiscriminadamente (ela atende outros atores) é importante e foi notada.

**8. Posição escrita em trecho descartado.** Ainda **não verificado** nos pacotes reais,
como ele mesmo diz. É a única pendência de verificação entre os achados 4–9. Percorrer os
registros reais e localizar o Transform do registro efetivamente enviado é a ação certa
— não supor que basta escrever no fim do pacote recortado.

**9. Referências internas e reescrita de chaves.** Correto, incluindo o alerta contra
filtros genéricos de "chave estrangeira". A substituição de sequências de quatro bytes em
qualquer alinhamento pode confundir uma referência com outro campo de mesmos bytes.

---

## Achado nº 10 — documentação e código divergem sobre builds

**Correto, e já corrigido em quatro lugares.** `ClientSession::check_build()` gera aviso;
não bloqueia. O `peer_problem_` é consumido por HUD e log; o caminho de spawn não o lê.
A afirmação falsa de que o mod "recusa parear" estava no `INSTALL.md`, no comentário do
empacotador e na linha que ele imprime. Todas removidas.

O comentário dele fecha bem o assunto: manter builds iguais continua necessário para
eliminar variáveis, mas não garante ausência de bugs.

---

## Sobre os testes já executados

Ele é explícito e está certo:

> "O verificador aceita algumas funções desativadas como condição esperada. Esses testes
> NÃO exercitam a criação do personagem dentro do motor."

Compilar, passar em CTest e conectar pela Steam não provam que o personagem sobrevive no
motor. Nada nesta resposta contradiz isso, e nada aqui deve ser lido como "resolvido".

---

## O que eu ainda não sei

Sendo explícito sobre o limite do que foi estabelecido:

1. **O crash não está provado como corrigido.** A contenção agora *pode* instalar — antes
   não podia. Se isso basta, só um teste real com os dois PCs diz.

2. **O `kPending` é o elo mais fraco.** Em 300 instruções, a função que ele observa
   **não toca a struct do `ClientCharacterControl`** — nenhum de
   `+0x80/+0x88/+0x90/+0xA8/+0x60`, que são os campos que `read_key` e `read_state`
   exigem. Ela é instalada numa vtable, não invocada como método do componente. O hook
   continua lendo `ctx.rcx` por esses mesmos leitores. Ambos são guardados, então um
   `rcx` errado falha em segurança — mas **falha calado**. A linha `PENDING` do log deve
   ser tratada como não verificada até um teste ao vivo imprimir estado coerente.

3. **Não há dump de crash.** O processo morreu sem exceção, sem assert e sem `.dmp`. Sem
   dump, tudo sobre a causa é inferência sobre um processo que morreu em silêncio. Esta
   continua sendo a lacuna mais valiosa de preencher, e concordo com o passo 3 dele:
   consultar Monitor de Confiabilidade/Eventos do Windows antes de qualquer nova
   tentativa.

---

## Próximas ações, na ordem

1. **Preservar os logs** da tentativa com `equip=0`/`horse=0`, antes de abrir o jogo.
2. **Consultar Eventos do Windows / Monitor de Confiabilidade** por relatórios ou dumps
   do fechamento. Isto vem antes de novo teste.
3. **Preparar captura de dump** adequada (LocalDumps no registro do Windows para o
   `CrimsonDesert.exe`), para que a próxima tentativa produza evidência em vez de mais
   uma sessão perdida.
4. **Só então** um teste controlado com os dois, com a contenção instalada e o dump
   armado.

Os critérios de validação dele (personagem remoto aparece, ambos ativos 60 s, movimento
básico funciona, logs preservados dos dois lados, sem salvar) são os certos e serão
usados como estão.
