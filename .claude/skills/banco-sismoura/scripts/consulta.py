"""Executa consultas SOMENTE LEITURA nos bancos SISMOURA (SQL Server).

Exemplos:
  python consulta.py --listar-lojas
  python consulta.py --loja parque10 --sql "SELECT TOP 10 * FROM Venda"
  python consulta.py --loja todas --arquivo vendas.sql --saida vendas.csv
  python consulta.py --loja cd --descrever Entrada_Produto
  python consulta.py --loja cd --tabelas
"""
import argparse
import csv
import os
import re
import sys
from datetime import date, datetime
from decimal import Decimal
from pathlib import Path

import mssql_python  # driver oficial da Microsoft: não precisa de ODBC Driver instalado no Windows
from dotenv import load_dotenv

# Credenciais e servidores ficam no .env da raiz do projeto (fora do git). Modelo: .env.example
ENV = Path(__file__).resolve().parents[4] / ".env"

LOJAS = {
    "parque10": "Parque Dez",
    "pontanegra": "Ponta Negra",
    "moradadosol": "Morada do Sol",
    "monte": "Monte das Oliveiras",
    "cd": "CD",
    "flores": "Flores",
}

PROIBIDOS = re.compile(
    r"\b(INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE|TRUNCATE|EXEC|EXECUTE|GRANT|REVOKE|DENY|"
    r"BACKUP|RESTORE|SHUTDOWN|KILL|DBCC|SP_\w+|XP_\w+|INTO)\b",
    re.IGNORECASE,
)


def carregar_config():
    """Monta a configuração a partir do .env. Só entram as lojas com <LOJA>_SERVIDOR preenchido;
    <LOJA>_USUARIO / <LOJA>_SENHA sobrescrevem SISMOURA_USUARIO / SISMOURA_SENHA."""
    load_dotenv(ENV)
    cfg = {
        "usuario": os.getenv("SISMOURA_USUARIO", ""),
        "senha": os.getenv("SISMOURA_SENHA", ""),
        "lojas": {},
    }
    for id_, nome in LOJAS.items():
        p = id_.upper()
        if not os.getenv(f"{p}_SERVIDOR"):
            continue
        l = {"nome": nome, "servidor": os.getenv(f"{p}_SERVIDOR"), "banco": os.getenv(f"{p}_BANCO", "sismoura")}
        for campo in ("usuario", "senha"):
            if os.getenv(f"{p}_{campo.upper()}"):
                l[campo] = os.getenv(f"{p}_{campo.upper()}")
        cfg["lojas"][id_] = l
    if not cfg["lojas"]:
        sys.exit(f"ERRO: nenhuma loja configurada. Crie {ENV} a partir do .env.example.")
    return cfg


def _protegido(valor):
    """Protege valores com ; ou } na string de conexão."""
    return "{" + str(valor).replace("}", "}}") + "}"


def remover_comentarios_e_strings(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\n]*", " ", sql)
    return re.sub(r"'(?:[^']|'')*'", "''", sql)


def validar_somente_leitura(sql):
    limpo = remover_comentarios_e_strings(sql)
    achado = PROIBIDOS.search(limpo)
    if achado:
        sys.exit(f"ERRO: comando bloqueado ('{achado.group(0)}'). Esta habilidade é somente leitura.")
    if not re.match(r"^\s*(SELECT|WITH)\b", limpo, re.IGNORECASE):
        sys.exit("ERRO: a consulta deve começar com SELECT ou WITH.")


def conectar(cfg, loja, timeout):
    l = cfg["lojas"][loja]
    cs = (
        f"Server={l['servidor']};Database={l['banco']};"
        f"UID={_protegido(l.get('usuario', cfg['usuario']))};PWD={_protegido(l.get('senha', cfg['senha']))};"
        "Encrypt=yes;TrustServerCertificate=yes"  # conexão criptografada (servidores usam certificado próprio)
    )
    conn = mssql_python.connect(cs, timeout=timeout, autocommit=False)  # timeout de login (s)
    conn.timeout = 600  # timeout de execução da consulta (s)
    return conn


def executar(cfg, loja, sql, timeout):
    conn = conectar(cfg, loja, timeout)
    try:
        cur = conn.cursor()
        cur.execute("SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED")  # não trava o sistema
        cur.execute(sql)
        colunas = [c[0] for c in cur.description]
        linhas = [list(r) for r in cur.fetchall()]
        return colunas, linhas
    finally:
        conn.rollback()
        conn.close()


def fmt(v):
    if v is None:
        return ""
    if isinstance(v, Decimal):
        return str(v)
    if isinstance(v, datetime):
        return v.strftime("%Y-%m-%d %H:%M:%S") if (v.hour or v.minute or v.second) else v.strftime("%Y-%m-%d")
    if isinstance(v, date):
        return v.strftime("%Y-%m-%d")
    s = str(v)
    return s if len(s) <= 80 else s[:77] + "..."


def imprimir(colunas, linhas, max_linhas):
    mostrar = linhas[:max_linhas]
    tab = [[str(c) for c in colunas]] + [[fmt(v) for v in r] for r in mostrar]
    larg = [max(len(r[i]) for r in tab) for i in range(len(colunas))]
    for n, r in enumerate(tab):
        print(" | ".join(v.ljust(larg[i]) for i, v in enumerate(r)))
        if n == 0:
            print("-+-".join("-" * w for w in larg))
    print(f"\n{len(linhas)} linha(s)" + (f" (exibindo {max_linhas})" if len(linhas) > max_linhas else ""))


def salvar(colunas, linhas, caminho):
    caminho = Path(caminho)
    caminho.parent.mkdir(parents=True, exist_ok=True)
    if caminho.suffix.lower() == ".xlsx":
        import pandas as pd
        pd.DataFrame(linhas, columns=colunas).to_excel(caminho, index=False)
    else:
        with open(caminho, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f, delimiter=";")
            w.writerow(colunas)
            for r in linhas:
                w.writerow(["" if v is None else str(v).replace(".", ",") if isinstance(v, (Decimal, float)) else v
                            for v in r])
    print(f"Salvo em: {caminho.resolve()}")


def main():
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Consultas somente leitura no SISMOURA")
    p.add_argument("--loja", help="parque10 | pontanegra | moradadosol | monte | cd | flores | todas | lista separada por vírgula")
    p.add_argument("--sql", help="consulta SQL (SELECT/WITH)")
    p.add_argument("--arquivo", help="arquivo .sql com a consulta")
    p.add_argument("--saida", help="salvar resultado em .csv (separador ;) ou .xlsx")
    p.add_argument("--max-linhas", type=int, default=50, help="linhas exibidas no terminal (padrão 50)")
    p.add_argument("--timeout", type=int, default=30, help="timeout de conexão em segundos")
    p.add_argument("--descrever", metavar="TABELA", help="lista colunas e tipos de uma tabela")
    p.add_argument("--tabelas", nargs="?", const="", metavar="FILTRO", help="lista tabelas (filtro opcional por nome)")
    p.add_argument("--listar-lojas", action="store_true")
    a = p.parse_args()

    cfg = carregar_config()
    if a.listar_lojas:
        for k, l in cfg["lojas"].items():
            print(f"{k:12} {l['nome']:22} {l['servidor']:18} {l['banco']}")
        return

    if not a.loja:
        p.error("informe --loja")
    lojas = list(cfg["lojas"]) if a.loja == "todas" else [x.strip() for x in a.loja.split(",")]
    for l in lojas:
        if l not in cfg["lojas"]:
            sys.exit(f"ERRO: loja '{l}' desconhecida. Use --listar-lojas.")

    if a.descrever:
        nome = a.descrever.replace("'", "''")
        sql = ("SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH AS TAMANHO, IS_NULLABLE "
               f"FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = '{nome}' ORDER BY ORDINAL_POSITION")
    elif a.tabelas is not None:
        filtro = a.tabelas.replace("'", "''")
        sql = ("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE' "
               f"AND TABLE_NAME LIKE '%{filtro}%' ORDER BY TABLE_NAME")
    elif a.arquivo:
        sql = Path(a.arquivo).read_text(encoding="utf-8")
    elif a.sql:
        sql = a.sql
    else:
        p.error("informe --sql, --arquivo, --descrever ou --tabelas")

    validar_somente_leitura(sql)

    todas_colunas, todas_linhas, multi = None, [], len(lojas) > 1
    for loja in lojas:
        nome = cfg["lojas"][loja]["nome"]
        try:
            colunas, linhas = executar(cfg, loja, sql, a.timeout)
        except mssql_python.Error as e:
            print(f"[{nome}] ERRO: {e}", file=sys.stderr)
            continue
        print(f"[{nome}] {len(linhas)} linha(s)", file=sys.stderr)
        if multi:
            colunas = ["Loja"] + colunas
            linhas = [[nome] + r for r in linhas]
        todas_colunas = todas_colunas or colunas
        todas_linhas.extend(linhas)

    if todas_colunas is None:
        sys.exit(1)
    imprimir(todas_colunas, todas_linhas, a.max_linhas)
    if a.saida:
        salvar(todas_colunas, todas_linhas, a.saida)


if __name__ == "__main__":
    main()
