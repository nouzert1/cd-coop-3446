# docs/ — índice

**Se você está começando, não leia esta pasta em ordem.** Os arquivos aqui foram escritos ao longo
de meses e vários são registros de investigação cujas conclusões já foram superadas.

Comece por:

| Documento | Para quê |
|---|---|
| [GUIA-JOGADOR.md](GUIA-JOGADOR.md) | **Jogar.** Instalar, testar, o que não funciona |
| [PORTING.md](PORTING.md) | **Portar para um build novo.** O método que funcionou |
| [BUGS-ABERTOS.md](BUGS-ABERTOS.md) | **Todo problema aberto**, ordenado por valor por hora |
| [HISTORIA-PORTES.md](HISTORIA-PORTES.md) | O que quebrou em cada atualização |

---

## Nível 1 — Atuais, mantidos

Estes descrevem o estado **de agora** e são atualizados junto com o código.

| Arquivo | Conteúdo |
|---|---|
| [GUIA-JOGADOR.md](GUIA-JOGADOR.md) | Guia do jogador, em português |
| [PORTING.md](PORTING.md) | Como portar; as armadilhas da ferramenta |
| [BUGS-ABERTOS.md](BUGS-ABERTOS.md) | Problemas abertos + sugestões para contribuidores |
| [HISTORIA-PORTES.md](HISTORIA-PORTES.md) | Histórico dos ports, com os deltas medidos |
| [ROADMAP.md](ROADMAP.md) | Como cada recurso foi construído, milestone por milestone |
| [TESTE-2-PCS-2026-10-31.md](TESTE-2-PCS-2026-10-31.md) | Roteiro do teste de dois PCs |
| [research/globais-3460.md](research/globais-3460.md) | Os 4 globais medidos no 3460, com o que quebra |
| [research/porte-3460.md](research/porte-3460.md) | O port 3446 → 3460, com as linhas de log cruas |
| [research/validacao-3460.md](research/validacao-3460.md) | As medições ao vivo: o que passou, o que falhou |

---

## Nível 2 — Planos e análises

Documentos de trabalho sobre problemas específicos. Ainda úteis, mas alguns descrevem planos que
mudaram de forma.

| Arquivo | Conteúdo |
|---|---|
| [PLAN-PENDIENTES.md](PLAN-PENDIENTES.md) | Plano dos pendentes (espanhol) |
| [JEFES-POR-QUE-NAO-FECHA.md](JEFES-POR-QUE-NAO-FECHA.md) | Por que chefes conjuntos não fecham |
| [RELEVO-INIMIGOS-NUNCA-LIGOU.md](RELEVO-INIMIGOS-NUNCA-LIGOU.md) | Por que o revezamento de inimigos nunca ligou |
| [DIAGNOSTICO-HANG.md](DIAGNOSTICO-HANG.md) | Diagnóstico do travamento (causa ainda desconhecida) |
| [INFORME-CABALLO-CRASH.md](INFORME-CABALLO-CRASH.md) | O crash do cavalo |
| [PRUEBA-DOS-PC.md](PRUEBA-DOS-PC.md) | Plano de teste de dois PCs (espanhol) |
| [PRUEBAS-COOP.md](PRUEBAS-COOP.md) | Testes de co-op (espanhol) |
| [CAMPO-HORA-NAO-EXERCITADO.md](CAMPO-HORA-NAO-EXERCITADO.md) | O campo de hora do jogo, não exercitado |
| [ANALISIS-CrimsonDesertCoop.md](ANALISIS-CrimsonDesertCoop.md) | Análise de outra tentativa de co-op (sem licença — **não copiar código**) |
| [RESPOSTA-AGENTE-HOST.md](RESPOSTA-AGENTE-HOST.md), [RESPOSTA-AO-RELATORIO-EXTERNO.md](RESPOSTA-AO-RELATORIO-EXTERNO.md) | Respostas a relatórios externos |

---

## Nível 3 — `research/` — registros datados

`docs/research/` tem ~70 notas, a maioria em espanhol, escritas durante a investigação. O índice
próprio está em [research/README.md](research/README.md).

**Cuidado ao usá-las:** são logs de investigação, não documentação. Uma nota pode registrar uma
conclusão que foi **depois derrubada** — por exemplo, um valor que "parecia" uma posição e era um
ponteiro. Várias contêm endereços do 3446 ou do 3424 que já não são válidos.

As três que valem ler primeiro estão no Nível 1 acima.

---

## Transcrições de port

`PORT-3424-probe.txt`, `PORT-3446-live.txt`, `PORT-3446-containment.txt` — saídas cruas das
ferramentas durante os ports. Úteis para ver **como** um endereço foi medido, não para copiar o
endereço.
