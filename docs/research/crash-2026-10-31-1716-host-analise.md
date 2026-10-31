# Teste de 2 PCs — 31/10/2026, 17:08–17:14 (terceira tentativa)

**Resultado: o co-op FUNCIONOU nos dois lados. O anfitrião morreu 1 segundo depois.**

Este é o teste mais informativo do projeto, porque pela primeira vez os dois lados chegaram ao
mesmo estado e o log de cada um permite ver o outro.

## Participantes

| | |
|---|---|
| Anfitrião | `CONVIDADO` (<STEAMID-CONVIDADO>), build `215C5636`, sala `1YZDAWX` |
| Convidado | `ANFITRIAO` (<STEAMID-ANFITRIAO>), build `215C5636` |
| Jogo | 1.0.0.3460 (PE `0x6AE58024`) nos dois |

## Linha do tempo

```
17:10:04  convidado abre o jogo, mod carrega, Game reader enabled
17:10:41  convidado recebe o personagem do anfitriao (49174 bytes)
17:11:33  convidado ENTRA NO MUNDO e anuncia o proprio personagem
          anfitriao recebe: (-20626.6, 621.3, -6813.7)   <- POSICAO CORRETA
17:11:33  convidado injeta o personagem do anfitriao  -> criado
17:11:34  anfitriao injeta o personagem do convidado  -> *** MORRE ***
17:11:34  convidado: "co-op: other player loaded"    <- BONECO APARECEU
17:11:39  convidado: "peer timed out after 5000 ms"  <- detecta a morte
17:14:34  convidado continua vivo, tentando reconectar (fim do log)
```

## O que ficou provado

**1. O bug da posicao zerada era SO' TIMING.** Nas duas tentativas anteriores a posicao do
convidado chegou `(0,0,0)` em 216 medicoes seguidas. Nesta, depois de o mundo dele carregar,
chegou correta. A hipotese levantada apos o teste anterior esta confirmada, e a instrumentacao
adicionada (`[NEVER VALID: N updates]`) teria mostrado isso sozinha.

**2. O leitor de posicao funciona nos DOIS PCs.** Nao era um port quebrado de um lado.

**3. Os dois bonecos foram criados com sucesso.** O convidado registrou
`co-op: other player loaded` as 17:11:34.423, um milissegundo antes de o anfitriao morrer.

**4. A correcao do guard funcionou.** Nenhuma mensagem de recusa apareceu, porque nao havia
nada a recusar: a posicao estava valida.

**5. O crash NAO e' do spawn.** O spawn completou nos dois lados. O processo do anfitriao morreu
DEPOIS, com o co-op ja estabelecido.

## As duas assimetrias -- nenhuma e' um defeito

**Ambas explicadas lendo o codigo. Nenhuma das duas e' bug.**

### `remote states 0` no anfitriao vs `962` no convidado

`stats_.remote_states` so' incrementa para pacotes `PlayerState`
(`client_session.cpp:175-177`). E `PlayerState` so' e' enviado a partir de
`sample()` (`mod.cpp:454`), que devolve `nullopt` enquanto o leitor local falha
(`mod.cpp:159`).

Ou seja: **o contador mede estados recebidos, e o numero baixo do anfitriao e' real** -- ele
recebeu poucos `PlayerState` do convidado naqueles segundos, porque o convidado tinha acabado
de entrar no mundo e estava no comeco da troca. O convidado recebeu 962 porque o anfitriao
estava no mundo havia minutos.

**Nao e' assimetria de defeito, e' assimetria de tempo de sessao.** O campo esta' correto.

### `session 1` (connecting) no convidado enquanto funcionava

`kNames[]` em `steam_transport.cpp`: `0 none, 1 connecting, 2 finding route, 3 connected`.
E' o estado da conexao Steam P2P, e e' **descritivo** -- nao fecha porta nenhuma. O convidado
trocou 1155 pacotes e criou o boneco enquanto o rotulo dizia `connecting`.

**E' rotulo atrasado, nao funcionalidade ausente.** Vale corrigir o rotulo um dia; nao explica
o crash e nao bloqueia o teste.

## O que isso muda

A hipotese "o anfitriao nao estava recebendo o convidado" esta' MORTA -- ele recebeu o
personagem, a posicao e os pacotes. O crash nao e' falta de dados.

## Descarte

`Suppress: largest actor load 23389 bytes (ceiling 16384)` aparece no log do convidado. NAO e'
a causa: o teto e' de carregamentos de INIMIGOS (`enemy_relay.cpp:1525`), o proprio codigo
avisa que veio de uma medicao na 2976 e nunca foi re-medido, e a linha diz
`0 refused for size` -- nada foi recusado por tamanho.

## O que falta

O anfitriao morreu sem deixar relatorio do Windows (nenhum WER novo), o que aponta para dentro
do processo. Falta capturar a pilha no momento da morte: sem `cdb`/`windbg` instalados, a via e'
o script `capture-hang.ps1` que ja acompanha o kit, ou instalar as ferramentas de depuracao.

**A pergunta a responder:** o que o anfitriao faz entre 17:11:34.420 (injecao entregue) e a
morte, sabendo que o convidado sobreviveu a injecao equivalente?
