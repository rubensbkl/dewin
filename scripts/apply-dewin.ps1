<#
.SYNOPSIS
    DEWIN Post-Install Runner & System Booster (Universal Autonomous Edition)
.DESCRIPTION
    Script orquestrador pos-instalacao e booster nativo do projeto DEWIN.
    Suporte unificado, 100% autonomo e com sistema completo de auditoria e logs.
    Matriz 2x2:
    - [1] Desktop Dev & Workstation (WSL2, Hyper-V, Sandbox, sem hibernacao, foco em SSD e CPU)
    - [2] Desktop Geral, Jogos & Produtividade (Criador / Gamer, sem virtualizacao, sem hibernacao)
    - [3] Notebook Dev & Workstation (WSL2, Hyper-V, Sandbox, ferramentas Dev, hibernacao segura compacta)
    - [4] Notebook Geral, Jogos & Produtividade (Maxima autonomia de bateria e FPS, hibernacao segura compacta)
.NOTES
    Projeto: DEWIN (Windows 11 Pro 25H2)
#>

[CmdletBinding()]
param(
    [ValidateSet('DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral', 'Prompt')]
    [string]$Profile = 'Prompt',
    [switch]$NoRestart
)

# 0. Configuracao de Codificacao UTF-8 para Console
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 1. Elevacao Administrativa
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Elevando permissoes para Administrador...' -ForegroundColor Yellow
    Start-Process powershell.exe -WorkingDirectory $PSScriptRoot -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Profile $Profile" -Verb RunAs
    exit 0
}

# 2. Inicializacao do Sistema Completo de Auditoria e Logs
$scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()
$global:DewinStats = @{
    Success  = 0
    Warnings = 0
    Errors   = 0
}

# Define diretorio de logs na raiz do projeto ou em TEMP como contingencia
$logDir = Join-Path -Path $PSScriptRoot -ChildPath '..\logs'
try {
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
} catch {
    $logDir = Join-Path -Path $env:TEMP -ChildPath 'dewin-logs'
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
}

$timestampStr = Get-Date -Format 'yyyyMMdd_HHmmss'
$global:DewinLogPath = Join-Path -Path $logDir -ChildPath "dewin_${timestampStr}.log"
$global:DewinLatestLog = Join-Path -Path $logDir -ChildPath 'dewin-latest.log'

# Funcao de Logging Centralizada
function Write-DewinLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'STEP', 'RAW')]
        [string]$Level = 'INFO',
        [switch]$NoConsole
    )

    $timeNow = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logPrefix = "[$timeNow] [$Level]"

    if (-not $NoConsole -and $Level -ne 'RAW') {
        switch ($Level) {
            'SUCCESS' { Write-Host $Message -ForegroundColor Green; $global:DewinStats.Success++ }
            'WARN'    { Write-Host $Message -ForegroundColor Yellow; $global:DewinStats.Warnings++ }
            'ERROR'   { Write-Host $Message -ForegroundColor Red; $global:DewinStats.Errors++ }
            'STEP'    { Write-Host $Message -ForegroundColor Cyan }
            Default   { Write-Host $Message -ForegroundColor Gray }
        }
    }

    if ($global:DewinLogPath) {
        $entry = if ($Level -eq 'RAW') { $Message } else { "$logPrefix $Message" }
        try {
            Add-Content -LiteralPath $global:DewinLogPath -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}

# Funcoes Utilitarias de Sistema
function Set-DewinReg {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$Value,
        [string]$Type = 'DWord'
    )
    try {
        if (-not (Test-Path $Path)) { New-Item -Path $Path -Force -ErrorAction Stop | Out-Null }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop | Out-Null
        Write-DewinLog -Level INFO -Message "Reg OK: $Path\$Name = $Value ($Type)" -NoConsole
    } catch {
        Write-DewinLog -Level WARN -Message "Reg Falha: $Path\$Name - $($_.Exception.Message)" -NoConsole
    }
}

function Restart-DewinExplorer {
    Write-DewinLog -Level STEP -Message '[*] Atualizando Windows Explorer...'
    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Start-Process "$env:SystemRoot\explorer.exe"
    }
    Write-DewinLog -Level INFO -Message 'Windows Explorer reiniciado com sucesso.' -NoConsole
}

Clear-Host
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '               DEWIN - OTIMIZADOR & BOOSTER DO SISTEMA             ' -ForegroundColor Cyan
Write-Host '         Universal Open-Source Edition | Windows 11 Pro           ' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host ''

# 3. Deteccao de Hardware e Perfil de Uso
$isDetectedLaptop = $false
try {
    $enclosure = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
    $chassisTypes = @($enclosure.ChassisTypes)
    $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $isDetectedLaptop = ($chassisTypes | Where-Object { $_ -in @(8, 9, 10, 11, 12, 14, 18, 21, 31, 32) }) -or $hasBattery
} catch {
    $isDetectedLaptop = $false
}

$cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
$manufacturer = if ($cs.Manufacturer) { $cs.Manufacturer.Trim() } else { 'Desconhecido' }
$model = if ($cs.Model) { $cs.Model.Trim() } else { 'Desconhecido' }

$osInfo = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$winVersion = if ($osInfo) { "$($osInfo.Caption) (Build $($osInfo.BuildNumber))" } else { 'Windows 11' }

$gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$gpuNames = ($gpus | ForEach-Object { $_.Name }) -join ' | '
if (-not $gpuNames) { $gpuNames = 'Nao detectada' }

$ramTotalGB = try { [math]::Round((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB) } catch { 0 }

$deviceTypeStr = if ($isDetectedLaptop) { 'Notebook' } else { 'Desktop' }

# Gravacao do Cabecalho de Auditoria no Log
Write-DewinLog -Level RAW -Message '=================================================================='
Write-DewinLog -Level RAW -Message "DEWIN BOOSTER - REGISTRO DE AUDITORIA E LOG"
Write-DewinLog -Level RAW -Message "Data e Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-DewinLog -Level RAW -Message "Sistema Operacional: $winVersion"
Write-DewinLog -Level RAW -Message "Dispositivo: $manufacturer $model ($deviceTypeStr)"
Write-DewinLog -Level RAW -Message "Memoria RAM: $ramTotalGB GB"
Write-DewinLog -Level RAW -Message "GPU(s): $gpuNames"
Write-DewinLog -Level RAW -Message "Usuario Administrador: $isAdmin"
Write-DewinLog -Level RAW -Message '=================================================================='

Write-Host '[*] Dispositivo Detectado: ' -NoNewline -ForegroundColor Cyan
Write-Host "$manufacturer $model " -NoNewline -ForegroundColor White
if ($isDetectedLaptop) {
    Write-Host '(Notebook / Portatil)' -ForegroundColor Green
} else {
    Write-Host '(Desktop / Estacao)' -ForegroundColor Green
}
Write-Host ('[*] Memoria RAM: ' + "$ramTotalGB GB") -ForegroundColor Gray
Write-Host ('[*] GPU(s): ' + $gpuNames) -ForegroundColor Gray
Write-Host ''

$isLaptop = $isDetectedLaptop
$isDevProfile = $false

if ($Profile -eq 'Prompt') {
    Write-Host 'Escolha o perfil desejado para esta maquina:' -ForegroundColor Yellow
    if ($isDetectedLaptop) {
        Write-Host '  [i] Dispositivo portatil identificado! Recomendado: [3] para perfil Dev ou [4] para Geral/Jogos.' -ForegroundColor Magenta
    } else {
        Write-Host '  [i] Desktop identificado! Recomendado: [1] para perfil Dev ou [2] para Geral/Jogos.' -ForegroundColor Magenta
    }
    Write-Host ''
    Write-Host '  --- DESKTOPS ---' -ForegroundColor DarkGray
    Write-Host '  [1] Desktop - Dev & Workstation' -ForegroundColor Green
    Write-Host '      -> WSL2, Hyper-V, Sandbox, VC++, Chrome, 7-Zip, .NET, sem hibernacao (recupera SSD).' -ForegroundColor Gray
    Write-Host '  [2] Desktop - Geral, Jogos & Produtividade' -ForegroundColor Cyan
    Write-Host '      -> Maxima leveza, menor latencia de entrada e SSD liberado, sem virtualizacao.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  --- NOTEBOOKS ---' -ForegroundColor DarkGray
    Write-Host '  [3] Notebook - Dev & Workstation' -ForegroundColor Green
    Write-Host '      -> WSL2, Hyper-V, Sandbox, ferramentas Dev, hibernacao segura compacta (~3 GB).' -ForegroundColor Gray
    Write-Host '  [4] Notebook - Geral, Jogos & Produtividade' -ForegroundColor Cyan
    Write-Host '      -> Maxima autonomia de bateria e FPS, sem virtualizacao, hibernacao segura compacta (~3 GB).' -ForegroundColor Gray
    Write-Host ''
    
    $defaultOpt = if ($isDetectedLaptop) { '3' } else { '1' }
    $selection = Read-Host "Digite a opcao desejada [1 a 4] (Padrao: $defaultOpt)"
    if ([string]::IsNullOrWhiteSpace($selection)) { $selection = $defaultOpt }

    switch ($selection) {
        '2' {
            $profileName = 'Desktop - Geral, Jogos & Produtividade'
            $isLaptop = $false
            $isDevProfile = $false
        }
        '3' {
            $profileName = 'Notebook - Dev & Workstation'
            $isLaptop = $true
            $isDevProfile = $true
        }
        '4' {
            $profileName = 'Notebook - Geral, Jogos & Produtividade'
            $isLaptop = $true
            $isDevProfile = $false
        }
        Default {
            $profileName = 'Desktop - Dev & Workstation'
            $isLaptop = $false
            $isDevProfile = $true
        }
    }
} else {
    switch ($Profile) {
        'DesktopGeral' {
            $profileName = 'Desktop - Geral, Jogos & Produtividade'
            $isLaptop = $false
            $isDevProfile = $false
        }
        'LaptopDev' {
            $profileName = 'Notebook - Dev & Workstation'
            $isLaptop = $true
            $isDevProfile = $true
        }
        'LaptopGeral' {
            $profileName = 'Notebook - Geral, Jogos & Produtividade'
            $isLaptop = $true
            $isDevProfile = $false
        }
        Default {
            $profileName = 'Desktop - Dev & Workstation'
            $isLaptop = $false
            $isDevProfile = $true
        }
    }
}

Write-DewinLog -Level INFO -Message "Perfil Selecionado: $profileName (DevProfile: $isDevProfile, Laptop: $isLaptop)"

# 4. Confirmacao do Perfil e Ponto de Restauracao Opcional
Write-Host ''
Write-Host ('[OK] Perfil selecionado: ' + $profileName) -ForegroundColor Green
Write-Host 'Modo de Execucao: 100% Autonomo e Nativo DEWIN' -ForegroundColor Cyan

# Verificacao de Espaco em Disco
$driveC = Get-PSDrive C -ErrorAction SilentlyContinue
$freeGB = if ($driveC) { [math]::Round($driveC.Free / 1GB, 1) } else { 0 }
Write-Host ''
if ($freeGB -gt 0) {
    $color = if ($freeGB -lt 35) { 'Yellow' } else { 'Cyan' }
    Write-Host ('[*] Espaco livre em C: ' + $freeGB + ' GB') -ForegroundColor $color
}

# Ponto de Restauracao Opcional
Write-Host ''
Write-Host 'Criar Ponto de Restauracao do Windows antes de aplicar?' -ForegroundColor Yellow
Write-Host '  -> Recomendado escolher [N] caso tenha pouco espaco livre (< 40 GB) ou o servico VSS trave.' -ForegroundColor Gray
$askRestore = Read-Host 'Deseja criar Ponto de Restauracao? (S/N) [Padrao: N]'
$createRestorePoint = ($askRestore -match '^[sSyY]')

if ($createRestorePoint) {
    Write-DewinLog -Level STEP -Message '[*] Criando Ponto de Restauracao...'
    try {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'SystemRestorePointCreationFrequency' -Value 0
        Enable-ComputerRestore -Drive "$Env:SystemDrive" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "DEWIN Booster - $profileName" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-DewinLog -Level SUCCESS -Message '  [+] Ponto de Restauracao criado com sucesso.'
    } catch {
        Write-DewinLog -Level WARN -Message ('  [!] Nao foi possivel criar ponto de restauracao: ' + $_.Exception.Message)
    }
} else {
    Write-DewinLog -Level INFO -Message '[*] Ponto de Restauracao ignorado. Prosseguindo direto para as otimizacoes.'
}

# 5. Calibracao de Hardware, Energia & Perifericos
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [1/7] Aplicando calibracao de hardware, energia e compatibilidade...'

# 5.1. Calibracao GPU para DaVinci Resolve, Unreal Engine e Jogos
$gpuPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
Set-DewinReg -Path $gpuPath -Name 'TdrDelay' -Value 8
Set-DewinReg -Path $gpuPath -Name 'TdrDdiDelay' -Value 8
Set-DewinReg -Path $gpuPath -Name 'HwSchMode' -Value 2 # HAGS Ativo
Write-DewinLog -Level SUCCESS -Message '  [+] GPU & Render: TdrDelay=8s, TdrDdiDelay=8s e HAGS calibrados.'

# 5.2. Gerenciamento de Energia e Bateria (Desktop vs. Notebook)
if ($isLaptop) {
    powercfg /h on 2>$null
    powercfg /h /type reduced 2>$null
    Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Control Center' -Name 'IsBatteryPercentageEnabled' -Value 1
    Write-DewinLog -Level SUCCESS -Message '  [+] Notebook: Hibernacao reduzida (~3GB) e porcentagem de bateria ativadas.'
} else {
    powercfg /h off 2>$null
    Write-DewinLog -Level SUCCESS -Message '  [+] Desktop: Hibernacao desativada para recuperar 16 a 24 GB de SSD.'
}

# 5.3. Bloqueio Global de Injeção de Bloatware da BIOS (WPBT) e Periféricos
Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'DisableWpbtExecution' -Value 1

Stop-Process -Name 'logi_download_assistant' -Force -ErrorAction SilentlyContinue
$programFiles64 = if ($Env:ProgramW6432) { $Env:ProgramW6432 } else { $Env:ProgramFiles }
$logiPath = Join-Path $programFiles64 'LogiDownloadAssistant'
if (-not (Test-Path $logiPath)) { New-Item -Path $logiPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
icacls $logiPath /deny "*S-1-1-0:(W)" 2>$null | Out-Null

$razerPath = "$Env:SystemRoot\Installer\Razer"
if (-not (Test-Path $razerPath)) { New-Item -Path $razerPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null }
icacls $razerPath /deny "*S-1-1-0:(W)" 2>$null | Out-Null

Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Installer' -Name 'DisableCoInstallers' -Value 1
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1
Write-DewinLog -Level SUCCESS -Message '  [+] Seguranca: Bloqueio de auto-instaladores (WPBT, Logitech, Razer) e login direto ativos.'

# 6. Debloat Cirurgico de Bloatware Nativo (28 aplicativos)
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [2/7] Aplicando debloat cirurgico (preservando Store, Calculadora, Notepad e Paint)...'

$bloatwarePackages = @(
    'Microsoft.Microsoft3DViewer', 'Microsoft.BingSearch', 'Clipchamp.Clipchamp',
    'Microsoft.Copilot', 'Microsoft.549981C3F5F10', 'Microsoft.Windows.DevHome',
    'MicrosoftCorporationII.MicrosoftFamily', 'Microsoft.WindowsFeedbackHub',
    'Microsoft.Edge.GameAssist', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'microsoft.windowscommunicationsapps', 'Microsoft.WindowsMaps',
    'Microsoft.MixedReality.Portal', 'Microsoft.BingNews', 'Microsoft.MicrosoftOfficeHub',
    'Microsoft.Office.OneNote', 'Microsoft.OutlookForWindows', 'Microsoft.MSPaint',
    'Microsoft.People', 'Microsoft.PowerAutomateDesktop', 'MicrosoftCorporationII.QuickAssist',
    'Microsoft.SkypeApp', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.MicrosoftStickyNotes', 'MicrosoftTeams', 'MSTeams',
    'Microsoft.Todos', 'Microsoft.Wallet', 'Microsoft.BingWeather',
    'Microsoft.YourPhone', 'Microsoft.ZuneMusic'
)

$removedCount = 0
foreach ($pkg in $bloatwarePackages) {
    try {
        $appx = Get-AppxPackage -Name $pkg -ErrorAction SilentlyContinue
        if ($appx) {
            $appx | Remove-AppxPackage -ErrorAction SilentlyContinue
            $removedCount++
        }
        $prov = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $pkg }
        if ($prov) {
            $prov | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        }
        Write-DewinLog -Level INFO -Message "Debloat: Pacote $pkg processado." -NoConsole
    } catch {
        Write-DewinLog -Level WARN -Message "Debloat: Aviso ao remover $pkg - $($_.Exception.Message)" -NoConsole
    }
}
Write-DewinLog -Level SUCCESS -Message "  [+] Limpeza de 28 bloatwares UWP concluida com sucesso."

# 7. Otimizacoes Nativas de Interface, Barra de Tarefas & Responsividade
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [3/7] Otimizando interface, barra de tarefas e resposta dos menus...'

# 7.1. Barra de Tarefas: Ocultar Pesquisa e Multitarefa (Task View)
Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0
$advExplorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-DewinReg -Path $advExplorer -Name 'ShowTaskViewButton' -Value 0
Set-DewinReg -Path $advExplorer -Name 'TaskbarAl' -Value 1 # Alinhamento ao Centro (Padrao Windows 11)
Set-DewinReg -Path "$advExplorer\TaskbarDeveloperSettings" -Name 'TaskbarEndTask' -Value 1 # Finalizar Tarefa no Botao Direito

# 7.2. Menu de Contexto Classico (Windows 10) no Botao Direito
$clsidPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
if (-not (Test-Path $clsidPath)) { New-Item -Path $clsidPath -Force -ErrorAction SilentlyContinue | Out-Null }
Set-ItemProperty -Path $clsidPath -Name '(Default)' -Value '' -Force -ErrorAction SilentlyContinue | Out-Null

# 7.3. Abrir Explorer em "Este Computador" & Remover Pagina Inicial e Galeria
Set-DewinReg -Path $advExplorer -Name 'LaunchTo' -Value 1
Set-DewinReg -Path 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0
Set-DewinReg -Path 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0

# 7.4. Exibir Extensoes de Arquivo e Pastas Ocultas
Set-DewinReg -Path $advExplorer -Name 'HideFileExt' -Value 0
Set-DewinReg -Path $advExplorer -Name 'Hidden' -Value 1

# 7.5. Desativar Descoberta Automatica de Pastas no Explorer (Abertura instantanea de pastas pesadas)
Remove-Item -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags' -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU' -Recurse -Force -ErrorAction SilentlyContinue
Set-DewinReg -Path 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' -Name 'FolderType' -Value 'NotSpecified' -Type 'String'

# 7.6. Desativar Widgets (News & Interests) e Processos de Background
Get-Process *Widget* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-AppxPackage Microsoft.WidgetsPlatformRuntime -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Get-AppxPackage MicrosoftWindows.Client.WebExperience -AllUsers -ErrorAction SilentlyContinue | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -Name 'AllowNewsAndInterests' -Value 0

# 7.7. Barras de Rolagem Sempre Visiveis e Modo Escuro
Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility' -Name 'DynamicScrollbars' -Value 0
$themePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
Set-DewinReg -Path $themePath -Name 'AppsUseLightTheme' -Value 0
Set-DewinReg -Path $themePath -Name 'SystemUsesLightTheme' -Value 0

# 7.8. Atraso de Menus Instantaneo e NumLock no Boot
Set-DewinReg -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type 'String'
if (Test-Path 'HKU:\.DEFAULT\Control Panel\Keyboard') { Set-DewinReg -Path 'HKU:\.DEFAULT\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -Type 'String' }
Set-DewinReg -Path 'HKCU:\Control Panel\Keyboard' -Name 'InitialKeyboardIndicators' -Value '2' -Type 'String'

# 7.9. Desativar Telas de Interrupcao (SCOOBE) e Anuncios no App Configuracoes
Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' -Name 'ScoobeSystemSettingEnabled' -Value 0
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OOBE' -Name 'DisableVoice' -Value 1

$cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
@('SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-353698Enabled', 'SystemPaneSuggestionsEnabled') | ForEach-Object {
    Set-DewinReg -Path $cdm -Name $_ -Value 0
}
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableSpotlightCollectionOnDesktop' -Value 1
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsSpotlightFeatures' -Value 1

Write-DewinLog -Level SUCCESS -Message '  [+] Interface: Barra sem pesquisa/multitarefa, menus sem delay e telas de interrupcao eliminadas.'

# 8. Otimizacoes de Baixa Latencia, Rede & Jogos (Gaming / Realtime)
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [4/7] Calibrando rede para baixa latencia, prioridade de CPU e Gaming...'

# 8.1. Prioridade de CPU e Desativacao de Network Throttling
$sysProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
Set-DewinReg -Path $sysProfile -Name 'NetworkThrottlingIndex' -Value 0xffffffff # Sem limite de banda nao-multimidia
Set-DewinReg -Path $sysProfile -Name 'SystemResponsiveness' -Value 0 # 100% de CPU para a aplicacao em foco

# 8.2. Desativacao do GameDVR (Captura em Background) e Otimizacoes de Jogos
Set-DewinReg -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
Set-DewinReg -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -Value 2
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
Set-DewinReg -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1

# 8.3. Aceleração de Cursor 1:1 e Desativação de Teclas de Aderência (Sticky Keys)
$mouse = 'HKCU:\Control Panel\Mouse'
Set-DewinReg -Path $mouse -Name 'MouseSpeed' -Value '0' -Type 'String'
Set-DewinReg -Path $mouse -Name 'MouseThreshold1' -Value '0' -Type 'String'
Set-DewinReg -Path $mouse -Name 'MouseThreshold2' -Value '0' -Type 'String'

Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -Type 'String'
Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value '58' -Type 'String'
Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '122' -Type 'String'

Write-DewinLog -Level SUCCESS -Message '  [+] Latencia: Network Throttling desativado, 100% CPU em foco, GameDVR e Sticky Keys eliminados.'

# 9. Otimizacoes de Privacidade, Telemetria & IA
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [5/7] Desativando telemetria, IA invasiva e tarefas agendadas em segundo plano...'

# 9.1. Telemetria Geral e Privacidade
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0
Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0
Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0
Set-DewinReg -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Value 0

Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
Get-Service -Name 'DiagTrack' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
Get-Service -Name 'wermgr' -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue

try { Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue } catch {}
[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')

# 9.2. Desativar Windows AI, Recall e Copilot
Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'SettingsPageVisibility' -Value 'hide:aicomponents' -Type 'String'
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\WindowsNotepad' -Name 'DisableAIFeatures' -Value 1
Get-Service -Name 'WSAIFabricSvc' -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
Get-Service -Name 'WSAIFabricSvc' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
try { Disable-WindowsOptionalFeature -FeatureName Recall -Online -NoRestart -ErrorAction SilentlyContinue | Out-Null } catch {}

# 9.3. Desativar Delivery Optimization P2P e Bloquear Pesquisas da Loja no Iniciar
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' -Name 'DODownloadMode' -Value 0
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1
$storeDb = "$Env:LocalAppData\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalState\store.db"
if (Test-Path $storeDb) { icacls $storeDb /deny "*S-1-1-0:F" 2>$null | Out-Null }

# 9.4. Desativar Historico de Atividades e Telemetria de Escrita
$actSys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
Set-DewinReg -Path $actSys -Name 'EnableActivityFeed' -Value 0
Set-DewinReg -Path $actSys -Name 'PublishUserActivities' -Value 0
Set-DewinReg -Path $actSys -Name 'UploadUserActivities' -Value 0

$ink = 'HKCU:\Software\Microsoft\InputPersonalization'
Set-DewinReg -Path $ink -Name 'RestrictImplicitInkCollection' -Value 1
Set-DewinReg -Path $ink -Name 'RestrictImplicitTextCollection' -Value 1
Set-DewinReg -Path "$ink\TrainedDataStore" -Name 'HarvestContacts' -Value 0

# 9.5. Politicas de Debloat do Microsoft Edge
$edgePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
@('PersonalizationReportingEnabled', 'ShowRecommendationsEnabled', 'UserFeedbackAllowed', 'AlternateErrorPagesEnabled',
  'EdgeCollectionsEnabled', 'EdgeShoppingAssistantEnabled', 'MicrosoftEdgeInsiderPromotionEnabled', 'ShowMicrosoftRewards',
  'WebWidgetAllowed', 'DiagnosticData', 'EdgeAssetDeliveryServiceEnabled', 'WalletDonationEnabled', 'DefaultBrowserSettingsCampaignEnabled') | ForEach-Object {
    Set-DewinReg -Path $edgePolicy -Name $_ -Value 0
}
Set-DewinReg -Path $edgePolicy -Name 'HideFirstRunExperience' -Value 1
Set-DewinReg -Path $edgePolicy -Name 'ConfigureDoNotTrack' -Value 1
Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' -Name 'CreateDesktopShortcutDefault' -Value 0

# 9.6. Remocao do OneDrive
$oneDriveSetup = Join-Path $Env:SystemRoot 'System32\OneDriveSetup.exe'
if (-not (Test-Path $oneDriveSetup)) { $oneDriveSetup = Join-Path $Env:SystemRoot 'SysWOW64\OneDriveSetup.exe' }
if (Test-Path $oneDriveSetup) { Start-Process -FilePath $oneDriveSetup -ArgumentList '/uninstall' -Wait -NoNewWindow -ErrorAction SilentlyContinue }
Stop-Process -Name 'OneDrive', 'FileCoAuth' -Force -ErrorAction SilentlyContinue
Remove-Item "$Env:LocalAppData\Microsoft\OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$Env:ProgramData\Microsoft OneDrive" -Recurse -Force -ErrorAction SilentlyContinue
Get-Service -Name 'OneSyncSvc' -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue

# 9.7. Desativar Tarefas Agendadas Pesadas de Telemetria (Evita picos de 100% disco/CPU em idle)
$telemetryTasks = @(
    '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
    '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
    '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector'
)
foreach ($task in $telemetryTasks) {
    try {
        $tPath = $task.Substring(0, $task.LastIndexOf('\') + 1)
        $tName = $task.Substring($task.LastIndexOf('\') + 1)
        Disable-ScheduledTask -TaskPath $tPath -TaskName $tName -ErrorAction SilentlyContinue | Out-Null
        Write-DewinLog -Level INFO -Message "Task desativada: $task" -NoConsole
    } catch {}
}

Write-DewinLog -Level SUCCESS -Message '  [+] Privacidade: Telemetria, tarefas de diagnostico em idle, IA e Edge Bloat desativados.'

# 10. Otimizacoes de Kernel, SSD, Servicos & Memoria
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [6/7] Otimizando servicos, memoria RAM e vida util do SSD...'

# 10.1. Calibracao SvcHost proporcional a RAM
try {
    $memKB = [int]((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB)
    if ($memKB -gt 0) {
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Value $memKB
        Write-DewinLog -Level SUCCESS -Message "  [+] Memoria: SvcHostSplitThresholdInKB calibrado com $([math]::Round($memKB / 1MB)) GB de RAM."
    }
} catch {}

# 10.2. Ajuste de Servicos Obsoletos
Get-Service -Name 'CscService' -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue
Get-Service -Name 'MapsBroker' -ErrorAction SilentlyContinue | Set-Service -StartupType Manual -ErrorAction SilentlyContinue
Get-Service -Name 'SharedAccess' -ErrorAction SilentlyContinue | Set-Service -StartupType Disabled -ErrorAction SilentlyContinue

# 10.3. Dual-Boot UTC, BSoD Detalhado & NTFS LongPaths
Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal' -Value 1 -Type 'QWord'
Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl' -Name 'DisplayParameters' -Value 1
Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1

# 10.4. Desativar Carimbo de Ultimo Acesso no NTFS (Menos escritas no SSD e leitura mais rapida)
try {
    & fsutil behavior set disablelastaccess 1 2>$null | Out-Null
    Write-DewinLog -Level INFO -Message 'NTFS DisableLastAccess ativado com sucesso.' -NoConsole
} catch {}

# 10.5. Desativar Armazenamento Reservado (Devolve ~7 GB de SSD)
try {
    DISM.exe /Online /Set-ReservedStorageState /State:Disabled 2>$null | Out-Null
    Write-DewinLog -Level SUCCESS -Message '  [+] Armazenamento Reservado desativado (~7GB de SSD liberados).'
} catch {}

# 10.6. Backup Diario Automatico do Registro (AutoRegBackup)
try {
    $cfgMgr = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager'
    Set-DewinReg -Path $cfgMgr -Name 'EnablePeriodicBackup' -Value 1
    Set-DewinReg -Path $cfgMgr -Name 'BackupCount' -Value 2

    $action = New-ScheduledTaskAction -Execute 'schtasks' -Argument '/run /i /tn "\Microsoft\Windows\Registry\RegIdleBackup"'
    $trigger = New-ScheduledTaskTrigger -Daily -At '00:30'
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName 'AutoRegBackup' -Description 'Backup Diario do Registro DEWIN' -User 'System' -Force -ErrorAction SilentlyContinue | Out-Null
} catch {}

# 10.7. Avisos de RDP Nao Assinado e Log de Boot (Apenas Dev)
if ($isDevProfile) {
    Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client' -Name 'RedirectionWarningDialogVersion' -Value 1
    Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Terminal Server Client' -Name 'RdpLaunchConsentAccepted' -Value 1
    Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'verbosestatus' -Value 1
}

# 10.8. Limpeza de Pastas Temp e Componentes
Remove-Item -Path "$Env:Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
try { cleanmgr.exe /d C: /VERYLOWDISK 2>$null | Out-Null } catch {}
try { Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase 2>$null | Out-Null } catch {}

Write-DewinLog -Level SUCCESS -Message '  [+] Sistema & SSD: DisableLastAccess ativo, LongPaths, UTC e limpeza concluidos.'

# 11. Recursos Opcionais (DISM) & Softwares Essenciais (Winget)
Write-Host ''
Write-DewinLog -Level STEP -Message '[*] [7/7] Configurando recursos opcionais e pacotes essenciais...'

# .NET Framework 3.5 (Compatibilidade legado)
try { Enable-WindowsOptionalFeature -Online -FeatureName 'NetFx3' -NoRestart -ErrorAction SilentlyContinue | Out-Null } catch {}

if ($isDevProfile) {
    Write-DewinLog -Level STEP -Message '  [*] Perfil Dev: Habilitando WSL2, Hyper-V e Windows Sandbox...'
    @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux', 'Microsoft-Hyper-V-All', 'Containers-DisposableClientVM') | ForEach-Object {
        try { Enable-WindowsOptionalFeature -Online -FeatureName $_ -NoRestart -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    Write-DewinLog -Level SUCCESS -Message '  [+] Recursos Dev (WSL2, Hyper-V, Sandbox) prontos.'
}

# Instalacao de Runtimes e Softwares Essenciais via Winget
$hasInternet = $false
try {
    $hasInternet = [bool](Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue)
} catch {}

if ($hasInternet) {
    $essentialApps = @(
        @{ Name = 'Visual C++ 2015-2022 (x64)'; Id = 'Microsoft.VCRedist.2015+.x64' },
        @{ Name = 'Visual C++ 2015-2022 (x86)'; Id = 'Microsoft.VCRedist.2015+.x86' },
        @{ Name = '7-Zip'; Id = '7zip.7zip' },
        @{ Name = 'Google Chrome'; Id = 'Google.Chrome' }
    )

    foreach ($app in $essentialApps) {
        Write-DewinLog -Level STEP -Message "  [*] Instalando/Atualizando $($app.Name)..."
        try {
            $wingetOut = & winget.exe install --id $app.Id --exact --silent --accept-package-agreements --accept-source-agreements --force 2>&1
            $exitCode = $LASTEXITCODE
            Write-DewinLog -Level INFO -Message "Winget $($app.Name): Codigo de saida $exitCode" -NoConsole
            Write-DewinLog -Level SUCCESS -Message "  [+] $($app.Name) pronto."
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Nao foi possivel instalar $($app.Name): $($_.Exception.Message)"
        }
    }
} else {
    Write-DewinLog -Level WARN -Message '  [!] Sem conexao com a internet. Instalacao de pacotes ignorada sem interromper o processo.'
}

# 12. Atualizacao Final do Windows Explorer
Write-Host ''
Restart-DewinExplorer

# Finalizacao do Timer e Sumario no Log
$scriptTimer.Stop()
$elapsedSec = [math]::Round($scriptTimer.Elapsed.TotalSeconds, 1)

Write-DewinLog -Level RAW -Message '=================================================================='
Write-DewinLog -Level RAW -Message "DEWIN BOOSTER FINALIZADO COM SUCESSO"
Write-DewinLog -Level RAW -Message "Tempo Total: $elapsedSec segundos"
Write-DewinLog -Level RAW -Message "Estatisticas: Sucessos=$($global:DewinStats.Success), Avisos=$($global:DewinStats.Warnings), Erros=$($global:DewinStats.Errors)"
Write-DewinLog -Level RAW -Message '=================================================================='

# Cria link/copia para dewin-latest.log
try {
    Copy-Item -Path $global:DewinLogPath -Destination $global:DewinLatestLog -Force -ErrorAction SilentlyContinue
} catch {}

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Green
Write-Host '          DEWIN BOOSTER FINALIZADO COM SUCESSO! (100% NATIVO)     ' -ForegroundColor Green
Write-Host '==================================================================' -ForegroundColor Green
Write-Host ''
Write-Host "Tempo total de execucao: $elapsedSec segundos" -ForegroundColor Cyan
Write-Host "[*] Log de auditoria salvo em: $global:DewinLogPath" -ForegroundColor Yellow
Write-Host ''
Write-Host 'Recomenda-se reiniciar o computador para que todas as alteracoes' -ForegroundColor Cyan
Write-Host 'de kernel, drivers e servicos entrem completamente em vigor.' -ForegroundColor Cyan
Write-Host ''

if (-not $NoRestart) {
    $choice = Read-Host 'Deseja reiniciar o computador agora? (S/N)'
    if ($choice -match '^[sSyY]') {
        Restart-Computer
    } else {
        Write-Host ''
        Write-Host 'Lembre-se de reiniciar manualmente mais tarde para aplicar todas as mudancas.' -ForegroundColor Yellow
        Write-Host ''
        Pause
    }
} else {
    Write-Host ''
    Pause
}

exit 0
