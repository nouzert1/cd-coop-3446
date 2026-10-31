# O `kFieldTimeClient` nunca foi exercitado — ninguém sabe se está certo

Build 1.0.0.3446 (PE `0x6AE46DD0`). Investigação feita **com o jogo rodando e o mundo
carregado** (2026-10-30, pid 36596).

## Resumo

Depois de cinco rodadas tratando `kFieldTimeClient` como "pendência a resolver", a leitura
correta é outra: **é uma função que nunca foi ligada**. O endereço não pode estar certo nem
errado, porque nada nunca o leu.

## A sessão ao vivo

O mundo estava carregado de verdade. Controles lidos no mesmo processo e no mesmo instante:

| leitura | valor | o que prova |
|---|---|---|
| `kStaticPlayerPos` | `(-10679.82, 611.65, -3896.42)` | coordenadas reais, há sessão |
| `kClientClockGlobal` | `1` | flag de sessão ativa |
| HP do jogador (log do mod) | `1125.0/1125.0` | ator vivo e legível |
| `check vs game global` | `0.05 m` | a leitura do mod bate com a do jogo |

### E a leitura de posição foi confirmada de novo, sobre movimento real

A tabela acima tem uma amostra. Numa sessão posterior (2026-10-31, pid 12328) o mod foi
acompanhado por **596 m de caminhada contínua**, 15 amostras de `check vs game global`:

| medida | valor |
|---|---|
| mínimo | 0.04 m |
| máximo | 0.47 m |
| média | **0.084 m** |
| acima de 1 m | **0 de 15** |

Percorrer 596 m sem o erro crescer é o que torna isto uma confirmação e não uma coincidência:
um endereço errado que por acaso aponta para coordenadas parecidas **não acompanha o jogador**,
e o erro de um ponteiro desalinhado cresce com a distância percorrida em vez de ficar em
centímetros. `kStaticPlayerPos` segue o movimento e o erro fica constante, então a correção
(commit `270e2cc`) está verificada em uso, não só "lida uma vez".

Vale para `kStaticPlayerPos` e para o que depende dele. **Não** vale para `kFieldTimeClient`:
o bloco continua zerado e nada o lê (ver abaixo).

E o bloco em `0x6EB2AD8`: **32 bytes zerados**.

## Por que zero ali **não prova nada**

A tentação é concluir "o endereço mudou". Seria errado, e o log diz por quê:

```
Config: time sync off
```

**Está em todos os cinco logs rotacionados** desta máquina. A razão está no código:
`[coop] time_sync` tem **default 0** (`config.cpp:197`) e nenhum `cdmp.ini` o liga.

Ou seja: `own_time()` — a única função que lê esse endereço — **nunca foi chamada numa
sessão real**. Nada leu, nada escreveu, nada depende disso.

**Consequência prática:** um endereço velho aqui **não pode ter causado nada** que você
tenha visto. Não é um defeito a caçar; é uma função desligada.

## O que tentei e **não** funciona

Registrado para não se repetir:

- **`xrefs` em `0x6EB2AD0`-`0x6EB2B00`.** No 3424 caem em `exe+0x2ABFA9` e
  `exe+0x2ABF86/87/8D` — mas a função em volta é a **lista de nomes do logger** (o `lea`
  aponta para uma tabela de registro zerada, a mesma forma em `exe+0x2ABF83` nos dois
  builds, apontando para tabelas diferentes). **São do logger, não do FieldTime.** Lê-los
  como escritores de FieldTime manda o port atrás da função errada — foi o que me custou
  tempo nesta rodada.
- **Varrer a região procurando um timestamp.** O `.bss` ali tem ponteiros de vtable e
  sentinelas `0x7F...` de runtime. "Um u64 não-zero perto daqui" **não é evidência**.
- **`findptr` do endereço absoluto.** 0 resultados nos dois binários.

## Como resolver de verdade, quando quiser

1. Ligar no `cdmp.ini`: `[coop]` → `time_sync=1`
2. Entrar no mundo e **mover uma vez** (o mod exige movimento)
3. Rodar `diagnostico/check-fieldtime.ps1`

O script decide em um comando e **não escolhe** um veredito quando a evidência não permite:

| resultado | leitura |
|---|---|
| zerado | ainda indefinido — confirme que o mundo carregou antes de concluir que mudou |
| não-zero **com** timestamp | o valor herdado está **certo**, nada a fazer |
| não-zero **sem** timestamp | mudou de lugar, precisa remedir |

## Custo de deixar como está

`own_time()` lê duas vezes e compara; se não bater, retorna vazio. Perde-se a sincronia de
hora entre os dois jogadores e **nada mais**. Falha em segurança.

E como a função está desligada por default, esse custo é **zero** hoje.

## A lição que vale para o resto do port

Cinco rodadas ranquearam este endereço como "pendência". Não era. **Antes de tratar um
endereço como pendente, verifique se o código que o consome já rodou alguma vez.** Um
endereço não exercitado é indistinguível de um endereço certo — e é por isso que ele ficou
tanto tempo nessa lista sem ninguém conseguir dizer nada sobre ele.
