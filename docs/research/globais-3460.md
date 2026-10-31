# Os quatro globais restantes do 3460 — medidos, e o que o resultado significa

**Data:** 2026-10-31, build `687d30ec`. Jogo aberto, save carregado, personagem andando.
Sonda: `game::diag::probe_globals`, que varre `[0x70C0000, 0x71D0000)` identificando cada
global por uma propriedade que só o objeto real possui.

---

## Resultado: zero candidatos em quatro categorias

```
Global probe: reference position (-20717.33, 620.17, -6914.66)
Global probe: 0 position, 0 camera, 0 minimap, 0 clockbias candidate(s)
```

A posição de referência é **válida** — é a mesma que o mod leu da cadeia do ator, confirmada
por movimento em rodada anterior. Então a varredura teve contra o que comparar.

**Isto não é falha da sonda.** Verificado: leituras diretas na faixa funcionam
(`0x71B5CF0` devolve um ponteiro vivo, `0x71B1A40` devolve o `GlobalVariableManager`).
A varredura percorreu a faixa e nada satisfez os critérios.

## O que cada endereço contém hoje

| global | endereço | valor lido | veredito |
|---|---|---|---|
| `kCameraSlot` | `0x70CDEA8` | `"common.v"` (texto UTF-16) | ❌ é uma string |
| `kMinimapIconRoot` | `0x71B1DD8` | `0xFFFF` | ❌ não é ponteiro |
| `kMinimapIconRootAlt` | `0x71B1DE0` | `0x0` | ❌ nulo |
| `kClientFrameClockMs` | `0x70CDCE1` | `0xB000000000000200` | ❌ lixo |
| `kStaticPlayerPos` | `0x71C0C20` | dois ponteiros | ❌ não são floats |

**Nenhum está "deslocado".** Não existe um delta a aplicar: os objetos de sistema **saíram
daquela faixa**. Onde o 3446 guardava o mundo do jogo, o 3460 guarda strings de configuração,
tabelas de flags e outros dados.

Isto é o mesmo fenômeno que já apareceu em `kWorldSystemSlot`, onde `0x71B1A40` passou a
conter um `GlobalVariableManager`. Confirma que **não é um deslocamento global da seção de
dados** — é reorganização de conteúdo.

## Um detalhe que vale registrar

O clock tem um byte de desalinhamento visível:

```
0x70CDCE8: 0x2748813B0
0x70CDCE9: 0x0002748813      <-- o valor que o mod lê
```

O contador de microssegundos começa em `0x70CDCE8`, não `0x70CDCE9`. O mod lê um byte
deslocado e por acaso obtém um número que **passa** na sua própria guarda (`< 1e9`). É o tipo
de erro que sobrevive a uma verificação porque a verificação foi escrita contra o valor certo
lido do lugar errado.

## Por que isto é aceitável, e o que quebra

Os três primeiros consumidores **falham fechado**:

- `camera_reader` exige um **sentinel float** exato dentro do bloco. Com o slot errado, a
  leitura nem chega lá: a primeira coisa é `read_ptr(0x70CDEA8)`, que devolve o texto
  interpretado como ponteiro e falha. O resultado é `no camera`, não uma câmera errada.
- `game_clock` tem quatro guardas em série (dentro da imagem, `ms != 0`, `ms` abaixo de um ano,
  `us < 1e9`) e devolve `nullopt` se qualquer uma falhar. O recurso desliga.
- `puppet_minimap` simplesmente não desenha o ícone.

**O que se perde:** a câmera do convidado (usada para orientar o boneco remoto), a sincronia
de tempo entre host e convidado, e o ícone do amigo no minimapa.

**O que NÃO se perde:** posição, vida, stamina, rotação do ator, e todo o caminho de rede.
O `Local player: in world` com posição correta continua funcionando — verificado nesta rodada
com o personagem andando.

## O controle que o objetivo pedia

`kStaticPlayerPos` era o controle nomeado: a posição derivada da cadeia comparada com um
segundo global. **Ele não pode exercer esse papel no 3460** enquanto estiver errado, e a sonda
mostra que o valor correto não está na faixa antiga.

O que substitui esse controle, e é mais forte: **verificação por movimento**. Duas leituras
com o personagem andando têm de diferir na direção do deslocamento. Foi assim que
`inner+0x460` foi provado:

```
leitura 1: (-20549.8086, 587.6920, -6922.1904)
leitura 2: (-20517.7422, 579.1594, -6952.5029)     ~45 m
```

Um endereço errado não acompanha o personagem. Isso não depende de nenhum segundo global estar
certo, então é imune à falha que derrubou o controle original.

## Próximo passo, se estes recursos voltarem a importar

Não é "aplicar um delta" nem "varrer mais". É **localizar cada objeto pelo seu construtor**:
achar a função que escreve no slot no 3446 e reencontrá-la no 3460 pelo prólogo. Um escritor é
mais estável que um leitor, e o endereço escrito está na instrução.

Alternativa mais barata, e provavelmente melhor: **descobrir se o 3460 ainda tem esses objetos
e onde**, varrendo a heap pelos nomes RTTI (`MinimapIcon`, `Camera`), do mesmo modo que o
`ClientActorManager` foi encontrado. Se os objetos existem, o slot que os referencia é
encontrável por quem aponta para eles.

O que **não** deve ser tentado de novo: assumir que `.data` não se moveu porque alguns
endereços ainda têm xrefs. Foi esse raciocínio que produziu a conclusão errada na rodada
anterior, e o número de xrefs era idêntico nos dois builds.
