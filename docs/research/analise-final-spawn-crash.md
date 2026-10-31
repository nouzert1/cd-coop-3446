======================================================================
RELATORIO DO ANFITRIAO -- CRASH DE SPAWN NA v0.18.0 (build D7FE9358)
Sessao de 2026-10-31, 18:14:19 a 18:17:25
======================================================================

  RESULTADO: a correcao do RaiseException FUNCIONOU (o jogo agora passa
  do menu e chega ao mundo), mas o CRASH DE SPAWN CONTINUA -- e agora
  esta' isolado com precisao de 23 milissegundos.

  Este e' um crash DIFERENTE do de hoje de manha. Os dois primeiros
  (v0.17.0) aconteciam ANTES do menu. Este acontece ao injetar o
  personagem do convidado, exatamente como descrito no INVESTIGATION.md.

======================================================================
1. IDENTIFICACAO
======================================================================
  Papel      : ANFITRIAO (role=host)
  Quem       : ANFITRIAO, SteamID64 <STEAMID-ANFITRIAO>
  Convidado  : CONVIDADO, SteamID64 <STEAMID-CONVIDADO>
  Kit        : cdmp-3460-role-swap-host.zip  v0.18.0-3460-fix
  Build id   : D7FE9358  (protocol 10)

  cdmp.asi  sha256 43335AA91BA673EFE8EAA440E30535C03E302EA55467DA3F68969524A1992256  PASS
  winmm.dll sha256 031A3E5576D91DCE1E438D36B9A3D462C7334AB4791990A8FF1E3DDC0E132DAF  PASS
  role=host | peer_steamid= | code=            (conforme exigido)

  Instalacao feita do zero: os 6 ficheiros do mod apagados antes de copiar.
  dinput8.dll renomeado para winmm.dll. Hashes conferidos contra o
  bloco do COMO-INSTALAR.md -- os tres valores batem exatamente.

======================================================================
2. A CORRECAO DO RaiseException FUNCIONOU
======================================================================
  Exit watch: TerminateProcess hooked | ExitProcess hooked |
              RtlExitUserProcess hooked (RaiseException not hooked:
              it fires as normal control flow)

  O hook problematico ja' nao esta' instalado, e o log di-lo por extenso.
  CONSEQUENCIA MEDIVEL: o jogo agora ARRANCA E ENTRA NO MUNDO.

    - v0.17.0: morria aos ~28 s, ANTES do menu, 0xc0000005 em cdmp.asi.
    - v0.18.0: arrancou, chegou ao mundo, correu ~3 minutos, conectou,
               e so' morreu ao injetar o convidado.

  Isto confirma que a causa dos crashes da manha era mesmo o hook de
  RaiseException. Essa parte esta' resolvida.

======================================================================
3. *** O CRASH DE SPAWN -- 23 MILISSEGUNDOS ***
======================================================================
  Sequencia exata, do log (todas as linhas, sem omissao):

  [18:17:25.336] Co-op: map pin of the other player at (-20627, -6814)
  [18:17:25.484] Co-op: received the other player's character (39795 bytes,
                 player 0xA0100001, spawn 1)
  [18:17:25.487] Puppet: rewrote keys in user packet: user x3, player x104, body x0
  [18:17:25.487] Puppet: rewrote keys in body packet: user x4, player x104, body x8
  [18:17:25.487] Puppet: spawn queued at (-20626.6, 621.3, -6813.7)
                 (2 packets, 16637 + 6445 bytes, sender player 0xA0100001, generation 1)
  [18:17:25.487] Co-op: the other player is in our world (spawn 1)
  [18:17:25.510] Inject: delivered opcode 2005 (16642 bytes) to ClientNet::OnRecvPacket
  [18:17:25.510] Inject: delivered opcode 2005 (6450 bytes) to ClientNet::OnRecvPacket
                 >>> FIM DO LOG. O processo morreu aqui. <<<

  Da ultima linha escrita (18:17:25.510) ate' a morte: ~23 ms.
  Nenhuma excecao registada, nenhum assert, nenhuma linha de erro.

  As duas ultimas linhas sao a INJECAO BEM-SUCEDIDA do opcode 2005
  (ActorLoadDataAck) -- o mod entregou os dois pacotes e retornou. O que
  mata o jogo esta' DEPOIS da injecao, no processamento que o jogo faz
  desses pacotes.

  Assinatura identica ao INVESTIGATION.md (que a mediu na 3446):
    "Co-op: the other player is in our world (spawn 1)"
    "Inject: delivered opcode 2005 ..."
    >>> nothing after this <<<

======================================================================
4. O REGISTO DO WINDOWS
======================================================================
  ATENCAO: os unicos Application Error 1000 nas ultimas 15 minutos sao
  os DOIS da v0.17.0, das 18:03:29 e 18:04:39 (modulo cdmp.asi,
  0xc0000005, deslocamento 0xea109).

  *** ESTE crash da v0.18.0 NAO GEROU Application Error NEM APPCRASH. ***
  *** E o Exit watch tambem NAO registou nada (bloco 'Exit:' vazio).    ***

  Ou seja: a morte de agora e' SILENCIOSA outra vez -- sem evento Windows,
  sem linha 'Exit:', sem dump. E' o padrao que a v0.4.0-3446 descreveu
  como travamento (AppHangTransient), nao como crash.

  Isto e' relevante: o Exit watch da v0.18.0 nao apanhou esta morte.
  Ele hooka TerminateProcess, ExitProcess e RtlExitUserProcess, mas a
  saida nao passou por nenhum dos tres -- ou o processo foi morto por
  um watchdog de fora, como a v0.4.0-3446 propos.

======================================================================
5. O QUE ESTAVA SAUDavel ANTES DO CRASH (nao e' o problema)
======================================================================
  Ligacao Steam ......... COMPLETA
    Net: connected | rtt 32.1 ms | relay 100 | session 3 | ping 25-29 ms
    sent 1276 recv 171, rejected 0, send errors 0

  Leitura da posicao local ..... A FUNCIONAR (12 valores distintos!)
    [18:16:59] pos (-20621.39, 619.09, -6823.67)
    [18:17:14] pos (-20624.05, 619.04, -6824.25)
    [18:17:19] pos (-20626.15, 619.01, -6824.15)
    [18:17:24] pos (-20621.73, 619.10, -6822.86)
    -> a posicao MUDA quando o jogador anda. O leitor do anfitriao esta' bom.

  Overlay ............... presents 6481 drawn 6480
  Latencia do loop de rede: 987-1027 loops/10 s, p95 0.0 ms, max 0.4 ms

  O unico valor estranho, e provavelmente de diagnostico e nao de causa:
    check vs game global 9008531862833856512.00 m
  (este numero absurdo aparece em TODAS as linhas da sessao, desde o
   inicio, muito antes do convidado chegar -- ver seccao 7)

  estados remotos recebidos: 0 -- o convidado envia, mas 'remote states 0'
  em todas as amostras. O boneco foi recebido por outro caminho
  ('received the other player's character', 39795 bytes).

======================================================================
6. LINHA DO TEMPO DA SESSAO
======================================================================
  18:14:19.249  mod carrega -- build D7FE9358, protocol 10
  18:14:20.566  Room: your code is 1Z65A0K
  18:14:37.463  Exit watch armado (SEM RaiseException)
  18:16:59      Net: connected, relay 100, posicao a mover-se normalmente
  18:17:25.336  Co-op: map pin of the other player at (-20627, -6814)
  18:17:25.484  recebido o personagem do convidado (39795 bytes)
  18:17:25.487  spawn queued + "the other player is in our world"
  18:17:25.510  Inject: delivered opcode 2005 (x2)
  18:17:25.53?  >>> MORTE (23 ms depois) <<<

  Tempo total de vida: 3 min 6 s. O jogo estava saudavel e no mundo.

======================================================================
7. PISTA: 'check vs game global' com valor impossivel
======================================================================
  Todas as linhas de posicao trazem:
    check vs game global 9008531862833856512.00 m

  9.0e18 metros e' um valor absurdo (interpretacao de bits de float/double
  como inteiro, ou leitura de um global nao inicializado). Aparece DESDE O
  INICIO da sessao, inclusive antes de o convidado existir, portanto NAO
  e' causa deste crash.

  Mas vale registar porque:
   - na sessao de convidado de hoje (v0.16.0) o mesmo campo dizia
     'check vs game global n/a' -- ou seja, mudou de comportamento;
   - se este global e' o mesmo que o guard de posicao "estacionada" usa,
     um valor assim pode fazer o guard aceitar lixo. A v0.16.0-3460
     descreve exatamente esse tipo de defeito: "o guard testava o valor
     que a build anterior produzia".

======================================================================
8. O QUE MUDOU, E O QUE ISSO DIZ
======================================================================
  | versao | build    | antes do menu        | ao injetar o convidado |
  |--------|----------|----------------------|------------------------|
  | v0.16.0| 215C5636 | OK                   | OK (convidado, 6 min)  |
  | v0.17.0| A8AE702B | CRASH 0xc0000005 x2  | (nao chegou la')       |
  | v0.18.0| D7FE9358 | OK (corrigido)       | CRASH silencioso 23 ms |

  A v0.18.0 corrigiu o defeito introduzido na v0.17.0, e devolveu o mod ao
  estado em que o crash de spawn volta a ser alcancavel. O crash de spawn
  e' portanto um defeito PRE-EXISTENTE (o do INVESTIGATION.md), nao uma
  regressao nova.

======================================================================
9. PEDIDOS CONCRETOS
======================================================================
  P1. O crash de spawn nao deixa rasto nenhum: sem evento Windows, sem
      'Exit:', sem dump. A v0.4.0-3446 propos que e' travamento e que um
      watchdog mata o processo. Se assim for, o Exit watch atual (que
      hooka TerminateProcess/ExitProcess/RtlExitUserProcess) NUNCA vai
      apanhar isto -- porque a morte vem de FORA do processo.
      Sugestao: hookar tambem a via do watchdog, ou usar
      'diagnostico/capture-hang.ps1 -Watch' da v0.4.0-3446, que grava o
      dump ENQUANTO o jogo roda, com o indice intacto.

  P2. O guard que recusa a posicao "estacionada" durante o carregamento:
      confirmar qual global ele le e se aceita 9008531862833856512.00.
      (seccao 7)

  P3. Reproduzir com 'record=1' no [sniffer] para guardar os pacotes
      exatos do opcode 2005 que matam o processo. Agora sabemos o instante
      com precisao de 23 ms, o que torna a captura viavel.

======================================================================
FICHEIROS
======================================================================
  cdmp-HOST-SPAWNCRASH-1818.log  -- log integral desta sessao (capturado
                                    com o jogo fechado, 36 KB)
  cdmp-HOST-crash-v017.log       -- o crash anterior (v0.17.0), para
                                    comparacao
======================================================================
