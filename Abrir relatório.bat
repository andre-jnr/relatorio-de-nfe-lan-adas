@echo off
title Relatorio de notas do dia
cd /d "%~dp0"
echo Abrindo o relatorio (porta definida no .env)  - feche esta janela para encerrar
python app.py
pause
