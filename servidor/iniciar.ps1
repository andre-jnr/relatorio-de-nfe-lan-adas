# Sobe o Relatório de notas em modo produção e o mantém no ar.
# É chamado pela tarefa agendada criada por instalar.ps1 (conta SYSTEM, ao ligar o computador).
# Se o processo cair, reinicia sozinho. Se a porta estiver ocupada, registra no log e para.

$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$python = Join-Path $raiz ".venv\Scripts\python.exe"
$pastaLogs = Join-Path $raiz "logs"
$log = Join-Path $pastaLogs "servidor.log"
$PORTA_OCUPADA = 3   # mesmo código de app.py

New-Item -ItemType Directory -Force $pastaLogs | Out-Null
Set-Location $raiz
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUNBUFFERED = "1"

function Registrar($msg) {
    Add-Content -Path $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  [iniciar] $msg" -Encoding UTF8
}

while ($true) {
    # Log com no máximo ~5 MB: o anterior vira servidor.log.old
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 5MB) {
        Move-Item $log "$log.old" -Force
    }
    Registrar "Iniciando o relatório"
    $inicio = Get-Date
    cmd /c "`"$python`" app.py --producao >> `"$log`" 2>&1"
    $codigo = $LASTEXITCODE

    if ($codigo -eq $PORTA_OCUPADA) {
        Registrar "Porta em uso por outro programa. O relatório NÃO foi iniciado. Libere a porta e rode: Start-ScheduledTask 'Relatorio de notas (3003)'"
        exit $codigo
    }
    # Se caiu logo depois de subir (ex.: erro no .env), espera mais para não encher o log
    $espera = if (((Get-Date) - $inicio).TotalSeconds -lt 60) { 60 } else { 10 }
    Registrar "O relatório parou (código $codigo). Reiniciando em $espera s."
    Start-Sleep -Seconds $espera
}
