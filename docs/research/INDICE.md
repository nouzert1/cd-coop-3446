# Índice da pesquisa

Esta pasta tem **mais de 80 arquivos**, escritos ao longo de meses, em **espanhol e
português**. Sem um índice, é impenetrável.

**Este arquivo é o índice.**

---

## Leia primeiro

Se você chegou aqui para continuar o projeto, **não comece por esta pasta**. Comece por
[`../DOSSIE.md`](../DOSSIE.md). Volte aqui quando precisar do detalhe de um assunto
específico.

---

## 1. O teste final de 31/10/2026 — comece por aqui

O material mais recente e mais importante. **É o estado real do projeto.**

| Arquivo | O que é |
|---|---|
| **`analise-final-spawn-crash.md`** | **A análise do crash final.** Isola a morte a 23 ms, com a sequência completa de linhas. Escrito pelo jogador que atuou como anfitrião |
| **`crash-final-2026-10-31-1817-host.log`** | **O log integral da sessão que morreu.** 35 KB. Termina nas duas linhas de injeção |
| `analise-raisesexception-1805.md` | O relatório do teste anterior, que identificou o `RaiseException` |
| `crash-2026-10-31-1716-host-3PC.txt` | Log do teste das 17:11 — **o único em que o boneco do anfitrião apareceu no convidado** |
| `crash-2026-10-31-1716-host-analise.md` | Análise do mesmo teste |
| `guest-2026-10-31-1715.log` | Log do outro lado da mesma sessão |
| `guest-diagnostico-1707.txt` | Diagnóstico do lado convidado |
| `crash-2026-10-31-spawn.txt` | Crash de spawn, tentativa 1 |
| `crash-2026-10-31-spawn-2.txt` | Crash de spawn, tentativa 2 |
| `crash-2026-10-31-1716-monitor.txt` | Saída do vigia durante o teste |

### O que este conjunto estabelece

1. A conexão funciona (`Net: connected`, rtt ~30 ms) ✅
2. A posição é lida corretamente nos dois PCs ✅
3. O convidado **viu** o boneco do anfitrião e sobreviveu ✅
4. **Injetar o personagem do convidado no anfitrião mata o processo** ❌

---

## 2. O port para a 3460

O jogo atualizou no meio do projeto. Todo endereço fixo da versão original ficou errado.

| Arquivo | O que é |
|---|---|
| **`porte-3460.md`** | **O registro do port.** Comece por aqui |
| `validacao-3460.md` | Validação ao vivo dos endereços |
| `globais-3460.md` | Os quatro globais que **mudaram de região** — ver abaixo |
| `fieldtime-3446.md` | Estado em 3446, para comparação |
| `cargas-de-ator-3446.md` | Cargas de ator em 3446 |
| `hallazgos-en-vivo.md` | Descobertas ao vivo |

### O achado mais importante

Quatro globais foram remedidos e **os objetos apontados por eles saíram da região onde a
3446 os mantinha.** Não é um deslocamento a corrigir — **a região toda foi reorganizada.**
Detalhe em `globais-3460.md`.

---

## 3. O sistema Troc (mensagens do jogo)

O jogo usa um sistema de mensagens com RTTI. Entender isso é pré-requisito para o resto.

| Arquivo | O que é |
|---|---|
| **`troc-rtti.md`** | **Como achar classes por RTTI.** Fundamental |
| `troc-dispatch.md` | Como as mensagens são despachadas |
| `troc-bdo-y-runtime.md` | Comparação com Black Desert (mesma engine) |
| **`troc-sintesis.md`** | **Como SINTETIZAR uma mensagem** — o que o mod faz |
| `mirror-ack-formats.md` | Formatos de ACK |

---

## 4. O transporte e a conexão

| Arquivo | O que é |
|---|---|
| **`steam-transporte.md`** | **A sala Steam, o código, o relay.** Nota: o mod usa **relay apenas** — `direct connections off`, o outro jogador nunca vê o seu IP |
| `broadcast-servidor-movimiento.md` | Broadcast de movimento |
| `movimiento-remoto-cliente.md` | Movimento remoto no cliente |

---

## 5. O boneco remoto e suas falhas

O coração do problema atual.

| Arquivo | O que é |
|---|---|
| `apariencia-estado-coop.md` | Aparência e estado — 37 KB, o maior |
| `lag-invitado-7oct.md` | Latência do convidado |
| `saltos-copia-anfitriao.md` | Saltos da cópia no anfitrião |
| `pendiente-copia-se-hunde.md` | A cópia afunda no chão |
| `pausa-copia-congelada.md` | Cópia congelada |
| `espejo-refinamiento.md` | Refinamento do espelhamento |
| `pointclimb-remoto.md` | Escalada remota |

---

## 6. Inimigos e chefes

| Arquivo | O que é |
|---|---|
| `enemigos-del-anfitrion.md` | Inimigos do anfitrião |
| `copias-enemigos-faltan-pose-minimapa.md` | Cópias faltando pose e minimapa |
| `copias-grupo-invisibles.md` | Cópias de grupo invisíveis |
| `copias-sin-dano-7oct.md` | Cópias sem dano |
| `enemigos-agachados-apose.md` | Inimigos agachados |
| `pendiente-jefes.md` | **Chefes — trabalho pendente** |
| `ids-enemigos-verificacion.md` | Verificação de IDs |
| `pendiente-aggro-y-respuesta-golpes.md` | Aggro e resposta a golpes |
| `pendiente-proyectiles.md` | Projéteis |
| `pendiente-jinetes-animales.md` | Montarias |
| `fase5-suprimir-enemigos-invitado.md` | Suprimir inimigos do convidado |
| `pendiente-3g-suprimir-enemigos-invitado.md` | O mesmo, pendente |

---

## 7. Recompensas, loot e progresso

| Arquivo | O que é |
|---|---|
| **`botin-invitado.md`** | **Loot do convidado — 82 KB, o maior arquivo.** O requisito central do pedido |
| `pendiente-recompensas-progreso.md` | Recompensas e progresso |
| `pieza4-botin-reaccion.md` | Reação do loot |
| `pieza4-capturas.md` | Capturas |
| `pieza4-dano-servidor.md` | Dano no servidor |
| `pieza4-tambaleo.md` | Cambaleio |

---

## 8. Minimapa, mundo e ambiente

| Arquivo | O que é |
|---|---|
| `mapa-minimapa.md` | Mapa e minimapa |
| `minimapa-icono-enemigo.md` | Ícone de inimigo no minimapa |
| `interacciones-mundo.md` | Interações com o mundo |
| `hora-del-dia.md` | Hora do dia |
| `zona-tras-muerte-anfitrion.md` | Zona após a morte do anfitrião |
| `muerte-realista.md` | Morte realista |

---

## 9. Combate

| Arquivo | O que é |
|---|---|
| `combate-coop.md` | Combate em co-op |
| `copia-objetivo-sin-ataques.md` | Cópia objetivo sem ataques |
| `caballo-coop.md` | Cavalo |

---

## 10. Pesquisa externa e referências

| Arquivo | O que é |
|---|---|
| `genshin-coop-referencia.md` | Referência de co-op do Genshin |
| `bdo-emuladores-monstruos.md` | Emuladores de monstros do BDO |
| `cd-companion-justskip.md` | Mod companion |
| `cheat-tables-versions.md` | Tabelas de cheat por versão |
| `orcax-equiphide.md` | Esconder equipamento |
| `ropa-al-desmontar.md` | Roupa ao desmontar |
| `flecha-color.md` | Cor da flecha |

---

## 11. Outros pendentes

| Arquivo | O que é |
|---|---|
| `pendiente-robustez.md` | Robustez — 47 KB |
| `pendiente-rango-claves.md` | Alcance de chaves |
| `pendiente-reaccion-muerte-invitado.md` | Reação à morte do convidado |
| `arbol-cuerda*.md` | Árvore de corda (6 arquivos) — investigação visual |
| `experimento-4c.md` | Experimento 4C |
| `captura-1.md`, `captura-2.md` | Notas de captura |
| `README.md` | O README antigo desta pasta |

---

## Como usar esta pasta

**Os arquivos são longos e em espanhol.** Os mais úteis estão em **negrito** acima.

**Três coisas a saber antes de ler qualquer um deles:**

1. **São registros de investigação, não conclusões.** Vários contêm hipóteses que depois se
   mostraram falsas. A palavra espanhola *"pendiente"* significa **não resolvido**.

2. **Cuidado com números.** Este projeto foi enganado repetidas vezes por valores
   plausíveis que não eram medições. Um número num documento antigo **pode ser lixo** — os
   piores exemplos estão catalogados em [`../DOSSIE.md`](../DOSSIE.md) §8.

3. **`arbol-cuerda-*.md`** são seis arquivos sobre um único problema visual. Baixa
   prioridade.

**Os logs de crash brutos** (`crash-*.txt`, `guest-*.log`) são **dados primários** — valem
mais que as análises, incluindo as minhas.
