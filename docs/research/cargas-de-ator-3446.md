# O teto de 16 KB nas cargas de ator: medido em 13890 cargas

**Data:** 2026-10-31. **Captura:** `cdmp_packets_20261031-002813.bin`, 533.7 MB, PE `0x6AE46DD0`
(1.0.0.3446), feita com o personagem num **acampamento de bandidos**, gravada com `record=1`.

Este documento existe para encerrar uma dúvida que consumiu duas rodadas: *o `kMaxLoad = 16 KB`
é suficiente?* A resposta é **sim**, e agora ela vem de medição em escala, não de estimativa.

---

## 1. O resultado

1.540.403 pacotes na captura. **13890** são `ActorLoadDataAck` (opcode 2005). Nenhum truncado
pelo sniffer (`truncadas: 0`).

| tipo | cargas | o que é |
|---|---|---|
| 3 | 2188 | inimigo |
| 6 | 3664 | inimigo |
| 7 | 7794 | armas/gimmicks |
| 4 | 71 | companheiro/mercernário |
| 5 | 155 | veículo (o dragão é tipo 5) |
| 0 | 18 | — |

**5832 cargas tipo 3/6 — inimigos reais.** Tamanhos do payload:

| | bytes |
|---|---|
| menor | 6857 |
| **mediana** | **7648** |
| maior | **11997** |
| acima de 16384 | **0** |

`kMaxLoad = 16 * 1024` (`native_suppress.cpp:59`) e `kMaxLoadSize = 16 * 1024`
(`enemy_relay.cpp:1525`) ficam com **4387 bytes de folga** sobre a maior carga já observada.

---

## 2. O que isso fecha, e o que NÃO fecha

**Fecha:** a hipótese da rodada 48 — "o `kMaxLoad` está baixo e por isso o laboratório viu
0 natives". **Refutada.** Nenhuma carga de inimigo chega perto do teto.

**NÃO fecha:** por que o `Ctrl+Home` no laboratório reportou 0 natives. Essa pergunta volta a
estar aberta, e o contador `loads_seen` (`native_suppress.cpp`, incrementado antes de qualquer
filtro em `suppress_observe_s2c`) é o que vai respondê-la: ele distingue *"o sniffer não viu
carga nenhuma"* de *"viu N e recusou todas"*.

Os registros de 23 KB que assustaram numa leitura anterior são **todos tipo 7** (armas e
gimmicks), que o código já roteia separadamente — não passam pelo caminho dos inimigos.

---

## 3. Como o número foi obtido, e as quatro vezes em que ele esteve errado

O script é `scripts/ler-cargas.ps1`. Ele errou **quatro vezes**, e cada erro produziu um número
que parecia uma descoberta sobre o jogo. Estão todos registrados aqui porque a única razão de o
resultado final ser confiável é que cada erro foi confrontado com o arquivo cru.

### 3.1 Formato do arquivo (conferido, estável)

```
cabeçalho de 12 bytes: "CDPK" | u32 versão | u32 pe_timestamp

descritor de 24 bytes, por pacote:
  +0  u64  t_us
  +8  u8   dir      1 = ClientToServer, 2 = ServerToClient
  +9  u8   pad
  +10 u16  size
  +12 u16  copied
  +14 u16  pad
  +16 u32  session
  +20 u32  thread
  então copied bytes de payload

payload Troc (conferido em 13890/13890):
  +0  u16  opcode        2005 = ActorLoadDataAck
  +2  u8   slot
  +3  u16  len           len + 5 == copied
  +5  u8   —
  +6  u8   —
  +7  u8   type          3 / 6 = inimigo
```

A varredura do arquivo chega ao fim **exato** (diferença de 0 byte em 1.540.403 pacotes), o que
prova que o descritor de 24 bytes está certo.

### 3.2 Os quatro erros

| # | erro | o que o script disse | por que parecia verdade |
|---|---|---|---|
| 1 | filtro `$dir -eq 1` (o certo é 2) | "cargas vistas: 0" | lê-se como "o 3446 não manda cargas" |
| 2 | `type` lido em `+7` **do descritor** | tudo tipo 255 | lê-se como "o formato do fio mudou" |
| 3 | `$p = $off + 31` (off já avançou) | "0 cargas" | a mensagem impressa foi "o sniffer não vê cargas" |
| 4 | guarda de fim curta demais | script abortava | lê-se como "o analisador está quebrado" |

O erro 3 é o mais instrutivo: a linha 54 já tinha avançado `$off` pelos 24 bytes do descritor, e
o código somou 24 de novo. Com isso ele leu o **descritor do pacote seguinte**, nunca encontrou
o opcode 2005, contou 0, e imprimiu uma conclusão sobre o **jogo** gerada inteiramente por
aritmética errada no **analisador**.

O erro 4: o último registro da captura é **truncado** (o sniffer foi morto no meio da gravação,
`copied=25` com exatamente 25 bytes restantes). A leitura do `type` em `+7` passava 6 bytes do
fim do arquivo, e o PowerShell abortava com `ArgumentException` — sintoma que chega ao usuário
como "o script não roda", não como "o último pacote estava incompleto".

### 3.3 A regra que saiu disso

**Nenhum número deste script vale antes de uma conferência contra o arquivo cru.** A que fechou
o caso foi aritmética: `len(u16@+3) + 5 == copied` em **13890 de 13890**. Isso não depende do
script, do meu entendimento do formato, nem do código do mod — é o arquivo conferindo a si mesmo
contra a única previsão que o formato faz.

---

## 4. Como reproduzir

```powershell
# com uma captura gravada (cdmp.ini: record=1) e o jogo fechado:
powershell -ExecutionPolicy Bypass -File .\scripts\ler-cargas.ps1 -Bin <captura.bin>
```

O script **copia o arquivo antes de ler** (o jogo mantém o original aberto enquanto roda).
