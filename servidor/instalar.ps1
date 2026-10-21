# Instala o Relatório de notas no servidor (Windows) para subir sozinho ao ligar o computador.
# Rode como Administrador:  clique duas vezes em servidor\instalar.bat
#
# O que faz:
#   1. confere o .env, o Python e o driver ODBC
#   2. cria o ambiente Python (.venv) e instala as dependências
#   3. confere se a porta está livre (se estiver ocupada por outro programa, para e avisa)
#   4. libera a porta no firewall só para a rede interna (perfis Domínio e Privado)
#   5. cria a tarefa agendada "Relatorio de notas (<porta>)" que roda servidor\iniciar.ps1 ao ligar
#   6. inicia o relatório e testa o acesso
# Pode ser rodado de novo (ex.: depois de atualizar o código): refaz tudo sem perder dados.

$ErrorActionPreference = "Stop"
$raiz = Split-Path $PSScriptRoot -Parent
$envArq = Join-Path $raiz ".env"
$venv = Join-Path $raiz ".venv"
$pythonVenv = Join-Path $venv "Scripts\python.exe"

function Passo($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "    OK  $msg" -ForegroundColor Green }
function Aviso($msg) { Write-Host "    !   $msg" -ForegroundColor Yellow }
function Falha($msg) { Write-Host "`nERRO: $msg" -ForegroundColor Red; exit 1 }

function Ler-Env($nome, $padrao) {
    $linha = Get-Content $envArq -Encoding UTF8 | Where-Object { $_ -match "^\s*$nome\s*=" } | Select-Object -Last 1
    if (-not $linha) { return $padrao }
    $valor = ($linha -split "=", 2)[1].Trim().Trim("'").Trim('"')
    if ($valor) { return $valor } else { return $padrao }
}

function Processo-Na-Porta($porta) {
    $con = Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($con) { Get-CimInstance Win32_Process -Filter "ProcessId = $($con.OwningProcess)" }
}

function Parar-Relatorio($porta) {
    # Para o laço do iniciar.ps1 deste projeto e o python que ele abriu (o do .venv abre o Python real como filho)
    $iniciar = Join-Path $PSScriptRoot "iniciar.ps1"
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*$iniciar*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
        Where-Object { $_.ExecutablePath -eq $pythonVenv } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    $proc = Processo-Na-Porta $porta
    if ($proc -and $proc.CommandLine -like "*app.py*--producao*") { Stop-Process -Id $proc.ProcessId -Force }
    Start-Sleep -Seconds 2
}

# ---------- 0. administrador ----------
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Falha "rode como Administrador (clique com o botão direito em instalar.bat > Executar como administrador)." }

# ---------- 1. configuração ----------
Passo "Conferindo o .env"
if (-not (Test-Path $envArq)) {
    Copy-Item (Join-Path $raiz ".env.example") $envArq
    Falha "não havia .env. Criei um a partir do .env.example em:`n  $envArq`nPreencha as credenciais e LOJAS_PERMITIDAS e rode a instalação de novo."
}
$porta = [int](Ler-Env "PORT" "3003")
$hostWeb = Ler-Env "HOST" "127.0.0.1"
$lojas = Ler-Env "LOJAS_PERMITIDAS" "todas"
$driver = Ler-Env "SISMOURA_DRIVER" "ODBC Driver 17 for SQL Server"
Ok "porta $porta · lojas: $lojas"
if ($hostWeb -eq "127.0.0.1" -or $hostWeb -eq "localhost") {
    Aviso "HOST=${hostWeb}: o relatório só abre NESTE computador. Para a rede interna acessar, use HOST=0.0.0.0 no .env."
}
$nomeTarefa = "Relatorio de notas ($porta)"

Passo "Conferindo o driver ODBC"
if (Get-OdbcDriver -Name $driver -Platform "64-bit" -ErrorAction SilentlyContinue) { Ok $driver }
else { Aviso "'$driver' não encontrado. Instale-o, senão o relatório não conecta no SISMOURA." }

# ---------- 2. Python ----------
Passo "Preparando o Python (.venv)"
if (-not (Test-Path $pythonVenv)) {
    $py = Get-Command py, python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike "*WindowsApps*" } | Select-Object -First 1
    if (-not $py) { Falha "Python não encontrado. Instale o Python 3 (python.org) marcando 'Add python.exe to PATH'." }
    & $py.Source -m venv $venv
    if ($LASTEXITCODE -ne 0) { Falha "não consegui criar o .venv." }
}
& $pythonVenv -m pip install --disable-pip-version-check -q -r (Join-Path $raiz "requirements.txt")
if ($LASTEXITCODE -ne 0) { Falha "falha ao instalar as dependências (requirements.txt)." }
Ok (& $pythonVenv --version)

# ---------- 3. porta ----------
Passo "Conferindo a porta $porta"
if (Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $nomeTarefa   # reinstalação: para a versão em execução
}
Parar-Relatorio $porta
$proc = Processo-Na-Porta $porta
if ($proc) {
    Falha "a porta $porta já está em uso por '$($proc.Name)' (PID $($proc.ProcessId)).`nNão troquei de porta: confira orientacoes-projetos-ia.md e libere a porta antes de instalar."
}
Ok "porta livre"

# ---------- permissões ----------
# A tarefa roda como SYSTEM: precisa ler o .env e gravar em dados\ e logs\
icacls $envArq /grant:r "*S-1-5-18:R" | Out-Null
foreach ($pasta in "dados", "logs") {
    $p = Join-Path $raiz $pasta
    New-Item -ItemType Directory -Force $p | Out-Null
    icacls $p /grant "*S-1-5-18:(OI)(CI)M" | Out-Null
}

# ---------- 4. firewall ----------
Passo "Liberando a porta $porta no firewall (só rede interna)"
Get-NetFirewallRule -DisplayName $nomeTarefa -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $nomeTarefa -Direction Inbound -Protocol TCP -LocalPort $porta `
    -Action Allow -Profile Domain, Private | Out-Null
Ok "regra '$nomeTarefa' criada (perfis Domínio e Privado)"
$publicas = Get-NetConnectionProfile | Where-Object NetworkCategory -eq "Public"
if ($publicas) {
    Aviso "a rede '$($publicas[0].Name)' está como Pública: nela a porta continua bloqueada. Mude para Privada/Domínio se o acesso pela rede falhar."
}

# ---------- 5. tarefa agendada ----------
Passo "Criando a tarefa agendada '$nomeTarefa'"
$iniciar = Join-Path $PSScriptRoot "iniciar.ps1"
$acao = New-ScheduledTaskAction -Execute "powershell.exe" -WorkingDirectory $raiz `
    -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$iniciar`""
$gatilho = New-ScheduledTaskTrigger -AtStartup
$gatilho.Delay = "PT30S"   # espera a rede subir
$conta = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$config = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
    -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $nomeTarefa -Action $acao -Trigger $gatilho -Principal $conta -Settings $config `
    -Description "Relatório de notas por dia - porta $porta. Instalado por servidor\instalar.ps1 em $raiz" -Force | Out-Null
Ok "sobe sozinho ao ligar o computador (sem precisar de login)"

# ---------- 6. iniciar e testar ----------
Passo "Iniciando"
Start-ScheduledTask -TaskName $nomeTarefa
$url = "http://localhost:$porta/api/lojas"
$respondeu = $false
for ($i = 0; $i -lt 30 -and -not $respondeu; $i++) {
    Start-Sleep -Seconds 2
    try { Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 5 | Out-Null; $respondeu = $true } catch {}
}
if (-not $respondeu) { Falha "o relatório não respondeu em $url. Veja o log: $(Join-Path $raiz 'logs\servidor.log')" }
Ok "respondendo em http://localhost:$porta"

$ips = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }).IPAddress
Write-Host "`nPronto! Acesse de outra máquina da rede:" -ForegroundColor Green
$ips | ForEach-Object { Write-Host "  http://${_}:$porta" }
Write-Host "  http://$($env:COMPUTERNAME):$porta"
Write-Host "Log: $(Join-Path $raiz 'logs\servidor.log')"
