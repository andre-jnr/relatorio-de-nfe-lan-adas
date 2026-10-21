# Tabelas do SISMOURA — referência

Esquema conferido no banco do Parque Dez em 08/10/2026. As outras lojas usam o mesmo sistema.

## Mapa de relacionamentos

```
Venda.Codigo                    ← Venda_Item.Venda
Venda_Item.Produto              → Produto.Codigo
Venda.PDV                       → PDV.Codigo
Produto.Grupo                   → Grupo_Produto.Codigo
Produto.SubGrupo                → SubGrupo.Codigo
Produto.Marca                   → Marca.Codigo
Fiscal_NF.Codigo                ← Fiscal_NFe.Codigo_Fiscal_NF
Contas_Pagar.Conta_Contabil     → Conta_Contabil.Codigo
Contas_Pagar.Codigo_Fornecedor  → Pessoa.Codigo   (nome em Pessoa.Nome; Fornecedor.Pessoa = Pessoa.Codigo)
Contas_Pagar.Codigo_Entrada     → Entrada_Produto.Chave
Entrada_Produto.Chave           ← Entrada_Produto_Itens.Chave
Entrada_Produto_Itens.Codigo_Produto → Produto.Codigo
Movimentacao.Codigo             ← Movimentacao_Item.Movimentacao
Movimentacao_Item.Motivo        → Mov_Desc.Codigo
Movimentacao_Item.Produto       → Produto.Codigo
```

## Valores de status (Parque Dez)

| Campo | Valores |
|---|---|
| `Venda.Cancelada`, `Venda_Item.Cancelado` | `N` (válida) / `S` (cancelada) |
| `Contas_Pagar.Pago` | `S` / `N` |
| `Contas_Pagar.Conta_Corrente` | **varchar**. `'2'` = Transferência. Compare como texto: `= '2'` |
| `Fiscal_NFe.Situacao` | AUTORIZADA, CANCELADA, REJEITADA, DENEGADA, INUTILIZADA, IMPRESSA, CADASTRADA, TRANSMITIDA, ASSINADA, AGUARDANDO |
| `Mov_Desc.E_S` | `E` (entrada) / `S` (saída) |
| `Fiscal_NF.CFOP` (transferências) | `5.152` transf. mercadoria · `5.409` transf. com ST · `5.552` transf. ativo imobilizado · `5.557` transf. material de uso/consumo |

---

## Vendas

```sql
-- cabeçalho
SELECT Codigo, Data, PDV, Valor_Final
FROM Venda
WHERE Cancelada = 'N'
  AND Data >= '2026-09-01' AND Data < '2026-10-01';

-- itens
SELECT Venda, Produto, Quantidade, Valor_Total
FROM Venda_Item
WHERE Cancelado = 'N';
```
Outras colunas úteis em `Venda`: `Valor` (bruto), `Desconto`, `Acrescimo`, `Valor_Dinheiro`, `Valor_Cartao_Credito`, `Valor_Cartao_Debito`, `Valor_Pix`, `Itens`, `Operador`, `Caixa`, `Cliente`, `CPF_Cliente`.
Outras colunas úteis em `Venda_Item`: `Valor_Unitario`, `Valor_Custo`, `Desconto`, `Item`.

**Faturamento por dia:**
```sql
SELECT CAST(Data AS date) AS Dia, COUNT(*) AS Cupons, SUM(Valor_Final) AS Faturamento,
       SUM(Valor_Final) / NULLIF(COUNT(*),0) AS Ticket_Medio
FROM Venda
WHERE Cancelada = 'N' AND Data >= '2026-09-01' AND Data < '2026-10-01'
GROUP BY CAST(Data AS date) ORDER BY Dia;
```

**Vendas por grupo de produto:**
```sql
SELECT g.Descricao AS Grupo, SUM(i.Quantidade) AS Qtde, SUM(i.Valor_Total) AS Total
FROM Venda v
JOIN Venda_Item i ON i.Venda = v.Codigo AND i.Cancelado = 'N'
JOIN Produto p ON p.Codigo = i.Produto
LEFT JOIN Grupo_Produto g ON g.Codigo = p.Grupo
WHERE v.Cancelada = 'N' AND v.Data >= '2026-09-01' AND v.Data < '2026-10-01'
GROUP BY g.Descricao ORDER BY Total DESC;
```

## Fiscal — NF de transferência emitidas

```sql
SELECT nf.CFOP, nf.Codigo, nf.Total_NF, nf.Data_Emissao, nfe.Situacao
FROM Fiscal_NF nf
LEFT JOIN Fiscal_NFe nfe ON nfe.Codigo_Fiscal_NF = nf.Codigo
WHERE nf.CFOP IN ('5.152','5.409','5.557','5.552')
  AND nf.Data_Emissao >= '2026-09-01' AND nf.Data_Emissao < '2026-10-01';
-- só as válidas: AND nfe.Situacao = 'AUTORIZADA'
```
Colunas úteis: `Nome` (destinatário), `CPF_CGC`, `Numero`, `Serie`, `Total_Produtos`, `Cancelada`, `Codigo_Movimentacao`; em `Fiscal_NFe`: `Chave_Acesso`, `NF`, `Data_Autorizacao`.

## NFe (cabeçalho)

```sql
SELECT Codigo_Fiscal_NF, Situacao FROM Fiscal_NFe;
```

## Contas pagas

```sql
SELECT
    Codigo, Data_Emissao, Data_Pagamento, Data_Vencimento, Pago, Valor_Pago, Valor,
    Conta_Contabil, Conta_Corrente, Codigo_Fornecedor, Observacao,
    CASE
        WHEN Conta_Corrente = '2' THEN 'Transferência'
        WHEN YEAR(Data_Emissao) = YEAR(Data_Pagamento) AND MONTH(Data_Emissao) = MONTH(Data_Pagamento) THEN 'Mesmo Mês'
        WHEN DATEFROMPARTS(YEAR(Data_Emissao), MONTH(Data_Emissao), 1)
           < DATEFROMPARTS(YEAR(Data_Pagamento), MONTH(Data_Pagamento), 1) THEN 'Meses Anteriores'
        ELSE 'Outros'
    END AS Origem_Contas_Pagas
FROM Contas_Pagar
WHERE Pago = 'S'
  AND Data_Pagamento >= '2026-09-01' AND Data_Pagamento < '2026-10-01';
```
Colunas úteis: `Juros`, `Desconto`, `Parcela`, `N_Doc_Merc`, `Codigo_Entrada` (entrada de nota de origem), `Data_Exclusao` (se preenchida, a conta foi excluída: filtre `Data_Exclusao IS NULL`).

**Pago por conta contábil, com nome do fornecedor disponível:**
```sql
SELECT cc.Codigo, cc.Descricao, SUM(cp.Valor_Pago) AS Total_Pago, COUNT(*) AS Titulos
FROM Contas_Pagar cp
LEFT JOIN Conta_Contabil cc ON cc.Codigo = cp.Conta_Contabil
WHERE cp.Pago = 'S' AND cp.Data_Exclusao IS NULL
  AND cp.Data_Pagamento >= '2026-09-01' AND cp.Data_Pagamento < '2026-10-01'
GROUP BY cc.Codigo, cc.Descricao ORDER BY Total_Pago DESC;
-- nome do fornecedor: LEFT JOIN Pessoa pe ON pe.Codigo = cp.Codigo_Fornecedor → pe.Nome
```

## Contas contábeis

```sql
SELECT Codigo, Descricao FROM Conta_Contabil;
```
Colunas úteis: `Cod_Contabil` (classificação), `Sintetico`, `Nivel`, `Inativa`, `Tipo_Conta`.

## Entrada de produtos (notas de entrada)

```sql
SELECT Data_Cadastro, Data_Emissao, Data_Entrada, Nota_Fiscal, Valor_Produtos,
       Chave,        -- PK, liga com Entrada_Produto_Itens.Chave
       Chave_NFE     -- chave de acesso da NF-e (44 dígitos)
       -- , Conteudo_Arquivo_Xml   ← pesado, só quando pedirem o XML
FROM Entrada_Produto
WHERE Data_Cadastro >= '2026-08-01' AND Data_Cadastro < '2026-09-01';
```
Colunas úteis: `Codigo_Fornecedor`, `Nome_Fornecedor` (já vem na tabela), `Valor_Nota`, `Valor_ICMS`, `Valor_Subst`, `Valor_IPI`, `Valor_Frete`, `Desconto`, `CFOP`.

## Entrada de produtos (itens)

```sql
SELECT Chave, Codigo_Produto, NCM, Quantidade, Quantidade_Cx, Valor_Unitario, Valor_Total
FROM Entrada_Produto_Itens;
```
Colunas úteis: `Custo`, `Custo_Sem_Imposto`, `ICMS_ST`, `Valor_IPI`, `CFOP`, `CST`.

**Compras por produto no mês:**
```sql
SELECT p.Codigo, p.Nome, SUM(i.Quantidade) AS Qtde, SUM(i.Valor_Total) AS Total
FROM Entrada_Produto e
JOIN Entrada_Produto_Itens i ON i.Chave = e.Chave
JOIN Produto p ON p.Codigo = i.Codigo_Produto
WHERE e.Data_Entrada >= '2026-09-01' AND e.Data_Entrada < '2026-10-01'
GROUP BY p.Codigo, p.Nome ORDER BY Total DESC;
```

## Produtos e cadastros

```sql
SELECT
    Codigo,
    Nome,
    Grupo,
    SubGrupo,
    Marca,
    Familia,
    Preco_Custo,
    Preco_Produto,                                   -- preço de venda
    Margem AS Markup,                                -- markup % sobre o custo, gravado pelo sistema
    CAST((Preco_Produto - Preco_Custo) / NULLIF(Preco_Produto, 0) * 100
         AS decimal(10,2)) AS Margem,                -- margem % sobre a venda
    Unidade,
    Data_Vigencia,                                   -- vigência do preço atual
    Data_Ult_Compra
FROM Produto;

SELECT Codigo, Descricao FROM Grupo_Produto;
SELECT Codigo, Descricao FROM SubGrupo;
SELECT Codigo, Nome FROM Marca;
```

**Markup × Margem:** use estes nomes ao responder o usuário.
- `Produto.Margem` no banco é **markup**: `(Venda − Custo) / Custo × 100`. Exemplo: custo 14,12 e venda 19,90 dão markup 40,93.
- **Margem** é calculada: `(Venda − Custo) / Venda × 100`. No mesmo exemplo, dá 29,05.
- Sempre use `NULLIF(Preco_Produto, 0)` no divisor, porque há produto com preço de venda zero.
- O markup gravado pode estar desatualizado quando o preço foi alterado fora do fluxo normal. No Parque Dez há produto com custo 15,51, venda 0,63 e `Margem` = 0. Se a análise exigir precisão, recalcule: `(Preco_Produto - Preco_Custo) / NULLIF(Preco_Custo, 0) * 100`.
- Para achar preços abaixo do custo: `WHERE Preco_Produto < Preco_Custo`.

Outras colunas úteis em `Produto`: `Codigo_Barra`, `Custo_Medio`, `Custo_Ult_Compra`, `Preco_Promocao`, `Quantidade` (estoque), `NCM`, `Inativo` (`'S'` = inativo, filtre `ISNULL(Inativo,'N') <> 'S'`), `Data_Ultima_Venda`, `Data_Cadastro`.

**Produtos com nomes de grupo, subgrupo e marca:**
```sql
SELECT p.Codigo, p.Nome, g.Descricao AS Grupo, s.Descricao AS SubGrupo, m.Nome AS Marca,
       p.Preco_Custo, p.Preco_Produto, p.Margem AS Markup,
       CAST((p.Preco_Produto - p.Preco_Custo) / NULLIF(p.Preco_Produto, 0) * 100 AS decimal(10,2)) AS Margem,
       p.Unidade, p.Data_Vigencia, p.Data_Ult_Compra
FROM Produto p
LEFT JOIN Grupo_Produto g ON g.Codigo = p.Grupo
LEFT JOIN SubGrupo s      ON s.Codigo = p.SubGrupo
LEFT JOIN Marca m         ON m.Codigo = p.Marca
WHERE ISNULL(p.Inativo, 'N') <> 'S';
```
A tabela `Familia` existe mas não tem colunas no Parque Dez, então use apenas o código `Produto.Familia`.

## Movimentações de estoque

```sql
SELECT Codigo, Data FROM Movimentacao;

SELECT Movimentacao, Motivo, Produto, Qtde, Preco_Custo,
       (Qtde * Preco_Custo) AS Total_Custo, Preco_Venda
FROM Movimentacao_Item;

SELECT Codigo, Descricao, E_S FROM Mov_Desc;   -- motivo da movimentação
```

**Movimentações por motivo no mês:**
```sql
SELECT md.Codigo, md.Descricao, md.E_S, COUNT(*) AS Itens,
       SUM(mi.Qtde) AS Qtde, SUM(mi.Qtde * mi.Preco_Custo) AS Total_Custo
FROM Movimentacao m
JOIN Movimentacao_Item mi ON mi.Movimentacao = m.Codigo
LEFT JOIN Mov_Desc md ON md.Codigo = mi.Motivo
WHERE m.Data >= '2026-09-01' AND m.Data < '2026-10-01'
  AND ISNULL(m.Cancelada,'N') <> 'S'
GROUP BY md.Codigo, md.Descricao, md.E_S ORDER BY Total_Custo DESC;
```
Motivos (Parque Dez) relevantes: 30 PRODUTOS VENCIDOS E AVARIADOS (S), 35 AVARIA (E), 27 CONTAGEM DE ESTOQUE (E), 11 COMPRAS (E), 12 SAIDA P/ COZINHA (S), 17 CENTRO DE DISTRIBUIÇÃO (S), 21 TRANSFERENCIA CD (E), 26 BONIFICAÇÃO (E). Os códigos mudam entre lojas, então consulte `Mov_Desc` em cada uma.
