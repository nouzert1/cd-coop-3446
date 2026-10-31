# Guia do CONVIDADO — quem vai visitar o mundo do amigo

Você vai entrar no mundo de outra pessoa. **Você não é o dono da partida**: o mundo, os inimigos e
as missões são do anfitrião. Seu papel é visitar, ajudar e pegar o seu loot.

Siga na ordem. Leva uns 15 minutos.

---

## Parte 1 — Antes de instalar (5 min)

### 1.1 Backup do seu save — FAÇA ISTO

1. Aperte `Win+R`
2. Cole isto e aperte Enter:
   ```
   %LOCALAPPDATA%\Pearl Abyss\CD
   ```
3. Copie a pasta **`save`** para a Área de Trabalho.

Se algo der errado, você apaga a pasta e restaura essa cópia. **Nada neste mod deveria estragar seu
save** — ele foi feito para recusar em vez de arriscar. Mas o backup leva 1 minuto e é a diferença
entre um susto e perder tudo.

### 1.2 Confira a versão do jogo

1. No Steam: botão direito em Crimson Desert → Gerenciar → **Procurar arquivos locais**
2. Na pasta que abrir, vá em `bin64`
3. Botão direito em **`CrimsonDesert.exe`** → Propriedades → aba **Detalhes**
4. Procure **"Versão do arquivo"**. Tem que ser exatamente:

```
1.0.0.3460
```

**Se for diferente, PARE e avise o anfitrião.** O mod só funciona nessa versão exata, e não tem como
adivinhar que o problema é esse — o jogo não avisa, o mod só para de ler.

> O jogo já se atualizou sozinho **duas vezes** durante este projeto. Para evitar surpresa:
> botão direito em Crimson Desert → Propriedades → **Atualizações** → escolha
> **"Só atualizar este jogo quando eu iniciar"**.

### 1.3 Confirme que vocês são amigos na Steam

O mod encontra o anfitrião pela **lista de amigos**. Se vocês não forem amigos, ele não acha
ninguém e nada acontece.

### 1.4 Confira o que você vai precisar

Você recebeu um arquivo `.zip`. Dentro dele tem:

| Arquivo | Para que serve |
|---|---|
| `cdmp.asi` | o mod |
| `cdmp.ini` | a configuração — **já vem pronta, não mexa** |
| `dinput8.dll` | o carregador (vai ser renomeado) |
| `COMECE-AQUI-PORTUGUES.txt` | este guia |
| `SHA256SUMS.txt` | conferência de integridade |

---

## Parte 2 — Instalar (5 min)

### 2.1 Feche o jogo

O jogo **precisa estar fechado**, senão os arquivos ficam travados.

### 2.2 Copie 3 arquivos

1. Abra a pasta do jogo: Steam → botão direito em Crimson Desert → Gerenciar → **Procurar arquivos
   locais** → abra **`bin64`**
2. Extraia o zip em algum lugar (Área de Trabalho serve)
3. Copie estes **3 arquivos** para dentro de `bin64`:

```
cdmp.asi
cdmp.ini
dinput8.dll
```

### 2.3 RENOMEIE o `dinput8.dll`

Depois de copiar, dentro de `bin64`:

```
dinput8.dll   →   RENOMEIE PARA   winmm.dll
```

**Este passo é obrigatório.** O jogo só carrega o mod através de um arquivo chamado `winmm.dll`.
Se ficar `dinput8.dll`, nada acontece e você não vê painel nenhum.

> ⚠️ **Se a pasta `bin64` já tiver um `winmm.dll`**, **PARE** e avise o anfitrião. Pode ser de outro
> mod, e sobrescrever quebra os dois.

### 2.4 Não edite o `cdmp.ini`

Ele já vem configurado para você. Confira só se tem estas linhas:

```ini
[net]
role=guest                          ← você é o convidado

[steam]
peer_steamid=76561199441047799      ← o SteamID do anfitrião, já preenchido

[coop]
enabled=1                           ← o interruptor principal
```

**[coop] enabled=1 é o mais importante.** É ele que faz o personagem do anfitrião **aparecer** no seu
mundo. Se estiver `0`, vocês conectam mas você **não vê o boneco dele**.

---

## Parte 3 — Jogar

### 3.1 Espere o anfitrião abrir primeiro

**Ele abre o jogo e carrega um save primeiro.** Espere ele avisar que está no mundo.

### 3.2 Abra o jogo e carregue seu save

1. Abra o Crimson Desert normalmente
2. Carregue o **seu** save
3. Espere o mundo carregar de verdade (você andando, não na tela de carregamento)

### 3.3 Vá para o mesmo lugar que ele

Combine **antes** onde vocês vão se encontrar. Sugestão: a primeira cidade, ou um acampamento
conhecido.

**Isto importa.** Vocês precisam estar no mesmo lugar do mapa para a descoberta funcionar.

### 3.4 Olhe o painel

O painel fica no **canto superior esquerdo**. **`F8`** mostra ou esconde.

Você deve ver:

```
Network: connected to '<nome do anfitrião>' (XX ms)
Other player: HP xxxx/xxxx   XX m away
```

### 3.5 A pergunta mais importante

Chegue **perto** dele (menos de 50 m) e olhe em volta.

> **Você VÊ o personagem dele no mundo, andando?**

**Esta é a resposta que estamos procurando.** É a coisa que nunca foi confirmada neste mod.

⚠️ **A distância no painel NÃO é a mesma coisa que ver o boneco.** Já aconteceu de a distância
funcionar e o personagem não existir na tela. São duas coisas separadas, e as duas precisam ser sim.

---

## Parte 4 — O que esperar (e não estranhar)

### O que FUNCIONA

- Conectar e ver a distância
- Ver a vida do outro no painel
- Os inimigos do anfitrião aparecem no seu mundo
- Você bate neles e o dano conta para ele
- Você pega o **seu** loot dos inimigos comuns

### O que NÃO funciona — já é conhecido, não é problema seu

| Coisa | O que você vai ver |
|---|---|
| **Rotação do personagem remoto** | Ele aparece **parado de frente**, sempre. Mesmo andando para o lado |
| Ícone dele no minimapa | Não aparece |
| Horário do jogo sincronizado | Não sincroniza |
| Sua missão de chefe | Não avança (de propósito — o chefe não é seu) |
| Loot de chefe | Não dropa para você |
| Cavalo montado | Desligado |

### Regras de chefe

Em chefe, você **vê e machuca**, mas **o golpe final é sempre do anfitrião**. Se você matar, a missão
dele trava. Deixe ele dar o último golpe.

Suas próprias missões e seu XP **não são afetados** por nada disso. Você está visitando.

---

## Parte 5 — Mensagens que você pode ver

| Mensagem | Significa | O que fazer |
|---|---|---|
| `check vs game global n/a` | **Normal.** O mod se abstém de um autocontrole que não funciona neste build | Nada |
| `Camera: camera block sentinel mismatch` | **Esperado.** É por isso que o personagem aparece parado de frente | Nada, é conhecido |
| `Different mod versions` | Os `cdmp.asi` são diferentes | **Os dois precisam usar o MESMO zip** |
| Nenhum painel | O mod não carregou | Você renomeou para `winmm.dll`? Os 3 arquivos estão em `bin64`? |
| `Game reader DISABLED: unsupported game build` | A versão do jogo mudou | Avise o anfitrião |

---

## Parte 6 — Regras durante o teste

1. **NINGUÉM salva o jogo** enquanto o outro estiver no mundo. Esta é a forma mais provável de
   estragar um save.
2. **Não apague o `cdmp.log`.** Ele é o resultado do teste.
3. Se o anfitrião pedir, aperte **Ctrl+F12** junto com ele.

### Por que o `Ctrl+F12`

Ele grava uma **marca numerada** no `cdmp.log`, com a hora exata. Quando vocês dois apertam **no mesmo
instante**, os dois logs ganham a mesma marca no mesmo momento — e aí dá para **alinhar as duas linhas
do tempo** e ver o que cada lado estava fazendo no instante de um problema.

Aperte quando algo interessante acontecer: o boneco apareceu, o boneco sumiu, o jogo travou, o dano
não contou. Combine com o anfitrião: *"agora!"* — os dois apertam juntos.
4. Se o jogo travar ou fechar sozinho, **anote o que estava acontecendo** naquele momento: quem fez o
   quê, se tinha inimigo por perto, se era chefe. É um problema conhecido e o contexto ajuda.

---

## Parte 7 — Como mandar o resultado

### Me mande

**Do seu PC (convidado):**
- o arquivo `bin64\cdmp.log`
- **uma foto do painel**, com a linha `Other player:` visível

**O anfitrião manda o log dele.**

### E responda em uma frase cada

1. Apareceu **`connected`**? Nos **dois**?
2. **Alguém viu o boneco do outro?** Quem viu o quê?
3. Os inimigos do anfitrião apareceram no **seu** mundo?
4. Você conseguiu **pegar loot**?

---

## Resumo em 8 linhas

```
1. Backup da pasta %LOCALAPPDATA%\Pearl Abyss\CD\save
2. Conferir a versão: tem que ser 1.0.0.3460
3. Ser amigo do anfitrião na Steam
4. Fechar o jogo
5. Copiar 3 arquivos para bin64   (cdmp.asi, cdmp.ini, dinput8.dll)
6. RENOMEAR dinput8.dll -> winmm.dll
7. Não editar o cdmp.ini (já vem pronto, role=guest)
8. Esperar o anfitrião abrir, depois abrir, ir ao mesmo lugar, F8, olhar
```
