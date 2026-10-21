# Remove a inicialização automática do Relatório de notas (tarefa agendada e regra de firewall).
# NÃO apaga dados (dados\), .env, .venv nem logs.
# Rode como Administrador:  clique duas vezes em servidor\desinstalar.bat

$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$pythonVenv = Join-Path $raiz ".venv\Scripts\python.exe"
$iniciar = Join-Path $PSScriptRoot "iniciar.ps1"

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host "ERRO: rode como Administrador." -ForegroundColor Red; exit 1 }

# Só as tarefas que apontam para o iniciar.ps1 DESTA pasta
$tarefas = Get-ScheduledTask -TaskName "Relatorio de notas (*)" -ErrorAction SilentlyContinue |
    Where-Object { $_.Actions.Arguments -like "*$iniciar*" }
foreach ($t in $tarefas) {
    Stop-ScheduledTask -TaskName $t.TaskName
    Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false
    Get-NetFirewallRule -DisplayName $t.TaskName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host "Removidos: tarefa e regra de firewall '$($t.TaskName)'" -ForegroundColor Green

    # Encerra o relatório se ainda estiver rodando: laço do iniciar.ps1, lançador do .venv e o Python na porta
    $porta = [int]($t.TaskName -replace "\D", "")
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*$iniciar*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
        Where-Object { $_.ExecutablePath -eq $pythonVenv } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    $con = Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($con) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId = $($con.OwningProcess)"
        if ($proc.CommandLine -like "*app.py*--producao*") {
            Stop-Process -Id $proc.ProcessId -Force
            Write-Host "Relatório encerrado (porta $porta liberada)"
        }
    }
}
if (-not $tarefas) { Write-Host "Nenhuma tarefa 'Relatorio de notas' instalada para esta pasta." }
