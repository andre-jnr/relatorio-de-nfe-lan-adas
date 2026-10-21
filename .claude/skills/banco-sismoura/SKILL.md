---
name: banco-sismoura
description: Consulta (somente leitura) os bancos SQL Server do sistema SISMOURA das lojas Moura — Parque Dez, Ponta Negra, Morada do Sol, Monte das Oliveiras, CD e Flores. Use sempre que o usuário pedir dados do sistema - vendas, itens vendidos, faturamento, notas fiscais de transferência (NFe), contas pagas/a pagar, contas contábeis, entrada de notas/produtos, produtos/grupos/marcas, movimentações de estoque - ou pedir para extrair, comparar lojas, exportar para CSV/Excel ou descobrir tabelas/colunas do banco.
---

# Banco SISMOURA — extração de informações

Cada loja tem seu próprio banco SQL Server com o **mesmo esquema** (sistema SISMOURA). Credenciais, servidores e bancos ficam no `.env` da raiz do projeto (fora do git; modelo em `.env.example`). Nunca os repita em respostas, commits ou arquivos gerados. Para ver servidor/banco de cada loja, rode `--listar-lojas`.

| Apelido (`--loja`) | Loja |
|---|---|
| `parque10` | Parque Dez |
| `pontanegra` | Ponta Negra |
| `moradadosol` | Morada do Sol |
| `monte` | Monte das Oliveiras |
| `cd` | CD (centro de distribuição) |
| `flores` | Flores |

Flores é a única loja com credencial própria (`FLORES_USUARIO` / `FLORES_SENHA` no `.env`), e o script a usa automaticamente. É uma loja recente: tem pouco histórico (cerca de 8 mil vendas em out/2026) e só 9 motivos cadastrados em `Mov_Desc`.

O **CD não tem vendas de PDV** (a tabela `Venda` fica vazia). Lá interessam entradas, movimentações, transferências fiscais e contas pagas.

Se o usuário não disser a loja, pergunte, ou use `todas` quando o pedido for comparativo ou consolidado.

## Como consultar

Use sempre o script `scripts/consulta.py`, que roda Python + `mssql-python` (driver oficial da Microsoft, conexão criptografada, sem precisar de ODBC Driver instalado):

```bash
S=".claude/skills/banco-sismoura/scripts/consulta.py"

python $S --listar-lojas
python $S --loja parque10 --sql "SELECT TOP 10 Codigo, Data, Valor_Final FROM Venda ORDER BY Data DESC"
python $S --loja todas --arquivo consulta.sql --saida saida/vendas.xlsx   # várias lojas → coluna "Loja" é adicionada
python $S --loja parque10,cd --sql "..."                                   # lista de lojas
python $S --loja cd --tabelas Entrada                                     # descobrir tabelas por nome
python $S --loja cd --descrever Entrada_Produto                           # colunas e tipos
```

- `--saida` aceita `.csv` (separador `;`, decimal `,` e UTF-8 com BOM, pronto para o Excel BR) ou `.xlsx`.
- `--max-linhas N` limita só o que aparece no terminal; o arquivo de saída recebe tudo.
- Para SQL longo ou com aspas, grave um `.sql` no scratchpad e use `--arquivo`.
- **Morada do Sol** costuma demorar para conectar. O timeout padrão é 30 s; se falhar, use `--timeout 60`.
- Se uma loja falhar com `--loja todas`, as demais seguem e o erro sai no stderr. Avise o usuário sobre a loja que faltou.

## Regras

1. **Somente leitura.** O script só aceita `SELECT`/`WITH`, bloqueia comandos de escrita, roda em `READ UNCOMMITTED` (não trava o PDV) e faz rollback no fim. Nunca tente contornar essas proteções. Se o usuário pedir para alterar dados, recuse e explique o motivo.
2. **Bancos de produção, com milhões de linhas** (só `Venda` no Parque Dez tem cerca de 1,7 milhão). Sempre filtre por período (`WHERE Data >= '2026-09-01' AND Data < '2026-10-01'`), use `TOP` ao explorar e agregue no SQL (`GROUP BY`) em vez de trazer itens brutos.
3. Prefira intervalos de data (`>= início AND < fim`) a `MONTH()`/`YEAR()` na coluna, porque aproveitam os índices.
4. **Não traga colunas pesadas** (`Conteudo_Arquivo_Xml`, `XML_NFe`, `Json`, `Dados_Adicionais*`, `Observacao` do tipo text) sem necessidade.
5. Filtros padrão: vendas `Cancelada = 'N'`, itens `Cancelado = 'N'`, NFe válida `Situacao = 'AUTORIZADA'`.
6. Há datas digitadas erradas, como vendas em 2029 no Monte. Desconfie de `MAX(Data)` e filtre períodos plausíveis.
7. Cadastros como `Mov_Desc`, `Conta_Contabil` e `Grupo_Produto` são **por loja**. Os códigos podem significar coisas diferentes em cada banco. Ao consolidar lojas, faça o join dentro de cada banco (na mesma consulta) e não junte códigos entre lojas.
8. Ao apresentar resultados, mostre um resumo (totais e destaques) e salve o detalhe em arquivo quando passar de cerca de 50 linhas.

## Tabelas e relacionamentos

Leia [references/tabelas.md](references/tabelas.md) antes de montar consultas. O arquivo tem as consultas-base de cada área (vendas, fiscal, contas pagas, entradas, produtos, movimentações), as chaves de junção, os valores válidos dos campos de status e exemplos prontos.

Para qualquer tabela fora da lista, descubra com `--tabelas <filtro>` e `--descrever <Tabela>` antes de escrever o SQL. Não adivinhe nomes de colunas.
