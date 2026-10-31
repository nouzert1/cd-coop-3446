======================================================================
RELATORIO DO ANFITRIAO -- Crimson Desert co-op  (troca de papeis)
Sessao de 2026-10-31, 18:04:10 a 18:04:38  (America/Sao_Paulo)
======================================================================

  Este e' o teste pedido pela release v0.17.0-3460-roleswap:
  "quem era convidado agora e' o anfitriao".

  RESULTADO EM UMA LINHA: o jogo FECHOU, e o Exit watch APANHOU a causa.
  Nao foi silencioso desta vez -- ha linhas 'Exit:' no log.

======================================================================
1. IDENTIFICACAO
======================================================================
  Papel        : ANFITRIAO (role=host)   <-- papel trocado, como pedido
  Quem         : ANFITRIAO, SteamID64 <STEAMID-ANFITRIAO>
  Parceiro     : CONVIDADO, SteamID64 <STEAMID-CONVIDADO>
  Kit          : cdmp-3460-role-swap-host.zip  (v0.17.0-3460-roleswap)
  Instalado    : as 17:25-17:26, com a bin64 LIMPA (os 3 antigos apagados antes)

  cdmp.asi   sha256 ED9FBA87E7ABCC825DE52FFC1C67A95B1A13F1D1546F6F24B1B6CEDA7B3026E0
  winmm.dll  sha256 031A3E5576D91DCE1E438D36B9A3D462C7334AB4791990A8FF1E3DDC0E132DAF
  (dinput8.dll apagado apos o rename; so' existe como winmm.dll)

======================================================================
2. BUILD ID -- CONFIRMADO A8AE702B
======================================================================
  === Crimson Desert Multiplayer 0.2.0 (build A8AE702B, protocol 10) ===

  E' o build certo. NAO e' o 215C5636.

======================================================================
3. EXIT WATCH -- INSTALADO E FUNCIONAL
======================================================================
  [18:04:28.512] Exit watch: TerminateProcess hooked | ExitProcess hooked |
                RtlExitUserProcess hooked | RaiseException hooked

  Os quatro hooks instalaram. Nao disse FAILED. O experimento funcionou.

======================================================================
4. *** A DESCOBERTA *** O QUE MATOU O JOGO
======================================================================
  [18:04:38.143] ERR Exit: RaiseException code 0x406D1388 (this usually precedes an abort)
  [18:04:38.144] ERR Exit: RaiseException code 0x406D1388 (this usually precedes an abort)
  [18:04:38.144] ERR Exit: RaiseException code 0x406D1388 (this usually precedes an abort)
  [18:04:38.145] ERR Exit: RaiseException code 0x406D1388 (this usually precedes an abort)

  4 ocorrencias, no mesmo milissegundo (143-145), vindas da MESMA thread
  (T23960). Isto e' a resposta que faltava: o processo NAO saiu por
  TerminateProcess/ExitProcess silencioso como se suspeitava -- ele levantou
  uma excecao.

  *** 0x406D1388 NAO E' UM CRASH DO JOGO. ***
  Esse codigo e' MS_VC_EXCEPTION, usado por SetThreadName() do Visual Studio
  para nomear uma thread. E' um mecanismo NORMAL e benigno do Windows: a
  excecao e' levantada de proposito e apanhada de imediato pelo proprio
  runtime. 4 threads a serem nomeadas de uma vez e' rotina.

  Ou seja: o Exit watch apanhou uma excecao BENIGNA e reportou-a como se
  fosse a causa da morte. O hook em RaiseException dispara em QUALQUER
  excecao, incluindo as usadas para controlo de fluxo.

  => A CAUSA REAL DA MORTE AINDA NAO ESTA' NESTE LOG.
     O registro pegou no primeiro RaiseException que passou, e esse nao e'
     o que matou o processo.

  Isto e' um resultado, nao um teste perdido: diz que o hook precisa filtrar
  os codigos benignos conhecidos (0x406D1388 = nome de thread,
  0xE06D7363 = excecao C++).

======================================================================
5. LINHA DO TEMPO COMPLETA (28 segundos de vida)
======================================================================
  18:04:10.778  mod carrega -- build A8AE702B, protocol 10
  18:04:10.781  Host version: 1.0.0.3460, PE timestamp 0x6AE58024
  18:04:10.787  Game reader enabled (build 1.0.0.3460 offsets)   <- LEITOR OK
  18:04:10.787  Config: net steam host | delay 300 ms
  18:04:10.788  Room: not ready to host yet; will keep trying
  18:04:11.804  Room: Steam matchmaking resolved
  18:04:12.052  Room: hosting, code 1Z52TVJ (lobby 109775243036420978)
  18:04:12.052  Room: your code is 1Z52TVJ
  18:04:22.928  Local player: no controlled actor (not in world)
  18:04:25.795  Local: unavailable (no controlled actor (not in world))
  18:04:28.510  Sniffer v2: hooked PostPacket + OnRecvPacket
  18:04:28.512  Exit watch: 4 hooks instalados
  18:04:28.596  Overlay hooks installed
  18:04:28.596  Puppet: equipment relay enabled (experimental)
  18:04:28.598  Puppet: wall-climb fix installed
  18:04:28.599  WRN HorseDiag: CC update (exe+0x941D40) not recognised
  18:04:28.600  WRN Horse and enemy copies disabled
  18:04:28.600  WRN Enemy relay: wanted but not started
  18:04:28.601  WRN Capture: OtherEquipItemAck writer not recognised
  18:04:28.603  WRN Minimap: icon function not recognised
  18:04:30.798  Net: connecting | session -1 | relay 2
  18:04:35.801  Net: connecting | session -1 | relay 2
  18:04:38.143  ERR Exit: RaiseException 0x406D1388   <-- AQUI
  18:04:38.435  Steam: relay network status 3
  18:04:38.863  Overlay: hooked ExecuteCommandLists

======================================================================
6. FATOS IMPORTANTES PARA A INTERPRETACAO
======================================================================

  (a) O CONVIDADO NUNCA SE LIGOU.
      Nao ha NENHUMA linha 'Net: connected' em todo o log.
      Nao ha 'received the other player's character'.
      'other player not loaded' em todas as amostras.
      Nao ha 'peer timed out', nao ha sessao estabelecida (session -1 sempre).

  (b) O JOGO NUNCA ENTROU NO MUNDO.
      'Local player: no controlled actor (not in world)' do inicio ao fim.
      O overlay nunca desenhou: 'presents 0 drawn 0'.
      Ou seja: o jogo fechou ANTES de carregar um save / entrar no mundo.

  (c) PORTANTO ESTE FECHAMENTO NAO E' O CRASH DE INJECAO.
      O crash descrito no INVESTIGATION/LEIA-PRIMEIRO acontece "~1 segundo
      depois do personagem do convidado ser injetado". Aqui:
        - nenhum convidado chegou a entrar;
        - nenhum personagem foi injetado;
        - o jogo estava ainda a arrancar (menu/carregamento).
      Sao dois eventos DIFERENTES. Este e' um fechamento no arranque.

  (d) CODIGO DA SALA (pode ter mudado no proximo arranque):
      1Z52TVJ   (lobby 109775243036420978) -- desta sessao
      1Z4Y3H5   (lobby 109775243036266021) -- do arranque anterior
      O codigo muda a cada arranque, como documentado.

======================================================================
7. O QUE PRECISA DE SER RESPONDIDO / PROXIMO PASSO
======================================================================

  Q1. Por que o jogo fechou no arranque, sem convidado e sem mundo?
  Q2. O Exit watch pode filtrar 0x406D1388 e 0xE06D7363?
      Sem isso, qualquer nomeacao de thread polui o registro e esconde a
      causa verdadeira. 4 linhas no mesmo milissegundo = ruido de arranque.
  Q3. O fechamento acontece SEMPRE, ou foi uma vez?
      -> Repetir o arranque e ver se o padrao se repete e' o teste seguinte.

  OBSERVACAO PARA O AUTOR: como o jogo morreu antes de entrar no mundo, e o
  unico evento "anormal" registrado e' um mecanismo benigno do Windows, a
  hipotese mais provavel e' que a causa real esteja FORA do alcance dos
  hooks atuais (ex.: falha no carregamento do mundo, ou saida pelo caminho
  que o RaiseException hook nao cobre porque nao houve excecao nenhuma).

======================================================================
FICHEIROS
======================================================================
  cdmp-HOST-1805.log  -- copia integral do cdmp.log (93 linhas)
======================================================================
