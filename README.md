# Relatório de notas por dia

Relatório diário das notas de entrada: **lançadas** no SISMOURA (lidas direto do banco, somente leitura), **a lançar** e **pendentes** (cadastradas na tela ou importadas por XML/ZIP de NF-e). Exporta para Excel e PDF.

- Porta padrão: **3003** (variável `PORT`)
- Python 3 + Flask, SQL Server via ODBC Driver 17, SQLite local em `dados/relatorio.db`

## Instalação

```bash
pip install -r requirements.txt
copy .env.example .env      # e preencha com as credenciais
python app.py               # ou: Abrir relatório.bat
```

Parâmetro `--sem-navegador` impede abrir o navegador ao iniciar (útil no servidor).

## Configuração (`.env`)

O `.env` guarda **todas** as credenciais e servidores. Ele **não vai para o git**; o modelo sem valores é o `.env.example`.

| Variável | O que faz |
| --- | --- |
| `PORT` | Porta web (padrão 3003) |
| `HOST` | `127.0.0.1` = só a própria máquina · `0.0.0.0` = rede interna |
| `LOJAS_PERMITIDAS` | `todas` ou lista: `parque10, pontanegra, moradadosol, monte, cd, flores` |
| `SISMOURA_USUARIO` / `SISMOURA_SENHA` / `SISMOURA_DRIVER` | Acesso padrão ao SQL Server |
| `<LOJA>_SERVIDOR` / `<LOJA>_BANCO` | Servidor e banco de cada loja (loja sem servidor fica desativada) |
| `<LOJA>_USUARIO` / `<LOJA>_SENHA` | Opcional: credencial própria da loja (ex.: Flores) |

### Restringir um servidor a uma loja

Exemplo para o servidor da **Ponta Negra** — o faturista de lá só vê e altera notas da Ponta Negra:

```ini
PORT=3003
HOST=0.0.0.0
LOJAS_PERMITIDAS=pontanegra

SISMOURA_DRIVER=ODBC Driver 17 for SQL Server
SISMOURA_USUARIO=...
SISMOURA_SENHA='...'
PONTANEGRA_SERVIDOR=...
PONTANEGRA_BANCO=...
```

Coloque no `.env` de cada servidor **apenas** as credenciais das lojas que ele pode ver: assim, mesmo que alguém mexa no código, a senha das outras lojas nem está na máquina.

Com a restrição ativa:
- o filtro "Todas as lojas" some e a API só consulta as lojas liberadas;
- notas a lançar/pendentes de outras lojas não aparecem nem podem ser editadas/excluídas;
- XMLs importados destinados a outra loja são ignorados (aparecem no aviso da importação). XML sem loja reconhecida entra na loja do servidor.
- Obs.: a Flores também recebe notas no CNPJ 0001-30 (Parque Dez). Num servidor só da Flores, escolha "Flores" no seletor de loja da importação para essas notas.

## Backup e migração de servidor

As notas lançadas vêm do SISMOURA; o que só existe neste sistema são as notas **a lançar** e **pendentes** (`dados/relatorio.db`).

No botão de engrenagem (canto do topo) → **Backup dos dados**:
- **Exportar** baixa `backup-notas-AAAA-MM-DD-HHMM.json` com todas as notas das lojas deste servidor.
- **Importar** soma as notas do arquivo às atuais: nada é apagado, notas repetidas e de lojas que o servidor não acessa são ignoradas. Antes, uma cópia do banco é salva em `dados/backups/`.

Para mudar de servidor: exporte no antigo, suba o sistema no novo e importe o arquivo.

## Proteger o `.env` no servidor (Windows)

Deixe o arquivo legível só pelo administrador e pela conta que roda o sistema:

```bat
icacls .env /inheritance:r /grant:r "%USERNAME%:F" /grant:r "*S-1-5-32-544:F"
```

Se o sistema rodar como serviço com outra conta, inclua-a: `/grant:r "NOME_DA_CONTA:R"`.

## O que nunca vai para o git

Ver `.gitignore`: `.env`, `dados/` (banco local com notas reais), planilhas/XML/ZIP exportados, `__pycache__`, ambientes virtuais.
