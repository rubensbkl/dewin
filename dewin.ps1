# ==============================================================================
# DEWIN Booster - Universal Windows Optimizer & Debloater (Single-Script Edition)
# ExecuÃ§Ã£o via terminal:
# irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('Light', 'Medium', 'Aggressive', 'Dev', 'DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral', 'GUI')]
    [string]$Profile = 'GUI',
    [switch]$Silent,
    [switch]$NoRestart
)

# 0. Auto-correÃ§Ã£o de codificaÃ§Ã£o para execuÃ§Ã£o direta via powershell.exe -File
if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    if ('Ã§'.Length -ne 1) {
        $scriptBytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
        $scriptText = [System.Text.Encoding]::UTF8.GetString($scriptBytes)
        $scriptBlock = [ScriptBlock]::Create($scriptText)
        $boundParams = $PSBoundParameters
        & $scriptBlock @boundParams
        return
    }
}

# 1. CodificaÃ§Ã£o UTF-8 para Console
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 2. Auto-ElevaÃ§Ã£o Administrativa (UAC)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[*] PrivilÃ©gios de Administrador necessÃ¡rios. Elevando via UAC...' -ForegroundColor Cyan
    $tempLauncher = Join-Path -Path $env:TEMP -ChildPath 'dewin-elevated.ps1'
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $scriptBytes = if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
            [System.IO.File]::ReadAllBytes($PSCommandPath)
        } else {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add('User-Agent', 'DEWIN-Installer')
            $webClient.DownloadData('https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1')
        }
        $utf8Preamble = [System.Text.Encoding]::UTF8.GetPreamble()
        $hasBom = ($scriptBytes.Length -ge 3 -and $scriptBytes[0] -eq 0xEF -and $scriptBytes[1] -eq 0xBB -and $scriptBytes[2] -eq 0xBF)
        if (-not $hasBom) {
            $scriptBytes = $utf8Preamble + $scriptBytes
        }
        [System.IO.File]::WriteAllBytes($tempLauncher, $scriptBytes)

        $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$tempLauncher`"")
        if ($Profile) { $elevArgs += @('-Profile', $Profile) }
        if ($Silent) { $elevArgs += '-Silent' }
        if ($NoRestart) { $elevArgs += '-NoRestart' }
        Start-Process powershell.exe -ArgumentList $elevArgs -Verb RunAs
        exit 0
    } catch {
        Write-Host ''
        Write-Host '==================================================================' -ForegroundColor Yellow
        Write-Host ' [!] PRIVILÃ‰GIOS DE ADMINISTRADOR NECESSÃRIOS' -ForegroundColor Yellow
        Write-Host ' O DEWIN precisa ser executado em um terminal com privilÃ©gios de Administrador.' -ForegroundColor Yellow
        Write-Host ' Clique com o botÃ£o direito no Iniciar -> Terminal (Administrador)' -ForegroundColor Cyan
        Write-Host ' e execute novamente:' -ForegroundColor Cyan
        Write-Host ' irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex' -ForegroundColor White
        Write-Host '==================================================================' -ForegroundColor Yellow
        exit 1
    }
}

# --- MÃ³dulo: src\core\Logger.ps1 ---
# ==============================================================================
# DEWIN Core: Sistema de Auditoria e Logs
# ==============================================================================

function Initialize-DewinLogging {
    [CmdletBinding()]
    param([string]$CustomDir)

    $global:DewinTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $global:DewinStats = @{
        Success  = 0
        Warnings = 0
        Errors   = 0
    }

    if (-not $CustomDir) {
        if ($PSScriptRoot) {
            $rootCandidate = if ((Split-Path $PSScriptRoot -Leaf) -eq 'core') {
                Join-Path $PSScriptRoot '..\..\logs'
            } else {
                Join-Path $PSScriptRoot 'logs'
            }
            $CustomDir = [System.IO.Path]::GetFullPath($rootCandidate)
        } else {
            $CustomDir = Join-Path -Path "$env:LOCALAPPDATA\dewin" -ChildPath 'logs'
        }
    }

    try {
        if (-not (Test-Path $CustomDir)) {
            New-Item -Path $CustomDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        $CustomDir = Join-Path -Path $env:TEMP -ChildPath 'dewin-logs'
        if (-not (Test-Path $CustomDir)) { New-Item -Path $CustomDir -ItemType Directory -Force | Out-Null }
    }

    $timestampStr = Get-Date -Format 'yyyyMMdd_HHmmss'
    $global:DewinLogPath = Join-Path -Path $CustomDir -ChildPath "dewin_${timestampStr}.log"
    $global:DewinLatestLog = Join-Path -Path $CustomDir -ChildPath 'dewin-latest.log'
}

function Write-DewinLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'STEP', 'RAW')]
        [string]$Level = 'INFO',
        [switch]$NoConsole,
        [scriptblock]$OnUiLog
    )

    $timeNow = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logPrefix = "[$timeNow] [$Level]"

    if (-not $NoConsole -and $Level -ne 'RAW') {
        switch ($Level) {
            'SUCCESS' { Write-Host $Message -ForegroundColor Green; if ($global:DewinStats) { $global:DewinStats.Success++ } }
            'WARN'    { Write-Host $Message -ForegroundColor Yellow; if ($global:DewinStats) { $global:DewinStats.Warnings++ } }
            'ERROR'   { Write-Host $Message -ForegroundColor Red; if ($global:DewinStats) { $global:DewinStats.Errors++ } }
            'STEP'    { Write-Host $Message -ForegroundColor Cyan }
            Default   { Write-Host $Message -ForegroundColor Gray }
        }
    }

    $logTarget = if ($global:DewinLogPath) { $global:DewinLogPath } else { $DewinLogPath }

    # Notificacao para interface grafica via fila sincronizada thread-safe
    $s = if ($global:sync) { $global:sync }
         elseif ($global:DewinSync) { $global:DewinSync }
         elseif ($sync) { $sync }
         elseif ($DewinSync) { $DewinSync }
         else { $null }

    if ($s -and ($null -ne $s.Messages)) {
        try {
            $uiEntry = if ($Level -eq 'RAW') { $Message } else { "$logPrefix $Message" }
            [void]$s.Messages.Add($uiEntry)
        } catch {}
    } elseif ($OnUiLog) {
        try { & $OnUiLog $Message $Level } catch {}
    }

    if ($logTarget) {
        $entry = if ($Level -eq 'RAW') { $Message } else { "$logPrefix $Message" }
        try {
            Add-Content -LiteralPath $logTarget -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}


# --- MÃ³dulo: src\core\Registry.ps1 ---
# ==============================================================================
# DEWIN Core: Utilitários de Registro
# ==============================================================================

function Set-DewinReg {
    [CmdletBinding()]
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

function Remove-DewinReg {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [string]$Name
    )
    try {
        if (Test-Path $Path) {
            if ($Name) {
                Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue | Out-Null
                Write-DewinLog -Level INFO -Message "Reg Removido: $Path\$Name" -NoConsole
            } else {
                Remove-Item -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                Write-DewinLog -Level INFO -Message "Chave Removida: $Path" -NoConsole
            }
        }
    } catch {
        Write-DewinLog -Level WARN -Message "Reg Remove Falha: $Path - $($_.Exception.Message)" -NoConsole
    }
}


# --- MÃ³dulo: src\core\Hardware.ps1 ---
# ==============================================================================
# DEWIN Core: Detecção Inteligente de Hardware
# ==============================================================================

function Get-DewinHardwareInfo {
    [CmdletBinding()]
    param()

    $info = [ordered]@{
        IsAdmin          = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Manufacturer     = 'Desconhecido'
        Model            = 'Desconhecido'
        Processor        = 'Processador'
        RamTotalGB       = 0
        GpuNames         = 'Não detectada'
        WinVersion       = 'Windows 11'
        WinBuild         = 0
        IsLaptop         = $false
        DeviceTypeStr    = 'Desktop'
        RecommendedProfile = 'Medium'
    }

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs.Manufacturer) { $info.Manufacturer = $cs.Manufacturer.Trim() }
        if ($cs.Model) { $info.Model = $cs.Model.Trim() }
    } catch {}

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu.Name) { $info.Processor = $cpu.Name.Trim() }
    } catch {}

    try {
        $memSum = (Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object Capacity -Sum).Sum
        if ($memSum) { $info.RamTotalGB = [math]::Round($memSum / 1GB) }
    } catch {}

    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $gpuList = ($gpus | ForEach-Object { $_.Name }) -join ' | '
        if ($gpuList) { $info.GpuNames = $gpuList }
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $info.WinVersion = $os.Caption
            $info.WinBuild = [int]$os.BuildNumber
        }
    } catch {}

    try {
        $enclosure = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
        $chassisTypes = @($enclosure.ChassisTypes)
        $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        $info.IsLaptop = ($chassisTypes | Where-Object { $_ -in @(8, 9, 10, 11, 12, 14, 18, 21, 31, 32) }) -or $hasBattery
    } catch {
        $info.IsLaptop = $false
    }

    $info.DeviceTypeStr = if ($info.IsLaptop) { 'Notebook' } else { 'Desktop' }
    $info.RecommendedProfile = 'Medium'

    return [PSCustomObject]$info
}


# --- MÃ³dulo: src\tweaks\InterfaceTweaks.ps1 ---
# ==============================================================================
# DEWIN Tweaks: Interface, Barra de Tarefas & Explorer
# ==============================================================================

function Restart-DewinExplorer {
    [CmdletBinding()]
    param()
    Write-DewinLog -Level STEP -Message '[*] Atualizando Windows Explorer...'
    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Start-Process "$env:SystemRoot\explorer.exe"
    }
    Write-DewinLog -Level INFO -Message 'Windows Explorer reiniciado com sucesso.' -NoConsole
}

function Invoke-DewinInterfaceTweaks {
    [CmdletBinding()]
    param(
        [switch]$HideSearch = $true,
        [switch]$HideTaskView = $true,
        [switch]$CenterTaskbar = $true,
        [switch]$TaskbarEndTask = $true,
        [switch]$ClassicContextMenu = $true,
        [switch]$LaunchToThisPC = $true,
        [switch]$ShowExtensionsAndHidden = $true,
        [switch]$AlwaysShowScrollbars = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando otimizações de interface e barra de tarefas...'
    $advExplorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    # Barra de tarefas: Ocultar caixa de pesquisa
    if ($HideSearch) {
        Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0
    }

    # Desativação de Destaques de Pesquisa (desenhos/notícias do Bing), Pesquisa na Nuvem e Localização na Busca
    $searchPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-DewinReg -Path $searchPol -Name 'EnableDynamicContentInWSB' -Value 0
    Set-DewinReg -Path $searchPol -Name 'AllowCloudSearch' -Value 0
    Set-DewinReg -Path $searchPol -Name 'AllowSearchToUseLocation' -Value 0
    Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsDynamicSearchBoxEnabled' -Value 0

    # Barra de tarefas: Ocultar botão de multitarefa (Task View)
    if ($HideTaskView) {
        Set-DewinReg -Path $advExplorer -Name 'ShowTaskViewButton' -Value 0
    }

    # Barra de tarefas: Alinhamento centralizado (Padrão Windows 11)
    if ($CenterTaskbar) {
        Set-DewinReg -Path $advExplorer -Name 'TaskbarAl' -Value 1
    }

    # Barra de tarefas: Opção "Finalizar Tarefa" no botão direito
    if ($TaskbarEndTask) {
        Set-DewinReg -Path "$advExplorer\TaskbarDeveloperSettings" -Name 'TaskbarEndTask' -Value 1
    }

    # Menu de contexto clássico (estilo Windows 10 direto no botão direito)
    if ($ClassicContextMenu) {
        $clsidPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        if (-not (Test-Path $clsidPath)) { New-Item -Path $clsidPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $clsidPath -Name '(Default)' -Value '' -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Abrir Explorer em "Este Computador" & Remover Início e Galeria
    if ($LaunchToThisPC) {
        Set-DewinReg -Path $advExplorer -Name 'LaunchTo' -Value 1
        Set-DewinReg -Path 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0
        Set-DewinReg -Path 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0
    }

    # Exibir extensões de arquivos conhecidas e pastas ocultas
    if ($ShowExtensionsAndHidden) {
        Set-DewinReg -Path $advExplorer -Name 'HideFileExt' -Value 0
        Set-DewinReg -Path $advExplorer -Name 'Hidden' -Value 1
    }

    # Manter barras de rolagem sempre visíveis
    if ($AlwaysShowScrollbars) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility' -Name 'DynamicScrollbars' -Value 0
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Interface, barra de tarefas e Explorer otimizados.'
}


# --- MÃ³dulo: src\tweaks\PerformanceTweaks.ps1 ---
# ==============================================================================
# DEWIN Tweaks: Desempenho, Latência, Jogos e SSD
# ==============================================================================

function Invoke-DewinPerformanceTweaks {
    [CmdletBinding()]
    param(
        [switch]$OptimizeNetworkLatency = $true,
        [switch]$DisableGameDVR = $true,
        [switch]$LinearMouse = $true,
        [switch]$DisableStickyKeys = $true,
        [switch]$InstantMenuDelay = $true,
        [switch]$OptimizeSsdAccess = $true,
        [switch]$CleanTempFiles = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando otimizações de desempenho, latência e SSD...'

    # Latência de Rede e Priorização Multimídia/Jogos
    if ($OptimizeNetworkLatency) {
        $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Set-DewinReg -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type 'DWord'
        Set-DewinReg -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -Type 'DWord'
    }

    # Desativação de GameDVR e Captura em Segundo Plano
    if ($DisableGameDVR) {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
        Set-DewinReg -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'HistoricalCaptureEnabled' -Value 0
    }

    # Resposta Linear do Mouse (1:1 sem aceleração)
    if ($LinearMouse) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type 'String'
    }

    # Desativação do popup irritante de Teclas de Aderência (Shift 5x)
    if ($DisableStickyKeys) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '122' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value '58' -Type 'String'
    }

    # Eliminação do atraso artificial de menus suspensos (MenuShowDelay = 0ms)
    if ($InstantMenuDelay) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type 'String'
    }

    # Otimização de SSD (Desativar timestamp de último acesso desnecessário)
    if ($OptimizeSsdAccess) {
        try { fsutil.exe behavior set disablelastaccess 1 2>$null | Out-Null } catch {}
    }

    # Limpeza de Pastas Temporárias
    if ($CleanTempFiles) {
        Remove-Item -Path "$Env:Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Desempenho, latência de rede, GameDVR e SSD calibrados.'
}


# --- MÃ³dulo: src\tweaks\PrivacyTweaks.ps1 ---
# ==============================================================================
# DEWIN Tweaks: Privacidade, Telemetria & Debloat
# ==============================================================================

function Invoke-DewinPrivacyTweaks {
    [CmdletBinding()]
    param(
        [switch]$DisableTelemetry = $true,
        [switch]$DisableCeipTasks = $true,
        [switch]$DisableCopilotRecall = $true,
        [switch]$DisableBingSearch = $true,
        [switch]$DebloatEdge = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando ajustes de privacidade e desativando telemetria...'

    # Telemetria do Windows e Serviços de Diagnóstico
    if ($DisableTelemetry) {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0

        @('DiagTrack', 'dmwappushservice') | ForEach-Object {
            try {
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue | Out-Null
                Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        }

        # Telemetria de Aplicativos e Coletor de Inventário
        $appCompatPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
        Set-DewinReg -Path $appCompatPol -Name 'AITEnable' -Value 0
        Set-DewinReg -Path $appCompatPol -Name 'DisableInventory' -Value 1

        # Conteúdo de Nuvem, Dicas do Windows e Bloqueio de Apps Patrocinados
        $cloudPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Set-DewinReg -Path $cloudPol -Name 'DisableCloudOptimizedContent' -Value 1
        Set-DewinReg -Path $cloudPol -Name 'DisableConsumerAccountStateContent' -Value 1
        Set-DewinReg -Path $cloudPol -Name 'DisableSoftLanding' -Value 1
        Set-DewinReg -Path $cloudPol -Name 'DisableWindowsConsumerFeatures' -Value 1

        $cdmPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Set-DewinReg -Path $cdmPath -Name 'SubscribedContent-338389Enabled' -Value 0
        Set-DewinReg -Path $cdmPath -Name 'SubscribedContent-310093Enabled' -Value 0
        Set-DewinReg -Path $cdmPath -Name 'SystemPaneSuggestionsEnabled' -Value 0

        # Coleta de Dados de Fala e Escrita na Nuvem
        $speechPol = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'
        Set-DewinReg -Path $speechPol -Name 'AllowSpeechModelUpdate' -Value 0
        Set-DewinReg -Path $speechPol -Name 'RestrictImplicitInkCollection' -Value 1
        Set-DewinReg -Path $speechPol -Name 'RestrictImplicitTextCollection' -Value 1

        # Relatório de Erros do Windows (WER) e Despejo de Logs de Falhas
        $werPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
        Set-DewinReg -Path $werPol -Name 'Disabled' -Value 1
        Set-DewinReg -Path $werPol -Name 'LoggingDisabled' -Value 1
        Set-DewinReg -Path $werPol -Name 'DoReport' -Value 0

        # Sincronização de Configurações na Nuvem
        $syncPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
        Set-DewinReg -Path $syncPol -Name 'DisableSettingSync' -Value 1
        Set-DewinReg -Path $syncPol -Name 'DisableSettingSyncUserOverride' -Value 1
    }

    # Desativação de Tarefas Agendadas Ociosas de Telemetria (CEIP)
    if ($DisableCeipTasks) {
        $tasksToDisable = @(
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Autochk\Proxy'
        )
        foreach ($task in $tasksToDisable) {
            try { Disable-ScheduledTask -TaskPath ($task | Split-Path) -TaskName ($task | Split-Path -Leaf) -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }

    # Desativação de Copilot, IA Recall e Cortana
    if ($DisableCopilotRecall) {
        Set-DewinReg -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
        Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowCopilotButton' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0
    }

    # Desativação do Bing e Sugestões na Pesquisa do Iniciar
    if ($DisableBingSearch) {
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0
    }

    # Debloat do Microsoft Edge (Mantém o WebView2 100% funcional)
    if ($DebloatEdge) {
        $edgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Set-DewinReg -Path $edgePol -Name 'MetricsReportingEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'PersonalizationReportingEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'ShowHomeButton' -Value 0
        Set-DewinReg -Path $edgePol -Name 'HideFirstRunExperience' -Value 1
        Set-DewinReg -Path $edgePol -Name 'StartupBoostEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'BackgroundModeEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'PreventPreheating' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main' -Name 'AllowPrelaunch' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader' -Name 'AllowTabPreloading' -Value 0
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Telemetria, CEIP, Copilot, Bing e Edge otimizados.'
}

function Invoke-DewinDebloat {
    [CmdletBinding()]
    param()

    Write-DewinLog -Level STEP -Message '[*] Removendo 28 bloatwares UWP de terceiros e publicidade...'

    $bloatwareList = @(
        'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp',
        'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.People', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub',
        'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
        'MicrosoftTeams', 'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10',
        'Microsoft.Microsoft3DViewer', 'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp',
        'Microsoft.GamingApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxSpeechToTextOverlay',
        'SpotifyAB.SpotifyMusic', 'Disney.37853FC22B2CE', 'ByteDancePte.Ltd.TikTok',
        'Facebook.InstagramBeta', 'Amazon.com.AmazonPrimeVideo', 'Netflix.Netflix',
        'Microsoft.BingFinance'
    )

    $removedCount = 0
    $provisioned = @(try { Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue } catch { @() })
    $provLookup = @{}
    foreach ($p in $provisioned) {
        if ($p.DisplayName) { $provLookup[$p.DisplayName] = $p.PackageName }
    }

    foreach ($app in $bloatwareList) {
        try {
            $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removedCount++
            }
            if ($provLookup.ContainsKey($app)) {
                Remove-AppxProvisionedPackage -Online -PackageName $provLookup[$app] -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}
    }

    Write-DewinLog -Level SUCCESS -Message "  [+] Limpeza de $removedCount bloatwares concluída."
}


# --- MÃ³dulo: src\tweaks\SystemTweaks.ps1 ---
# ==============================================================================
# DEWIN Tweaks: Sistema, GPU, Energia & Serviços
# ==============================================================================

function Invoke-DewinSystemTweaks {
    [CmdletBinding()]
    param(
        [bool]$IsLaptop = $false,
        [bool]$IsDev = $false,
        [int]$RamGB = 16,
        [switch]$CalibrateGpu = $true,
        [switch]$SmartHibernation = $true,
        [switch]$DisableReservedStorage = $true,
        [switch]$OptimizeSvcHost = $true,
        [switch]$EnableLongPaths = $true,
        [switch]$DisableLockScreen = $true,
        [switch]$DualBootUtc = $false
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando calibrações de sistema, GPU e energia...'

    # Calibração de GPU (TdrDelay = 8s, TdrDdiDelay = 8s, HAGS = 2)
    if ($CalibrateGpu) {
        $gfxPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        Set-DewinReg -Path $gfxPath -Name 'TdrDelay' -Value 8
        Set-DewinReg -Path $gfxPath -Name 'TdrDdiDelay' -Value 8
        Set-DewinReg -Path $gfxPath -Name 'HwSchMode' -Value 2
    }

    # Gerenciamento Inteligente de Hibernação e Energia
    if ($SmartHibernation) {
        if ($IsLaptop) {
            Write-DewinLog -Level STEP -Message '  [*] Configurando hibernação segura compacta e economia de bateria para Notebook...'
            try {
                powercfg.exe /hibernate on 2>$null | Out-Null
                powercfg.exe /h /type reduced 2>$null | Out-Null
            } catch {}

            # Otimização de bateria: suspende indexação pesada quando desconectado da tomada
            Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'PreventIndexingOnBattery' -Value 1
        } else {
            Write-DewinLog -Level STEP -Message '  [*] Desativando hibernação para Desktop (recuperando espaço em disco SSD)...'
            try { powercfg.exe /hibernate off 2>$null | Out-Null } catch {}

            # Desktop: desativa checagens de sensores inexistentes (luminosidade/giroscópio)
            Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableSensors' -Value 1
        }
    }

    # Desativação do Popup Invasivo do Assistente de Compatibilidade de Programas (PCA)
    Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisablePCA' -Value 1

    # Desativação de Armazenamento Reservado (~7 GB liberados de SSD)
    if ($DisableReservedStorage) {
        try { Set-WindowsReservedStorageState -State Disabled -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    # Calibração de SvcHost de acordo com a memória RAM
    if ($OptimizeSvcHost -and $RamGB -gt 0) {
        $svcThreshold = if ($RamGB -ge 32) { 33554432 } elseif ($RamGB -ge 16) { 16777216 } else { 8388608 }
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Value $svcThreshold
    }

    # Habilitação de Caminhos Longos no Sistema de Arquivos (MAX_PATH)
    if ($EnableLongPaths) {
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1
    }

    # Pular Tela de Bloqueio Estática e SCOOBE
    if ($DisableLockScreen) {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'DisablePrivacyExperience' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' -Name 'ScoobeSystemSettingEnabled' -Value 0
    }

    # Tweaks Exclusivos para Perfil Desenvolvedor
    if ($IsDev) {
        # Mensagens detalhadas de inicialização e desligamento
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'verbosestatus' -Value 1
        # Desativação de aviso repetitivo de RDP não assinado
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client' -Name 'RedirectionWarningDialogVersion' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Terminal Server Client' -Name 'RdpLaunchConsentAccepted' -Value 1
    }

    # Sincronização de Relógio UTC para Dual Boot (Linux / Fedora)
    if ($DualBootUtc) {
        Write-DewinLog -Level STEP -Message '[*] Configurando relógio da placa-mãe em UTC para Dual Boot Linux...'
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal' -Value 1 -Type 'QWord'
        try {
            Set-Service w32time -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service w32time -ErrorAction SilentlyContinue
            & "$env:SystemRoot\System32\w32tm.exe" /config /update | Out-Null
            Start-Sleep -Milliseconds 1200
            & "$env:SystemRoot\System32\w32tm.exe" /resync /force | Out-Null
            Write-DewinLog -Level SUCCESS -Message '  [+] Relógio em UTC configurado e sincronizado com o servidor oficial NTP.'
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Não foi possível sincronizar o relógio automaticamente: $($_.Exception.Message)"
        }
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Calibrações de sistema, GPU e energia aplicadas com sucesso.'
}


# --- MÃ³dulo: src\packages\SoftwareInstaller.ps1 ---
# ==============================================================================
# DEWIN Packages: Instalador de Softwares via Winget
# ==============================================================================

function Get-DewinSoftwareCatalog {
    [CmdletBinding()]
    param()

    return @(
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Name = 'Visual C++ 2015-2022 (x64)'; Category = 'Essenciais'; Default = $true },
        @{ Id = 'Microsoft.VCRedist.2015+.x86'; Name = 'Visual C++ 2015-2022 (x86)'; Category = 'Essenciais'; Default = $true },
        @{ Id = '7zip.7zip';                   Name = '7-Zip (Compactador de Arquivos)'; Category = 'Essenciais'; Default = $true },
        @{ Id = 'Google.Chrome';               Name = 'Google Chrome'; Category = 'Navegadores'; Default = $true },
        @{ Id = 'Microsoft.VisualStudioCode';  Name = 'Visual Studio Code'; Category = 'Desenvolvimento'; Default = $false },
        @{ Id = 'Git.Git';                     Name = 'Git for Windows'; Category = 'Desenvolvimento'; Default = $false },
        @{ Id = 'Discord.Discord';             Name = 'Discord'; Category = 'Comunicação'; Default = $false },
        @{ Id = 'Valve.Steam';                 Name = 'Steam'; Category = 'Jogos'; Default = $false },
        @{ Id = 'VideoLAN.VLC';                Name = 'VLC Media Player'; Category = 'Multimídia'; Default = $false },
        @{ Id = 'Spotify.Spotify';             Name = 'Spotify'; Category = 'Multimídia'; Default = $false }
    )
}

function Install-DewinSoftware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$AppIds,
        [scriptblock]$OnProgress
    )

    if (-not $AppIds -or $AppIds.Count -eq 0) { return }

    Write-DewinLog -Level STEP -Message "[*] Iniciando instalação de $($AppIds.Count) pacotes via Winget..."

    $hasInternet = $false
    try {
        $hasInternet = [bool](Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue)
    } catch {}

    if (-not $hasInternet) {
        Write-DewinLog -Level WARN -Message '  [!] Sem conexão com a internet. Instalação de pacotes ignorada.'
        return
    }

    $catalog = Get-DewinSoftwareCatalog
    $total = $AppIds.Count
    $current = 0

    foreach ($id in $AppIds) {
        $current++
        $appInfo = $catalog | Where-Object { $_.Id -eq $id }
        $appName = if ($appInfo) { $appInfo.Name } else { $id }

        if ($OnProgress) {
            $pct = [int](10 + (($current / $total) * 85))
            try { & $OnProgress $pct "Instalando ($current/$total): $appName..." } catch {}
        }

        Write-DewinLog -Level STEP -Message "  [*] Instalando $appName ($id)..."
        try {
            $wingetProc = Start-Process -FilePath 'winget.exe' -ArgumentList "install --id `"$id`" --exact --silent --accept-package-agreements --accept-source-agreements --force" -NoNewWindow -PassThru -Wait
            if ($wingetProc.ExitCode -eq 0) {
                Write-DewinLog -Level SUCCESS -Message "  [+] $appName instalado com sucesso."
            } else {
                Write-DewinLog -Level INFO -Message "  [i] Winget $appName finalizou com código $($wingetProc.ExitCode)" -NoConsole
            }
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Falha ao instalar ${appName}: $($_.Exception.Message)"
        }
    }
}


# --- MÃ³dulo: src\packages\WindowsFeatures.ps1 ---
# ==============================================================================
# DEWIN Packages: Recursos Opcionais do Windows (DISM)
# ==============================================================================

function Get-DewinFeaturesCatalog {
    [CmdletBinding()]
    param()

    return @(
        @{ Id = 'NetFx3';                          Name = '.NET Framework 3.5 (Compatibilidade Legada)'; Default = $true },
        @{ Id = 'VirtualMachinePlatform';          Name = 'Plataforma de Máquina Virtual (Base WSL2)'; Default = $false },
        @{ Id = 'Microsoft-Windows-Subsystem-Linux'; Name = 'Subsistema do Windows para Linux (WSL2)'; Default = $false },
        @{ Id = 'Microsoft-Hyper-V-All';            Name = 'Hyper-V (Virtualização Nativa)'; Default = $false },
        @{ Id = 'Containers-DisposableClientVM';   Name = 'Windows Sandbox (Área Restrita)'; Default = $false }
    )
}

function Enable-DewinFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$FeatureNames,
        [scriptblock]$OnProgress
    )

    if (-not $FeatureNames -or $FeatureNames.Count -eq 0) { return }

    Write-DewinLog -Level STEP -Message "[*] Configurando $($FeatureNames.Count) recursos opcionais do Windows via DISM..."

    $total = $FeatureNames.Count
    $current = 0

    foreach ($feat in $FeatureNames) {
        $current++
        if ($OnProgress) {
            $pct = [int](10 + (($current / $total) * 85))
            try { & $OnProgress $pct "Habilitando ($current/$total): recurso $feat..." } catch {}
        }
        Write-DewinLog -Level STEP -Message "  [*] Habilitando recurso: $feat..."
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-DewinLog -Level SUCCESS -Message "  [+] Recurso $feat pronto."
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Não foi possível habilitar ${feat}: $($_.Exception.Message)"
        }
    }
}


# --- MÃ³dulo: src\engine\Presets.ps1 ---
# ==============================================================================
# DEWIN Engine: Mapeamento de Perfis de Otimização e Recursos
# ==============================================================================

function Get-DewinTweakPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('Light', 'Medium', 'Aggressive', 'PoucoOtimizado', 'Medio', 'Completo', 'Maximo')]
        [string]$Level = 'Medium'
    )

    $normLevel = switch -Regex ($Level) {
        '^(Light|PoucoOtimizado)$' { 'Light' }
        '^(Aggressive|Completo|Maximo)$' { 'Aggressive' }
        Default { 'Medium' }
    }

    $isLight = ($normLevel -eq 'Light')
    $isAggressive = ($normLevel -eq 'Aggressive')
    $isMediumOrHigher = ($normLevel -in @('Medium', 'Aggressive'))

    $tweaks = [ordered]@{
        # Interface e Barra de Tarefas
        HideSearch              = [bool]$isMediumOrHigher
        HideTaskView            = [bool]$isMediumOrHigher
        CenterTaskbar           = $true
        TaskbarEndTask          = $true
        ClassicContextMenu      = [bool]$isMediumOrHigher
        LaunchToThisPC          = [bool]$isMediumOrHigher
        ShowExtensionsAndHidden = $true
        AlwaysShowScrollbars    = $true

        # Desempenho, Latência e Armazenamento
        OptimizeNetworkLatency  = [bool]$isMediumOrHigher
        DisableGameDVR          = [bool]$isMediumOrHigher
        LinearMouse             = [bool]$isMediumOrHigher
        DisableStickyKeys       = $true
        InstantMenuDelay        = $true
        OptimizeSsdAccess       = $true
        CleanTempFiles          = $true

        # Privacidade, Telemetria e Aplicativos Padrão
        DisableTelemetry        = $true
        DisableCeipTasks        = $true
        DisableCopilotRecall    = [bool]$isMediumOrHigher
        DisableBingSearch       = $true
        DebloatEdge             = [bool]$isMediumOrHigher
        RemoveUwpBloat          = [bool]$isMediumOrHigher

        # Sistema, Gráficos e Energia
        CalibrateGpu            = [bool]$isMediumOrHigher
        SmartHibernation        = [bool]$isMediumOrHigher
        DisableReservedStorage  = [bool]$isMediumOrHigher
        OptimizeSvcHost         = $true
        EnableLongPaths         = $true
        DisableLockScreen       = [bool]$isMediumOrHigher
        IsDev                   = [bool]$isAggressive
        DualBootUtc             = [bool]$isAggressive
    }

    return [PSCustomObject]@{
        Level       = $normLevel
        Tweaks      = $tweaks
        Description = switch ($normLevel) {
            'Light'      { 'Pouco Otimizado: Otimizações essenciais e seguras, mantendo a experiência clássica do Windows 11 intacta.' }
            'Medium'     { 'Médio (Recomendado): Equilíbrio perfeito entre desempenho, redução de telemetria e debloat para o dia a dia.' }
            'Aggressive' { '100% Otimizado: Máximo desempenho, menor latência, zero telemetria e configurações completas ativadas.' }
        }
    }
}

function Get-DewinFeaturePreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [ValidateSet('General', 'Geral', 'Dev')]
        [string]$Profile = 'General'
    )

    $isDev = ($Profile -eq 'Dev')

    $features = @('NetFx3')
    if ($isDev) {
        $features += @(
            'VirtualMachinePlatform',
            'Microsoft-Windows-Subsystem-Linux',
            'Microsoft-Hyper-V-All',
            'Containers-DisposableClientVM'
        )
    }

    return [PSCustomObject]@{
        Profile     = if ($isDev) { 'Dev' } else { 'General' }
        Features    = $features
        Description = if ($isDev) {
            'Desenvolvedor: Habilita todos os recursos opcionais (.NET 3.5, WSL2, Plataforma de VM, Hyper-V e Sandbox).'
        } else {
            'Geral: Habilita apenas o .NET Framework 3.5 para compatibilidade com softwares e jogos legados.'
        }
    }
}

function Get-DewinPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('Light', 'Medium', 'Aggressive', 'Dev', 'DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral')]
        [string]$Name
    )

    $tweakLevel = switch -Regex ($Name) {
        'Light'                                    { 'Light' }
        '(Aggressive|.*Dev)'                       { 'Aggressive' }
        Default                                    { 'Medium' }
    }

    $featProfile = if ($Name -like '*Dev*') { 'Dev' } else { 'General' }

    $tweakPreset = Get-DewinTweakPreset -Level $tweakLevel
    $featPreset = Get-DewinFeaturePreset -Profile $featProfile

    return [PSCustomObject]@{
        Name        = $Name
        Tweaks      = $tweakPreset.Tweaks
        Apps        = @() # Aplicativos não são pré-marcados por presets
        Features    = $featPreset.Features
        Description = $tweakPreset.Description
    }
}


# --- MÃ³dulo: src\engine\Runner.ps1 ---
# ==============================================================================
# DEWIN Engine: Orquestrador de Execução e Otimização
# ==============================================================================

function Invoke-DewinTweaksOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][hashtable]$Tweaks,
        [PSCustomObject]$Hardware,
        [scriptblock]$OnProgress
    )

    if (-not $Hardware) { $Hardware = Get-DewinHardwareInfo }

    $updateProgress = {
        param([int]$Percent, [string]$Status)
        $s = if ($global:sync) { $global:sync } elseif ($sync) { $sync } else { $null }
        if ($s) {
            $s.Percent = [int]$Percent
            $s.Status = [string]$Status
        }
        if ($OnProgress) { try { & $OnProgress $Percent $Status } catch {} }
    }

    & $updateProgress 5 "Inicializando auditoria e configurações de sistema..."

    # 1. Cabecalho de Auditoria
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "DEWIN BOOSTER - REGISTRO DE AUDITORIA E OTIMIZAÇÕES"
    Write-DewinLog -Level RAW -Message "Data e Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-DewinLog -Level RAW -Message "Sistema Operacional: $($Hardware.WinVersion) (Build $($Hardware.WinBuild))"
    Write-DewinLog -Level RAW -Message "Dispositivo: $($Hardware.Manufacturer) $($Hardware.Model) ($($Hardware.DeviceTypeStr))"
    Write-DewinLog -Level RAW -Message "Memória RAM: $($Hardware.RamTotalGB) GB"
    Write-DewinLog -Level RAW -Message "GPU(s): $($Hardware.GpuNames)"
    Write-DewinLog -Level RAW -Message "Usuário Administrador: $($Hardware.IsAdmin)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    # 2. Calibrações de Sistema, GPU e Energia
    & $updateProgress 15 "Configurando tolerâncias gráficas, energia e serviços..."
    Invoke-DewinSystemTweaks -IsLaptop ([bool]$Tweaks['IsLaptop']) `
                            -IsDev ([bool]$Tweaks['IsDev']) `
                            -RamGB ([int]$Hardware.RamTotalGB) `
                            -CalibrateGpu:([bool]$Tweaks['CalibrateGpu']) `
                            -SmartHibernation:([bool]$Tweaks['SmartHibernation']) `
                            -DisableReservedStorage:([bool]$Tweaks['DisableReservedStorage']) `
                            -OptimizeSvcHost:([bool]$Tweaks['OptimizeSvcHost']) `
                            -EnableLongPaths:([bool]$Tweaks['EnableLongPaths']) `
                            -DisableLockScreen:([bool]$Tweaks['DisableLockScreen']) `
                            -DualBootUtc:([bool]$Tweaks['DualBootUtc'])

    # 3. Privacidade e Debloat
    & $updateProgress 35 "Aplicando ajustes de privacidade e telemetria..."
    Invoke-DewinPrivacyTweaks -DisableTelemetry:([bool]$Tweaks['DisableTelemetry']) `
                             -DisableCeipTasks:([bool]$Tweaks['DisableCeipTasks']) `
                             -DisableCopilotRecall:([bool]$Tweaks['DisableCopilotRecall']) `
                             -DisableBingSearch:([bool]$Tweaks['DisableBingSearch']) `
                             -DebloatEdge:([bool]$Tweaks['DebloatEdge'])

    if ([bool]$Tweaks['RemoveUwpBloat']) {
        & $updateProgress 50 "Removendo aplicativos pré-instalados desnecessários..."
        Invoke-DewinDebloat
    }

    # 4. Interface e Barra de Tarefas
    & $updateProgress 65 "Otimizando interface, barra de tarefas e Explorador de Arquivos..."
    Invoke-DewinInterfaceTweaks -HideSearch:([bool]$Tweaks['HideSearch']) `
                               -HideTaskView:([bool]$Tweaks['HideTaskView']) `
                               -CenterTaskbar:([bool]$Tweaks['CenterTaskbar']) `
                               -TaskbarEndTask:([bool]$Tweaks['TaskbarEndTask']) `
                               -ClassicContextMenu:([bool]$Tweaks['ClassicContextMenu']) `
                               -LaunchToThisPC:([bool]$Tweaks['LaunchToThisPC']) `
                               -ShowExtensionsAndHidden:([bool]$Tweaks['ShowExtensionsAndHidden']) `
                               -AlwaysShowScrollbars:([bool]$Tweaks['AlwaysShowScrollbars'])

    # 5. Desempenho e Latência
    & $updateProgress 80 "Otimizando latência de rede, gravação de jogos e SSD..."
    Invoke-DewinPerformanceTweaks -OptimizeNetworkLatency:([bool]$Tweaks['OptimizeNetworkLatency']) `
                                 -DisableGameDVR:([bool]$Tweaks['DisableGameDVR']) `
                                 -LinearMouse:([bool]$Tweaks['LinearMouse']) `
                                 -DisableStickyKeys:([bool]$Tweaks['DisableStickyKeys']) `
                                 -InstantMenuDelay:([bool]$Tweaks['InstantMenuDelay']) `
                                 -OptimizeSsdAccess:([bool]$Tweaks['OptimizeSsdAccess']) `
                                 -CleanTempFiles:([bool]$Tweaks['CleanTempFiles'])

    # 6. Atualização do Windows Explorer (apenas se houver tweaks de interface aplicados)
    $hasInterfaceChanges = [bool]($Tweaks['HideSearch'] -or $Tweaks['HideTaskView'] -or $Tweaks['CenterTaskbar'] -or `
                                 $Tweaks['TaskbarEndTask'] -or $Tweaks['ClassicContextMenu'] -or $Tweaks['LaunchToThisPC'] -or `
                                 $Tweaks['ShowExtensionsAndHidden'] -or $Tweaks['AlwaysShowScrollbars'] -or $Tweaks['InstantMenuDelay'])
    if ($hasInterfaceChanges) {
        & $updateProgress 95 "Recarregando interface do Windows Explorer para aplicar alterações..."
        Restart-DewinExplorer
    }

    # 7. Conclusão e Sumário
    $elapsedSec = if ($global:DewinTimer) { [math]::Round($global:DewinTimer.Elapsed.TotalSeconds, 1) } else { 0 }
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "OTIMIZAÇÕES APLICADAS COM SUCESSO"
    Write-DewinLog -Level RAW -Message "Tempo Total: $elapsedSec segundos"
    Write-DewinLog -Level RAW -Message "Estatísticas: Sucessos=$($global:DewinStats.Success), Avisos=$($global:DewinStats.Warnings), Erros=$($global:DewinStats.Errors)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    try {
        Copy-Item -Path $global:DewinLogPath -Destination $global:DewinLatestLog -Force -ErrorAction SilentlyContinue
    } catch {}

    & $updateProgress 100 "Otimizações aplicadas com sucesso em $elapsedSec s."
}

function Invoke-DewinSoftwaresOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$Apps,
        [scriptblock]$OnProgress
    )

    $updateProgress = {
        param([int]$Percent, [string]$Status)
        $s = if ($global:sync) { $global:sync } elseif ($sync) { $sync } else { $null }
        if ($s) {
            $s.Percent = [int]$Percent
            $s.Status = [string]$Status
        }
        if ($OnProgress) { try { & $OnProgress $Percent $Status } catch {} }
    }

    & $updateProgress 5 "Inicializando gerenciador de pacotes Winget..."
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "DEWIN BOOSTER - INSTALAÇÃO DE SOFTWARES"
    Write-DewinLog -Level RAW -Message "Data e Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-DewinLog -Level RAW -Message "Quantidade de Softwares Selecionados: $($Apps.Count)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    & $updateProgress 10 "Instalando $($Apps.Count) programas selecionados via Winget..."
    Install-DewinSoftware -AppIds $Apps -OnProgress {
        param($pct, $msg)
        & $updateProgress $pct $msg
    }

    $elapsedSec = if ($global:DewinTimer) { [math]::Round($global:DewinTimer.Elapsed.TotalSeconds, 1) } else { 0 }
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "INSTALAÇÃO DE SOFTWARES FINALIZADA"
    Write-DewinLog -Level RAW -Message "Tempo Total: $elapsedSec segundos"
    Write-DewinLog -Level RAW -Message '=================================================================='

    try {
        Copy-Item -Path $global:DewinLogPath -Destination $global:DewinLatestLog -Force -ErrorAction SilentlyContinue
    } catch {}

    & $updateProgress 100 "Instalação de programas finalizada em $elapsedSec s."
}

function Invoke-DewinFeaturesOnly {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$Features,
        [scriptblock]$OnProgress
    )

    $updateProgress = {
        param([int]$Percent, [string]$Status)
        $s = if ($global:sync) { $global:sync } elseif ($sync) { $sync } else { $null }
        if ($s) {
            $s.Percent = [int]$Percent
            $s.Status = [string]$Status
        }
        if ($OnProgress) { try { & $OnProgress $Percent $Status } catch {} }
    }

    & $updateProgress 5 "Inicializando módulo DISM do Windows..."
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "DEWIN BOOSTER - RECURSOS OPCIONAIS DO WINDOWS"
    Write-DewinLog -Level RAW -Message "Data e Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-DewinLog -Level RAW -Message "Recursos a Configurar: $($Features.Count)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    Enable-DewinFeatures -FeatureNames $Features -OnProgress {
        param($pct, $msg)
        & $updateProgress $pct $msg
    }

    $elapsedSec = if ($global:DewinTimer) { [math]::Round($global:DewinTimer.Elapsed.TotalSeconds, 1) } else { 0 }
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "RECURSOS DISM CONFIGURADOS COM SUCESSO"
    Write-DewinLog -Level RAW -Message "Tempo Total: $elapsedSec segundos"
    Write-DewinLog -Level RAW -Message '=================================================================='

    try {
        Copy-Item -Path $global:DewinLogPath -Destination $global:DewinLatestLog -Force -ErrorAction SilentlyContinue
    } catch {}

    & $updateProgress 100 "Recursos opcionais configurados com sucesso em $elapsedSec s."
}

function Invoke-DewinExecution {
    [CmdletBinding()]
    param(
        [hashtable]$Tweaks,
        [string[]]$Apps = @(),
        [string[]]$Features = @(),
        [PSCustomObject]$Hardware,
        [scriptblock]$OnProgress
    )

    if ($Tweaks -and $Tweaks.Count -gt 0) {
        Invoke-DewinTweaksOnly -Tweaks $Tweaks -Hardware $Hardware -OnProgress $OnProgress
    }

    if ($Features -and $Features.Count -gt 0) {
        Invoke-DewinFeaturesOnly -Features $Features -OnProgress $OnProgress
    }

    if ($Apps -and $Apps.Count -gt 0) {
        Invoke-DewinSoftwaresOnly -Apps $Apps -OnProgress $OnProgress
    }
}


# --- MÃ³dulo: src\engine\Controller.ps1 ---
# ==============================================================================
# DEWIN Engine: Controlador da Interface Gráfica (WPF)
# ==============================================================================

function New-DewinSessionState {
    param([hashtable]$SyncHashtable)
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    $builtInFunctions = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($iss.Commands |
            Where-Object { $_ -is [System.Management.Automation.Runspaces.SessionStateFunctionEntry] } |
            ForEach-Object { $_.Name }),
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($func in (Get-ChildItem function:\)) {
        if (-not $builtInFunctions.Contains($func.Name)) {
            $iss.Commands.Add(
                (New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $func.Name, $func.Definition)
            )
        }
    }

    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $SyncHashtable, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinSync', $SyncHashtable, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinLogPath', $global:DewinLogPath, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinLatestLog', $global:DewinLatestLog, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinTimer', $global:DewinTimer, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinStats', $global:DewinStats, $null))

    return $iss
}

function Start-DewinGui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$XamlString,
        [PSCustomObject]$Hardware
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (-not $Hardware) {
        $Hardware = Get-DewinHardwareInfo
    }

    # Carregamento do XAML
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($XamlString))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $global:DewinWindow = $window

    # Mapeamento dinâmico de elementos por Nome
    $global:DewinGui = @{}
    $xmlDoc = [xml]$XamlString
    $xmlDoc.SelectNodes('//*[@Name]') | ForEach-Object {
        $name = $_.GetAttribute('Name')
        $global:DewinGui[$name] = $window.FindName($name)
    }
    $gui = $global:DewinGui

    # 1. Preenchimento dos Dados de Hardware
    $gui['txtHardwareBanner'].Text = "Dispositivo: $($Hardware.Manufacturer) $($Hardware.Model) | CPU: $($Hardware.Processor) | RAM: $($Hardware.RamTotalGB) GB | GPU: $($Hardware.GpuNames)"
    $gui['txtDeviceType'].Text = "$($Hardware.DeviceTypeStr) Detectado"

    $recText = if ($Hardware.IsLaptop) {
        "Notebook identificado ($($Hardware.Manufacturer) $($Hardware.Model)). O gerenciamento inteligente ativará hibernação compacta para preservar energia e autonomia ao fechar a tampa."
    } else {
        "Desktop identificado ($($Hardware.Manufacturer) $($Hardware.Model)). O gerenciamento inteligente desativará a hibernação para liberar espaço em disco SSD equivalente à memória RAM."
    }
    $gui['txtRecommendation'].Text = $recText

    # 2. Listas de Controles
    $allTweakChecks = @(
        'chkHideSearch', 'chkHideTaskView', 'chkCenterTaskbar', 'chkTaskbarEndTask',
        'chkClassicContextMenu', 'chkLaunchToThisPC', 'chkShowExtensionsAndHidden', 'chkAlwaysShowScrollbars',
        'chkOptimizeNetworkLatency', 'chkDisableGameDVR', 'chkLinearMouse', 'chkDisableStickyKeys',
        'chkInstantMenuDelay', 'chkOptimizeSsdAccess', 'chkCleanTempFiles',
        'chkDisableTelemetry', 'chkDisableCeipTasks', 'chkDisableCopilotRecall', 'chkDisableBingSearch',
        'chkDebloatEdge', 'chkRemoveUwpBloat',
        'chkCalibrateGpu', 'chkSmartHibernation', 'chkDisableReservedStorage', 'chkOptimizeSvcHost',
        'chkEnableLongPaths', 'chkDisableLockScreen', 'chkIsDev', 'chkDualBootUtc'
    )

    $allAppChecks = @(
        'appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome',
        'appVsCode', 'appGit', 'appDiscord', 'appSteam', 'appVlc', 'appSpotify'
    )

    $allFeatChecks = @(
        'featNetFx3', 'featWsl', 'featVmPlatform', 'featHyperV', 'featSandbox'
    )

    $appMap = @{
        'appVcRedist64' = 'Microsoft.VCRedist.2015+.x64'
        'appVcRedist86' = 'Microsoft.VCRedist.2015+.x86'
        'app7zip'       = '7zip.7zip'
        'appChrome'     = 'Google.Chrome'
        'appVsCode'     = 'Microsoft.VisualStudioCode'
        'appGit'        = 'Git.Git'
        'appDiscord'    = 'Discord.Discord'
        'appSteam'      = 'Valve.Steam'
        'appVlc'        = 'VideoLAN.VLC'
        'appSpotify'    = 'Spotify.Spotify'
    }

    $featMap = @{
        'featNetFx3'      = 'NetFx3'
        'featWsl'         = 'Microsoft-Windows-Subsystem-Linux'
        'featVmPlatform'  = 'VirtualMachinePlatform'
        'featHyperV'      = 'Microsoft-Hyper-V-All'
        'featSandbox'     = 'Containers-DisposableClientVM'
    }

    # 3. Funções de Aplicação de Perfis Separadas por Aba
    $applyTweakPresetToGui = {
        param([string]$Level)
        $preset = Get-DewinTweakPreset -Level $Level

        foreach ($chkName in $allTweakChecks) {
            $tweakKey = $chkName.Substring(3)
            if ($preset.Tweaks.Contains($tweakKey) -and $gui[$chkName]) {
                $gui[$chkName].IsChecked = [bool]$preset.Tweaks[$tweakKey]
            }
        }

        $friendlyLevel = switch ($preset.Level) {
            'Light'      { 'Pouco Otimizado' }
            'Medium'     { 'Médio (Recomendado)' }
            'Aggressive' { '100% Otimizado' }
            default      { $preset.Level }
        }

        if ($gui['lblStatusTweaks']) {
            $gui['lblStatusTweaks'].Text = "Perfil '$friendlyLevel' selecionado. Clique ao lado para aplicar."
        }
    }

    $applyFeaturePresetToGui = {
        param([string]$ProfileName)
        $featPreset = Get-DewinFeaturePreset -Profile $ProfileName

        foreach ($k in $featMap.Keys) {
            if ($gui[$k]) {
                $gui[$k].IsChecked = ($featPreset.Features -contains $featMap[$k])
            }
        }

        $friendlyProfile = switch ($featPreset.Profile) {
            'General' { 'Geral (.NET apenas)' }
            'Dev'     { 'Desenvolvedor (Tudo)' }
            default   { $featPreset.Profile }
        }

        if ($gui['lblStatusFeatures']) {
            $gui['lblStatusFeatures'].Text = "Perfil '$friendlyProfile' selecionado. Clique ao lado para habilitar."
        }
    }

    # 4. Vinculação dos Botões de Níveis Rápidos (Aba 2: Otimizações)
    $gui['btnPresetTweakLight'].Add_Click({ & $applyTweakPresetToGui 'Light' })
    $gui['btnPresetTweakMedium'].Add_Click({ & $applyTweakPresetToGui 'Medium' })
    $gui['btnPresetTweakAggressive'].Add_Click({ & $applyTweakPresetToGui 'Aggressive' })

    # Botões de Seleção de Tweaks (Aba 2)
    $gui['btnSelectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
        if ($gui['lblStatusTweaks']) { $gui['lblStatusTweaks'].Text = "Todas as 29 otimizações foram marcadas." }
    })
    $gui['btnDeselectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
        if ($gui['lblStatusTweaks']) { $gui['lblStatusTweaks'].Text = "Todas as otimizações foram desmarcadas." }
    })

    # Botões de Perfis Rápidos e Seleção de Recursos (Aba 3: Extras / DISM)
    $gui['btnPresetFeatGeneral'].Add_Click({ & $applyFeaturePresetToGui 'General' })
    $gui['btnPresetFeatDev'].Add_Click({ & $applyFeaturePresetToGui 'Dev' })
    $gui['btnSelectAllFeat'].Add_Click({
        foreach ($c in $allFeatChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
        if ($gui['lblStatusFeatures']) { $gui['lblStatusFeatures'].Text = "Todos os recursos opcionais foram marcados." }
    })
    $gui['btnDeselectAllFeat'].Add_Click({
        foreach ($c in $allFeatChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
        if ($gui['lblStatusFeatures']) { $gui['lblStatusFeatures'].Text = "Todos os recursos opcionais foram desmarcados." }
    })

    # Botões de Seleção de Softwares (Aba 1: Aplicativos - 100% Manual)
    $gui['btnSelectEssentialApps'].Add_Click({
        $essentialIds = @('appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome')
        foreach ($c in $allAppChecks) {
            if ($gui[$c]) { $gui[$c].IsChecked = ($essentialIds -contains $c) }
        }
        if ($gui['lblStatusSoftwares']) { $gui['lblStatusSoftwares'].Text = "Softwares essenciais (VC++, 7-Zip, Chrome) selecionados manualmente." }
    })
    $gui['btnSelectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
        if ($gui['lblStatusSoftwares']) { $gui['lblStatusSoftwares'].Text = "Todos os programas foram marcados." }
    })
    $gui['btnDeselectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
        if ($gui['lblStatusSoftwares']) { $gui['lblStatusSoftwares'].Text = "Todos os programas foram desmarcados." }
    })

    # Botões de Utilidades de Log (Aba 4)
    $gui['btnOpenLogFolder'].Add_Click({
        $logDir = if ($global:DewinLogPath) {
            Split-Path -Path $global:DewinLogPath
        } elseif ($PSScriptRoot) {
            Join-Path $PSScriptRoot 'logs'
        } else {
            "$env:LOCALAPPDATA\dewin\logs"
        }
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Start-Process explorer.exe $logDir
    })

    $gui['btnClearLogConsole'].Add_Click({
        $gui['txtConsoleLog'].Text = "[$(Get-Date -Format 'HH:mm:ss')] Console de logs limpo."
    })

    $lastOriginTab = if ($gui['tabItemSoftwares']) { $gui['tabItemSoftwares'] } else { $null }
    if ($gui['mainTabControl']) {
        $gui['mainTabControl'].Add_SelectionChanged({
            if ($gui['mainTabControl'].SelectedItem -and $gui['tabItemLog'] -and $gui['mainTabControl'].SelectedItem -ne $gui['tabItemLog']) {
                $lastOriginTab = $gui['mainTabControl'].SelectedItem
            }
        })
    }

    if ($gui['btnBackToOptions']) {
        $gui['btnBackToOptions'].Add_Click({
            $target = if ($lastOriginTab) { $lastOriginTab } else { $gui['tabItemTweaks'] }
            if ($target -and $gui['mainTabControl']) {
                $gui['mainTabControl'].SelectedItem = $target
            }
        })
    }

    # Inicialização da interface: todas as opções iniciam desmarcadas por padrão
    foreach ($c in $allAppChecks)   { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    foreach ($c in $allFeatChecks)  { if ($gui[$c]) { $gui[$c].IsChecked = $false } }

    # 5. Executador Assíncrono com UI Responsiva (Thread-Safe e Auto-Reativação)
    $global:DewinActionButtons = @(
        'btnInstallSoftwares', 'btnApplyOptimizations', 'btnEnableFeatures',
        'btnSelectEssentialApps', 'btnSelectAllApps', 'btnDeselectAllApps',
        'btnSelectAll', 'btnDeselectAll',
        'btnPresetTweakLight', 'btnPresetTweakMedium', 'btnPresetTweakAggressive',
        'btnPresetFeatGeneral', 'btnPresetFeatDev', 'btnSelectAllFeat', 'btnDeselectAllFeat',
        'btnBackToOptions', 'btnOpenLogFolder', 'btnClearLogConsole'
    )

    $setDewinActionButtonsState = {
        param([bool]$Enabled)
        $ui = if ($global:DewinGui) { $global:DewinGui } else { $null }
        if (-not $ui) { return }

        $btns = if ($global:DewinActionButtons) { $global:DewinActionButtons } else { @() }
        foreach ($b in $btns) {
            if ($ui[$b] -and ($ui[$b] -is [System.Windows.Controls.Button])) {
                $ui[$b].IsEnabled = $Enabled
            }
        }

        if ($Enabled) {
            foreach ($k in $ui.Keys) {
                if ($ui[$k] -is [System.Windows.Controls.Button]) {
                    $ui[$k].IsEnabled = $true
                }
            }
        }
    }

    $runDewinAsync = {
        param(
            [string]$ActionTitle,
            [string]$TabKey, # 'Softwares', 'Tweaks', 'Features'
            [scriptblock]$TaskScriptBlock,
            [array]$TaskArgs,
            [scriptblock]$OnCompleted
        )

        $pbName = "pb$TabKey"
        $lblStatusName = "lblStatus$TabKey"
        $lblPercentName = "lblPercent$TabKey"

        # Inicializa o progresso na aba ativa
        if ($gui[$pbName]) { $gui[$pbName].Value = 0 }
        if ($gui[$lblPercentName]) { $gui[$lblPercentName].Text = "0%" }
        if ($gui[$lblStatusName]) { $gui[$lblStatusName].Text = "Iniciando $ActionTitle..." }

        & $setDewinActionButtonsState $false

        # Loga no console da aba de Log em segundo plano (sem forçar troca de aba)
        $gui['txtConsoleLog'].AppendText("`r`n`r`n[$(Get-Date -Format 'HH:mm:ss')] Iniciando: $ActionTitle...")

        $global:DewinSync = [hashtable]::Synchronized(@{
            Percent  = 0
            Status   = "Iniciando $ActionTitle..."
            Messages = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            IsDone   = $false
            Error    = $null
        })

        $iss = New-DewinSessionState -SyncHashtable $global:DewinSync
        $runspace = [runspacefactory]::CreateRunspace($iss)
        $runspace.Open()

        $psAsync = [powershell]::Create()
        $psAsync.Runspace = $runspace
        $psAsync.AddScript($TaskScriptBlock) | Out-Null
        foreach ($arg in $TaskArgs) {
            $psAsync.AddArgument($arg) | Out-Null
        }

        $asyncResult = $psAsync.BeginInvoke()

        $global:DewinUiTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $global:DewinUiTimer.Interval = [TimeSpan]::FromMilliseconds(100)

        # Variáveis locais capturadas pelo GetNewClosure()
        $localSetButtonState = $setDewinActionButtonsState
        $localPbName = $pbName
        $localStatusName = $lblStatusName
        $localPercentName = $lblPercentName

        $tickAction = {
            try {
                $ui = if ($global:DewinGui) { $global:DewinGui } elseif ($gui) { $gui } else { $null }
                if (-not $ui) { return }

                $s = if ($global:DewinSync) { $global:DewinSync } elseif ($sync) { $sync } else { $null }
                if (-not $s) { return }

                $pct = [int]$s.Percent
                if ($pct -lt 0) { $pct = 0 }
                if ($pct -gt 100) { $pct = 100 }

                if ($ui[$localPbName]) { $ui[$localPbName].Value = $pct }
                if ($ui[$localPercentName]) { $ui[$localPercentName].Text = "${pct}%" }
                if ($ui[$localStatusName] -and $s.Status) { $ui[$localStatusName].Text = [string]$s.Status }

                $msgList = @()
                if ($s.Messages -and $s.Messages.Count -gt 0) {
                    [System.Threading.Monitor]::Enter($s.Messages.SyncRoot)
                    try {
                        $msgList = @($s.Messages)
                        $s.Messages.Clear()
                    } finally {
                        [System.Threading.Monitor]::Exit($s.Messages.SyncRoot)
                    }
                }

                if ($msgList.Count -gt 0) {
                    $batchBuilder = [System.Text.StringBuilder]::new()
                    foreach ($m in $msgList) {
                        [void]$batchBuilder.AppendLine($m)
                    }
                    $ui['txtConsoleLog'].AppendText($batchBuilder.ToString())
                    $ui['txtConsoleLog'].ScrollToEnd()
                }

                if ($s.IsDone -or ($asyncResult -and $asyncResult.IsCompleted)) {
                    if ($global:DewinUiTimer) {
                        try { $global:DewinUiTimer.Stop() } catch {}
                    }

                    # 1. Reabilita TODOS os botões da interface IMEDIATAMENTE (primeira ação ao finalizar)
                    if ($localSetButtonState) {
                        try { & $localSetButtonState $true } catch {}
                    }
                    if ($global:DewinActionButtons) {
                        foreach ($btn in $global:DewinActionButtons) {
                            if ($ui[$btn] -and ($ui[$btn] -is [System.Windows.Controls.Button])) {
                                $ui[$btn].IsEnabled = $true
                            }
                        }
                    }
                    foreach ($k in $ui.Keys) {
                        if ($ui[$k] -is [System.Windows.Controls.Button]) {
                            $ui[$k].IsEnabled = $true
                        }
                    }

                    # 2. Restaura os títulos padrão dos botões principais
                    if ($ui['btnApplyOptimizations']) { $ui['btnApplyOptimizations'].Content = "Aplicar Otimizações Selecionadas" }
                    if ($ui['btnInstallSoftwares'])   { $ui['btnInstallSoftwares'].Content   = "Instalar Programas Selecionados" }
                    if ($ui['btnEnableFeatures'])     { $ui['btnEnableFeatures'].Content     = "Habilitar Recursos Selecionados" }

                    # 3. Restaura foco na janela do aplicativo (vital após reinício de Explorer)
                    $w = if ($global:DewinWindow) { $global:DewinWindow } elseif ($window) { $window } else { $null }
                    if ($w) {
                        try {
                            $w.Activate()
                            $w.Focus()
                        } catch {}
                    }

                    # 4. Limpeza segura de runspace
                    try { $psAsync.EndInvoke($asyncResult) | Out-Null } catch {}
                    try { $psAsync.Dispose() } catch {}
                    try { $runspace.Close() } catch {}
                    try { $runspace.Dispose() } catch {}

                    # 5. Executa callback de conclusão (ex: MessageBox de confirmação)
                    if ($OnCompleted) {
                        try { & $OnCompleted $s } catch {}
                    }

                    # 6. Garantia final: reabilita novamente após o fechamento de eventuais caixas de diálogo
                    if ($localSetButtonState) {
                        try { & $localSetButtonState $true } catch {}
                    }
                    foreach ($k in $ui.Keys) {
                        if ($ui[$k] -is [System.Windows.Controls.Button]) {
                            $ui[$k].IsEnabled = $true
                        }
                    }
                }
            } catch {}
        }.GetNewClosure()

        $global:DewinUiTimer.Add_Tick($tickAction)
        $global:DewinUiTimer.Start()
    }

    # 6. Evento de Instalação de Softwares (Aba 1: Botão Independente)
    $gui['btnInstallSoftwares'].Add_Click({
        $selectedApps = @()
        foreach ($k in $appMap.Keys) {
            if ($gui[$k] -and $gui[$k].IsChecked) { $selectedApps += $appMap[$k] }
        }

        if ($selectedApps.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                $window,
                "Nenhum programa foi selecionado.`r`nPor favor, marque ao menos um software na lista para instalar.",
                "DEWIN Booster - Selecione Softwares",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnInstallSoftwares'].Content = "Instalando programas..."

        & $runDewinAsync "Instalação de Softwares via Winget" 'Softwares' {
            param($AppsArg)
            try {
                Invoke-DewinSoftwaresOnly -Apps $AppsArg
            } catch {
                $err = $_.Exception.Message
                if ($global:sync) { $global:sync.Error = $err }
                elseif ($sync) { $sync.Error = $err }
                Write-DewinLog -Level ERROR -Message "Erro na instalacao de softwares: $err"
            } finally {
                if ($global:sync) { $global:sync.IsDone = $true }
                elseif ($sync) { $sync.IsDone = $true }
            }
        } @(,$selectedApps) {
            param($s)
            $gui['btnInstallSoftwares'].Content = "Instalar Programas Selecionados"
            if ($s.Error) {
                $gui['lblStatusSoftwares'].Text = "Falha na instalação de programas: $($s.Error)"
                $gui['lblPercentSoftwares'].Text = "Erro"
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Ocorreu um erro ao instalar os programas selecionados:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbSoftwares'].Value = 100
                $gui['lblPercentSoftwares'].Text = "100%"
                $gui['lblStatusSoftwares'].Text = "Programas instalados e atualizados com sucesso via Winget."
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Os programas selecionados foram instalados ou atualizados com sucesso via Winget.",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
        }
    })

    # 7. Evento de Aplicação de Otimizações (Aba 2: Botão Independente)
    $gui['btnApplyOptimizations'].Add_Click({
        $selectedTweaks = @{}
        foreach ($chkName in $allTweakChecks) {
            $tweakKey = $chkName.Substring(3)
            $selectedTweaks[$tweakKey] = [bool]($gui[$chkName].IsChecked)
        }
        $selectedTweaks['IsLaptop'] = [bool]$Hardware.IsLaptop

        $gui['btnApplyOptimizations'].Content = "Aplicando otimizações..."

        & $runDewinAsync "Otimizações do Sistema" 'Tweaks' {
            param($TweaksArg, $HwArg)
            try {
                Invoke-DewinTweaksOnly -Tweaks $TweaksArg -Hardware $HwArg
            } catch {
                $err = $_.Exception.Message
                if ($global:sync) { $global:sync.Error = $err }
                elseif ($sync) { $sync.Error = $err }
                Write-DewinLog -Level ERROR -Message "Erro nas otimizacoes: $err"
            } finally {
                if ($global:sync) { $global:sync.IsDone = $true }
                elseif ($sync) { $sync.IsDone = $true }
            }
        } @($selectedTweaks, $Hardware) {
            param($s)
            $gui['btnApplyOptimizations'].Content = "Aplicar Otimizações Selecionadas"
            if ($s.Error) {
                $gui['lblStatusTweaks'].Text = "Falha na aplicação de otimizações: $($s.Error)"
                $gui['lblPercentTweaks'].Text = "Erro"
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Ocorreu um erro durante as otimizações:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbTweaks'].Value = 100
                $gui['lblPercentTweaks'].Text = "100%"
                $gui['lblStatusTweaks'].Text = "Otimizações aplicadas com sucesso no sistema."
                $res = [System.Windows.MessageBox]::Show(
                    $window,
                    "Otimizações aplicadas com sucesso.`r`n`r`nRecomenda-se reiniciar o computador para que todas as alterações entrem em vigor.`r`nDeseja reiniciar agora?",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Information
                )
                if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                    Restart-Computer
                }
            }
        }
    })

    # 8. Evento de Habilitação de Recursos do Windows (Aba 3: Botão Independente)
    $gui['btnEnableFeatures'].Add_Click({
        $selectedFeats = @()
        foreach ($k in $featMap.Keys) {
            if ($gui[$k] -and $gui[$k].IsChecked) { $selectedFeats += $featMap[$k] }
        }

        if ($selectedFeats.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                $window,
                "Nenhum recurso opcional foi selecionado.`r`nPor favor, marque ao menos um recurso do Windows.",
                "DEWIN Booster - Selecione Recursos",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnEnableFeatures'].Content = "Habilitando recursos..."

        & $runDewinAsync "Recursos Opcionais do Windows (DISM)" 'Features' {
            param($FeatsArg)
            try {
                Invoke-DewinFeaturesOnly -Features $FeatsArg
            } catch {
                $err = $_.Exception.Message
                if ($global:sync) { $global:sync.Error = $err }
                elseif ($sync) { $sync.Error = $err }
                Write-DewinLog -Level ERROR -Message "Erro nos recursos DISM: $err"
            } finally {
                if ($global:sync) { $global:sync.IsDone = $true }
                elseif ($sync) { $sync.IsDone = $true }
            }
        } @(,$selectedFeats) {
            param($s)
            $gui['btnEnableFeatures'].Content = "Habilitar Recursos Selecionados"
            if ($s.Error) {
                $gui['lblStatusFeatures'].Text = "Falha na habilitação de recursos DISM: $($s.Error)"
                $gui['lblPercentFeatures'].Text = "Erro"
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Ocorreu um erro ao configurar os recursos:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbFeatures'].Value = 100
                $gui['lblPercentFeatures'].Text = "100%"
                $gui['lblStatusFeatures'].Text = "Recursos opcionais do Windows habilitados com sucesso."
                $res = [System.Windows.MessageBox]::Show(
                    $window,
                    "Recursos opcionais habilitados com sucesso via DISM.`r`n`r`nÉ necessário reiniciar o computador para finalizar a instalação dos recursos.`r`nDeseja reiniciar agora?",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Information
                )
                if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                    Restart-Computer
                }
            }
        }
    })

    # 9. Exibição da Janela Modal
    $window.ShowDialog() | Out-Null
}


# --- Interface GrÃ¡fica XAML ---
$global:DewinXaml = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(@'
PFdpbmRvdyB4bWxucz0iaHR0cDovL3NjaGVtYXMubWljcm9zb2Z0LmNvbS93aW5meC8yMDA2L3hhbWwvcHJlc2VudGF0aW9uIgogICAgICAgIHhtbG5zOng9Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vd2luZngvMjAwNi94YW1sIgogICAgICAgIFRpdGxlPSJERVdJTiBCb29zdGVyIC0gT3RpbWl6YWRvciBlIEdlcmVuY2lhZG9yIGRvIFdpbmRvd3MiCiAgICAgICAgSGVpZ2h0PSI4MDAiIFdpZHRoPSIxMTAwIiBNaW5IZWlnaHQ9IjcwMCIgTWluV2lkdGg9Ijk4MCIKICAgICAgICBXaW5kb3dTdGFydHVwTG9jYXRpb249IkNlbnRlclNjcmVlbiIKICAgICAgICBCYWNrZ3JvdW5kPSIjMEYxMTFBIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IgogICAgICAgIEZvbnRGYW1pbHk9IlNlZ29lIFVJLCBTZWdvZSBVSSBWYXJpYWJsZSwgQXJpYWwiPgoKICAgIDxXaW5kb3cuUmVzb3VyY2VzPgogICAgICAgIDwhLS0gUGFsZXRhIGRlIENvcmVzIE1vZGVybmEgKERFV0lOIERhcmsgVGhlbWUpIC0tPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJnRGFyayIgQ29sb3I9IiMwRjExMUEiIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQmdDYXJkIiBDb2xvcj0iIzFBMUIyNiIgLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJCZ0NhcmRBbHQiIENvbG9yPSIjMjQyODNCIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJvcmRlckNhcmQiIENvbG9yPSIjMkYzNTRGIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlByaW1hcnlDeWFuIiBDb2xvcj0iIzdEQ0ZGRiIgLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJQcmltYXJ5Qmx1ZSIgQ29sb3I9IiM3QUEyRjciIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQWNjZW50R3JlZW4iIENvbG9yPSIjOUVDRTZBIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkFjY2VudFllbGxvdyIgQ29sb3I9IiNFMEFGNjgiIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iVGV4dFByaW1hcnkiIENvbG9yPSIjQzhEM0Y1IiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlRleHRNdXRlZCIgQ29sb3I9IiM3OTgyQTkiIC8+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBDaGVja0JveGVzIE1vZGVybm9zIC0tPgogICAgICAgIDxTdHlsZSBUYXJnZXRUeXBlPSJDaGVja0JveCI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvcmVncm91bmQiIFZhbHVlPSIjQzhEM0Y1IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250U2l6ZSIgVmFsdWU9IjEzIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJNYXJnaW4iIFZhbHVlPSIwLDUsMCw1IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJDdXJzb3IiIFZhbHVlPSJIYW5kIiAvPgogICAgICAgIDwvU3R5bGU+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBCb3RvZXMgU2VjdW5kYXJpb3MgLS0+CiAgICAgICAgPFN0eWxlIHg6S2V5PSJTZWNvbmRhcnlCdXR0b24iIFRhcmdldFR5cGU9IkJ1dHRvbiI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJhY2tncm91bmQiIFZhbHVlPSIjMjQyODNCIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb3JlZ3JvdW5kIiBWYWx1ZT0iI0M4RDNGNSIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyQnJ1c2giIFZhbHVlPSIjNDE0ODY4IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCb3JkZXJUaGlja25lc3MiIFZhbHVlPSIxIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJQYWRkaW5nIiBWYWx1ZT0iMTIsNiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ3Vyc29yIiBWYWx1ZT0iSGFuZCIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9udFdlaWdodCIgVmFsdWU9IlNlbWlCb2xkIiAvPgogICAgICAgIDwvU3R5bGU+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBDYXJkcyBkZSBQZXJmaWwgZSBBZ3J1cGFtZW50b3MgLS0+CiAgICAgICAgPFN0eWxlIHg6S2V5PSJQcm9maWxlQ2FyZCIgVGFyZ2V0VHlwZT0iQm9yZGVyIj4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQmFja2dyb3VuZCIgVmFsdWU9IiMxQTFCMjYiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlckJydXNoIiBWYWx1ZT0iIzJGMzU0RiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyVGhpY2tuZXNzIiBWYWx1ZT0iMSIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iMTAiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlBhZGRpbmciIFZhbHVlPSIxNiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iTWFyZ2luIiBWYWx1ZT0iNiIgLz4KICAgICAgICA8L1N0eWxlPgoKICAgICAgICA8IS0tIEVzdGlsbyBNb2Rlcm5vIGRhIEJhcnJhIGRlIFByb2dyZXNzbyAtLT4KICAgICAgICA8U3R5bGUgVGFyZ2V0VHlwZT0iUHJvZ3Jlc3NCYXIiPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCYWNrZ3JvdW5kIiBWYWx1ZT0iIzI0MjgzQiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgVmFsdWU9IiM3RENGRkYiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlclRoaWNrbmVzcyIgVmFsdWU9IjAiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlRlbXBsYXRlIj4KICAgICAgICAgICAgICAgIDxTZXR0ZXIuVmFsdWU+CiAgICAgICAgICAgICAgICAgICAgPENvbnRyb2xUZW1wbGF0ZSBUYXJnZXRUeXBlPSJQcm9ncmVzc0JhciI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0ie1RlbXBsYXRlQmluZGluZyBCYWNrZ3JvdW5kfSIgQ29ybmVyUmFkaXVzPSI1IiBDbGlwVG9Cb3VuZHM9IlRydWUiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQgTmFtZT0iUEFSVF9UcmFjayI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBOYW1lPSJQQVJUX0luZGljYXRvciIgQmFja2dyb3VuZD0ie1RlbXBsYXRlQmluZGluZyBGb3JlZ3JvdW5kfSIgSG9yaXpvbnRhbEFsaWdubWVudD0iTGVmdCIgQ29ybmVyUmFkaXVzPSI1IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICA8L0NvbnRyb2xUZW1wbGF0ZT4KICAgICAgICAgICAgICAgIDwvU2V0dGVyLlZhbHVlPgogICAgICAgICAgICA8L1NldHRlcj4KICAgICAgICA8L1N0eWxlPgogICAgPC9XaW5kb3cuUmVzb3VyY2VzPgoKICAgIDxHcmlkIE1hcmdpbj0iMTYiPgogICAgICAgIDxHcmlkLlJvd0RlZmluaXRpb25zPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iIC8+IDwhLS0gQ2FiZWNhbGhvIGUgQmFubmVyIGRlIEhhcmR3YXJlIC0tPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IioiIC8+ICAgIDwhLS0gQXJlYSBQcmluY2lwYWwgY29tIEFiYXMgLS0+CiAgICAgICAgPC9HcmlkLlJvd0RlZmluaXRpb25zPgoKICAgICAgICA8IS0tIDEuIENBQkVDQUxITyAmIEJBTk5FUiBERSBIQVJEV0FSRSAtLT4KICAgICAgICA8Qm9yZGVyIEdyaWQuUm93PSIwIiBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjEwIiBQYWRkaW5nPSIxNiIgTWFyZ2luPSIwLDAsMCwxMiI+CiAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CgogICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjAiPgogICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIE9yaWVudGF0aW9uPSJIb3Jpem9udGFsIj4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJERVdJTiBCT09TVEVSIiBGb250U2l6ZT0iMjAiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3RENGRkYiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzI0MjgzQiIgQ29ybmVyUmFkaXVzPSI1IiBQYWRkaW5nPSI2LDIiIE1hcmdpbj0iMTAsMCwwLDAiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJOYXRpdm8gZSBkZSBDw7NkaWdvIEFiZXJ0byIgRm9udFNpemU9IjExIiBGb3JlZ3JvdW5kPSIjOUVDRTZBIiBGb250V2VpZ2h0PSJTZW1pQm9sZCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0idHh0SGFyZHdhcmVCYW5uZXIiIFRleHQ9IkRldGVjdGFuZG8gY29tcG9uZW50ZXMgZGUgaGFyZHdhcmUuLi4iIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgTWFyZ2luPSIwLDUsMCwwIiAvPgogICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgoKICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIxIiBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciI+CiAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMjQyODNCIiBCb3JkZXJCcnVzaD0iIzQxNDg2OCIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjEwLDYiIE1hcmdpbj0iNCwwIj4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBOYW1lPSJ0eHREZXZpY2VUeXBlIiBUZXh0PSJEZXRlY3RhbmRvLi4uIiBGb250U2l6ZT0iMTIiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3QUEyRjciIC8+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgPCEtLSAyLiBBQkFTIFBSSU5DSVBBSVMgLS0+CiAgICAgICAgPFRhYkNvbnRyb2wgTmFtZT0ibWFpblRhYkNvbnRyb2wiIEdyaWQuUm93PSIxIiBCYWNrZ3JvdW5kPSIjMTMxNDFGIiBCb3JkZXJCcnVzaD0iIzJGMzU0RiI+CiAgICAgICAgICAgIAogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8IS0tIEFCQSAxOiBQUk9HUkFNQVMgJiBBUExJQ0FUSVZPUyAoVEVMQSBJTklDSUFMKSAgICAgICAgICAgIC0tPgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8VGFiSXRlbSBOYW1lPSJ0YWJJdGVtU29mdHdhcmVzIiBIZWFkZXI9IiBQcm9ncmFtYXMgZSBBcGxpY2F0aXZvcyAiPgogICAgICAgICAgICAgICAgPFNjcm9sbFZpZXdlciBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIE1hcmdpbj0iMTAiPgogICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhYmVjYWxobyBlIEFjb2VzIFJhcGlkYXMgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCIgTWFyZ2luPSI2LDAsNiwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iSW5zdGFsYcOnw6NvIGUgQXR1YWxpemHDp8OjbyBkZSBTb2Z0d2FyZXMgdmlhIFdpbmdldCIgRm9udFNpemU9IjE2IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0RDRkZGIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlNlbGVjaW9uZSBvcyBwcm9ncmFtYXMgcXVlIGRlc2VqYSBpbnN0YWxhciBzaWxlbmNpb3NhbWVudGUgbm8gY29tcHV0YWRvcjoiIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgTWFyZ2luPSIwLDMsMCwwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjEiIE9yaWVudGF0aW9uPSJIb3Jpem9udGFsIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5TZWxlY3RFc3NlbnRpYWxBcHBzIiBDb250ZW50PSJFc3NlbmNpYWlzIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iMCwwLDYsMCIgVG9vbFRpcD0iU2VsZWNpb25hIFZpc3VhbCBDKyssIDctWmlwIGUgR29vZ2xlIENocm9tZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5TZWxlY3RBbGxBcHBzIiBDb250ZW50PSJNYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSIwLDAsNiwwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkRlc2VsZWN0QWxsQXBwcyIgQ29udGVudD0iRGVzbWFyY2FyIFRvZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2F0YWxvZ28gZGUgU29mdHdhcmVzIGVtIEdyaWQgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDb2x1bmEgMTogUnVudGltZXMgZSBOYXZlZ2Fkb3JlcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlJ1bnRpbWVzIGUgVXRpbGl0w6FyaW9zIEVzc2VuY2lhaXMiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcFZjUmVkaXN0NjQiIENvbnRlbnQ9IlZpc3VhbCBDKysgMjAxNS0yMDIyICh4NjQpIC0gUHLDqS1yZXF1aXNpdG8gcGFyYSBqb2dvcyBlIHByb2dyYW1hcyIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBWY1JlZGlzdDg2IiBDb250ZW50PSJWaXN1YWwgQysrIDIwMTUtMjAyMiAoeDg2KSAtIENvbXBhdGliaWxpZGFkZSBkZSBhcGxpY2F0aXZvcyAzMi1iaXQiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iYXBwN3ppcCIgQ29udGVudD0iNy1aaXAgLSBDb21wYWN0YWRvciBlIGRlc2NvbXBhY3RhZG9yIGRlIGFsdGEgcGVyZm9ybWFuY2UiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJOYXZlZ2Fkb3JlcyBXZWIiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcENocm9tZSIgQ29udGVudD0iR29vZ2xlIENocm9tZSAtIE5hdmVnYWRvciB3ZWIgbW9kZXJubyBlIHNlZ3VybyIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDI6IERlc2Vudm9sdmltZW50byBlIE11bHRpbWlkaWEvSm9nb3MgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJGZXJyYW1lbnRhcyBkZSBEZXNlbnZvbHZpbWVudG8iIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0JCOUFGNyIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcFZzQ29kZSIgQ29udGVudD0iVmlzdWFsIFN0dWRpbyBDb2RlIC0gRWRpdG9yIGRlIGPDs2RpZ28gZGEgTWljcm9zb2Z0IiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcEdpdCIgQ29udGVudD0iR2l0IGZvciBXaW5kb3dzIC0gU2lzdGVtYSBkaXN0cmlidcOtZG8gZGUgY29udHJvbGUgZGUgdmVyc8OjbyIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkNvbXVuaWNhw6fDo28sIE3DrWRpYSBlIEpvZ29zIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNFMEFGNjgiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBEaXNjb3JkIiBDb250ZW50PSJEaXNjb3JkIC0gQ29tdW5pY2HDp8OjbyBwb3Igdm96LCB2w61kZW8gZSB0ZXh0byIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBTdGVhbSIgQ29udGVudD0iU3RlYW0gLSBQbGF0YWZvcm1hIGRlIGpvZ29zIGUgY29tdW5pZGFkZSBkaWdpdGFsIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcFZsYyIgQ29udGVudD0iVkxDIE1lZGlhIFBsYXllciAtIFJlcHJvZHV0b3IgZGUgw6F1ZGlvIGUgdsOtZGVvIHVuaXZlcnNhbCIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBTcG90aWZ5IiBDb250ZW50PSJTcG90aWZ5IC0gU3RyZWFtaW5nIGRlIG3DunNpY2EgZSBwb2RjYXN0cyIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgSW5kZXBlbmRlbnRlIGRlIEFjYW8gZSBQcm9ncmVzc28gZGUgU29mdHdhcmVzIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMxQTFCMjYiIEJvcmRlckJydXNoPSIjMkYzNTRGIiBCb3JkZXJUaGlja25lc3M9IjEiIENvcm5lclJhZGl1cz0iMTAiIFBhZGRpbmc9IjE2LDEyIiBNYXJnaW49IjYsMTIsNiw2Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLlJvd0RlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuUm93RGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gTGluaGEgMTogU3RhdHVzIGRhIGluc3RhbGFjYW8gKyBQb3JjZW50YWdlbSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIE5hbWU9ImxibFN0YXR1c1NvZnR3YXJlcyIgR3JpZC5Sb3c9IjAiIEdyaWQuQ29sdW1uPSIwIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVGV4dD0iQSBpbnN0YWxhw6fDo28gw6kgcmVhbGl6YWRhIGVtIHNlZ3VuZG8gcGxhbm8gdmlhIFdpbmdldCBvZmljaWFsLiIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgTWFyZ2luPSIwLDAsMCw4IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVGV4dFRyaW1taW5nPSJDaGFyYWN0ZXJFbGxpcHNpcyIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBOYW1lPSJsYmxQZXJjZW50U29mdHdhcmVzIiBHcmlkLlJvdz0iMCIgR3JpZC5Db2x1bW49IjEiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUZXh0PSIwJSIgRm9udFNpemU9IjEyIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjMzhCREY4IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgSG9yaXpvbnRhbEFsaWdubWVudD0iUmlnaHQiIE1hcmdpbj0iMCwwLDAsOCIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBMaW5oYSAyOiBCYXJyYSBkZSBQcm9ncmVzc28gKyBCb3RhbyBkZSBBY2FvIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxQcm9ncmVzc0JhciBOYW1lPSJwYlNvZnR3YXJlcyIgR3JpZC5Sb3c9IjEiIEdyaWQuQ29sdW1uPSIwIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBIZWlnaHQ9IjEwIiBNaW5pbXVtPSIwIiBNYXhpbXVtPSIxMDAiIFZhbHVlPSIwIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCYWNrZ3JvdW5kPSIjMTMxNDFGIiBGb3JlZ3JvdW5kPSIjMzhCREY4IiBCb3JkZXJUaGlja25lc3M9IjAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIE1hcmdpbj0iMCwwLDE2LDAiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuSW5zdGFsbFNvZnR3YXJlcyIgR3JpZC5Sb3c9IjEiIEdyaWQuQ29sdW1uPSIxIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQ29udGVudD0iSW5zdGFsYXIgUHJvZ3JhbWFzIFNlbGVjaW9uYWRvcyIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiMyNTYzRUIiIEJvcmRlckJydXNoPSIjMzhCREY4IiBGb3JlZ3JvdW5kPSJXaGl0ZSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRXZWlnaHQ9IkJvbGQiIEZvbnRTaXplPSIxMyIgUGFkZGluZz0iMjAsMTAiIEN1cnNvcj0iSGFuZCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24uUmVzb3VyY2VzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0eWxlIFRhcmdldFR5cGU9IkJvcmRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3R5bGU+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgPC9TY3JvbGxWaWV3ZXI+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDwhLS0gQUJBIDI6IE9USU1JWkFDT0VTIERPIFNJU1RFTUEgRSBQRVJGSVMgICAgICAgICAgICAgICAgICAgLS0+CiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDxUYWJJdGVtIE5hbWU9InRhYkl0ZW1Ud2Vha3MiIEhlYWRlcj0iIE90aW1pemHDp8O1ZXMgZG8gU2lzdGVtYSAiPgogICAgICAgICAgICAgICAgPFNjcm9sbFZpZXdlciBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIE1hcmdpbj0iMTAiPgogICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIE5vdGlmaWNhY2FvIGRlIFJlY29tZW5kYWNhbyBkZSBIYXJkd2FyZSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUMyNzM4IiBCb3JkZXJCcnVzaD0iIzI1NjNFQiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjEyIiBNYXJnaW49IjYsMCw2LDEwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0idHh0UmVjb21tZW5kYXRpb24iIFRleHQ9IkNhbGN1bGFuZG8gbWVsaG9yIHBlcmZpbCBwYXJhIHN1YSBtw6FxdWluYS4uLiIgRm9udFNpemU9IjEzIiBGb3JlZ3JvdW5kPSIjOTNDNUZEIiBUZXh0V3JhcHBpbmc9IldyYXAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBTZcOnw6NvIGRvcyAzIE7DrXZlaXMgUsOhcGlkb3MgZGUgT3RpbWl6YcOnw6NvIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9Ik7DrXZlaXMgUsOhcGlkb3MgZGUgT3RpbWl6YcOnw6NvOiIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJTZW1pQm9sZCIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSI4LDQsOCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8VW5pZm9ybUdyaWQgQ29sdW1ucz0iMyIgTWFyZ2luPSIwLDAsMCwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgUG91Y28gT3RpbWl6YWRvIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUG91Y28gT3RpbWl6YWRvIiBGb250U2l6ZT0iMTUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiMzOEJERjgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iT3RpbWl6YcOnw7VlcyBlc3NlbmNpYWlzIGUgc2VndXJhcywgbWFudGVuZG8gYSBleHBlcmnDqm5jaWEgY2zDoXNzaWNhIGRvIFdpbmRvd3MgMTEgaW50YWN0YS4iIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgTWFyZ2luPSIwLDMsMCw2IiBUZXh0V3JhcHBpbmc9IldyYXAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0i4oCiIExpbXBlemEgZGUgYXJxdWl2b3MgdGVtcG9yw6FyaW9zIGUgU1NEJiN4MGE74oCiIERlc2F0aXZhw6fDo28gZGUgdGVsZW1ldHJpYSBiw6FzaWNhIGUgQmluZyYjeDBhO+KAoiBNZW51cyByw6FwaWRvcyBlIHN1cG9ydGUgYSBjYW1pbmhvcyBsb25nb3MiIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSIwLDIsMCwxMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5QcmVzZXRUd2Vha0xpZ2h0IiBDb250ZW50PSJTZWxlY2lvbmFyIFBvdWNvIE90aW1pemFkbyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBCYWNrZ3JvdW5kPSIjMDI4NEM3IiBCb3JkZXJCcnVzaD0iIzM4QkRGOCIgRm9yZWdyb3VuZD0iV2hpdGUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIE3DqWRpbyAoUmVjb21lbmRhZG8pIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iTcOpZGlvIChSZWNvbWVuZGFkbykiIEZvbnRTaXplPSIxNSIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzRBREU4MCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJFcXVpbMOtYnJpbyBpZGVhbCBlbnRyZSBkZXNlbXBlbmhvLCBwcml2YWNpZGFkZSwgcmVtb8Onw6NvIGRlIGJsb2F0IGUgZmx1aWRleiBkbyBzaXN0ZW1hLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBNYXJnaW49IjAsMywwLDYiIFRleHRXcmFwcGluZz0iV3JhcCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSLigKIgUmVtb8Onw6NvIGRlIDI4IGJsb2F0d2FyZXMgZSB0ZWxlbWV0cmlhJiN4MGE74oCiIEJhaXhhIGxhdMOqbmNpYSBkZSByZWRlIGUgc2VtIEdhbWVEVlImI3gwYTvigKIgTWVudSBjbMOhc3NpY28gZSBoaWJlcm5hw6fDo28gaW50ZWxpZ2VudGUiIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSIwLDIsMCwxMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5QcmVzZXRUd2Vha01lZGl1bSIgQ29udGVudD0iU2VsZWNpb25hciBNw6lkaW8gKFJlY29tZW5kYWRvKSIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBCYWNrZ3JvdW5kPSIjMTZBMzRBIiBCb3JkZXJCcnVzaD0iIzIyQzU1RSIgRm9yZWdyb3VuZD0iV2hpdGUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIDEwMCUgT3RpbWl6YWRvIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iMTAwJSBPdGltaXphZG8iIEZvbnRTaXplPSIxNSIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0JCOUFGNyIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJNw6F4aW1vIGRlc2VtcGVuaG8gYWJzb2x1dG8gcGFyYSBqb2dhZG9yZXMsIGNyaWFkb3JlcyBlIGRlc2Vudm9sdmVkb3JlcyBleGlnZW50ZXMuIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsNiIgVGV4dFdyYXBwaW5nPSJXcmFwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IuKAoiBUb2RhcyBhcyAyOCBvdGltaXphw6fDtWVzIGF0aXZhZGFzJiN4MGE74oCiIENhbGlicmHDp8OjbyBkZSBHUFUsIENQVSBlIG1lbcOzcmlhJiN4MGE74oCiIFJlbMOzZ2lvIFVUQyBlIGluaWNpYWxpemHDp8OjbyBsaW1wYSIgRm9udFNpemU9IjExIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IiBNYXJnaW49IjAsMiwwLDEwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0blByZXNldFR3ZWFrQWdncmVzc2l2ZSIgQ29udGVudD0iU2VsZWNpb25hciAxMDAlIE90aW1pemFkbyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBCYWNrZ3JvdW5kPSIjN0MzQUVEIiBCb3JkZXJCcnVzaD0iIzhCNUNGNiIgRm9yZWdyb3VuZD0iV2hpdGUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvVW5pZm9ybUdyaWQ+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIEJhcnJhIGRlIEZlcnJhbWVudGFzIGRlIFNlbGVjYW8gZG9zIFR3ZWFrcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjEyIiBNYXJnaW49IjYsMCw2LDEwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlNlbGXDp8OjbyBQZXJzb25hbGl6YWRhIGRlIE90aW1pemHDp8O1ZXM6IiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNDOEQzRjUiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIxIiBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuU2VsZWN0QWxsIiBDb250ZW50PSJNYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSIwLDAsNiwwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkRlc2VsZWN0QWxsIiBDb250ZW50PSJEZXNtYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBHcmlkIGRlIFR3ZWFrcyBwb3IgQ2F0ZWdvcmlhIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDE6IEludGVyZmFjZSBlIERlc2VtcGVuaG8gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIEludGVyZmFjZSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkludGVyZmFjZSBlIEJhcnJhIGRlIFRhcmVmYXMiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0hpZGVTZWFyY2giIENvbnRlbnQ9Ik9jdWx0YXIgY2FpeGEgZGUgcGVzcXVpc2EgbmEgYmFycmEgZGUgdGFyZWZhcyIgSXNDaGVja2VkPSJGYWxzZSIgVG9vbFRpcD0iT2N1bHRhIGEgYmFycmEgZGUgcGVzcXVpc2EgZSBkZXNhdGl2YSBkZXN0YXF1ZXMgZG8gQmluZywgYnVzY2EgcmVtb3RhIG5hIG51dmVtIGUgcmFzdHJlYW1lbnRvIGRlIGxvY2FsaXphw6fDo28uIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0hpZGVUYXNrVmlldyIgQ29udGVudD0iT2N1bHRhciBib3TDo28gZGUgVmlzw6NvIGRlIFRhcmVmYXMgKFRhc2sgVmlldykiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9Ik9jdWx0YSBvIMOtY29uZSBkYSBiYXJyYTsgbyBhdGFsaG8gV2luK1RhYiBwZXJtYW5lY2UgdG90YWxtZW50ZSBmdW5jaW9uYWwuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0NlbnRlclRhc2tiYXIiIENvbnRlbnQ9IkFsaW5oYW1lbnRvIGNlbnRyYWxpemFkbyBkYSBiYXJyYSBkZSB0YXJlZmFzIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJNYW50w6ltIGEgYmFycmEgZGUgdGFyZWZhcyBjZW50cmFsaXphZGEgbm8gcGFkcsOjbyBtb2Rlcm5vIGRvIFdpbmRvd3MgMTEuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa1Rhc2tiYXJFbmRUYXNrIiBDb250ZW50PSJBdGl2YXIgb3DDp8OjbyAnRmluYWxpemFyIFRhcmVmYScgbm8gYm90w6NvIGRpcmVpdG8iIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IlBlcm1pdGUgZW5jZXJyYXIgcHJvY2Vzc29zIG7Do28gcmVzcG9uc2l2b3MgZGlyZXRhbWVudGUgcGVsbyBib3TDo28gZGlyZWl0byBuYSBiYXJyYSBkZSB0YXJlZmFzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtDbGFzc2ljQ29udGV4dE1lbnUiIENvbnRlbnQ9Ik1lbnUgZGUgY29udGV4dG8gY2zDoXNzaWNvIChlc3RpbG8gV2luZG93cyAxMCkiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkV4aWJlIHRvZGFzIGFzIG9ww6fDtWVzIGRvIG1lbnUgZGUgY29udGV4dG8gZGlyZXRhbWVudGUsIHNlbSBzdWJtZW51cyBhZGljaW9uYWlzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtMYXVuY2hUb1RoaXNQQyIgQ29udGVudD0iQWJyaXIgRXhwbG9yYWRvciBkZSBBcnF1aXZvcyBlbSAnRXN0ZSBDb21wdXRhZG9yJyIgSXNDaGVja2VkPSJGYWxzZSIgVG9vbFRpcD0iQ29uZmlndXJhIG8gRXhwbG9yYWRvciBkZSBBcnF1aXZvcyBwYXJhIGluaWNpYXIgbmFzIHVuaWRhZGVzIGRlIGRpc2NvLCByZW1vdmVuZG8gcMOhZ2luYXMgbGVudGFzIGRlIEluw61jaW8gZSBHYWxlcmlhLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtTaG93RXh0ZW5zaW9uc0FuZEhpZGRlbiIgQ29udGVudD0iRXhpYmlyIGV4dGVuc8O1ZXMgZSBhcnF1aXZvcyBvY3VsdG9zIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJGYWNpbGl0YSBhIHZpc3VhbGl6YcOnw6NvIGRlIGV4dGVuc8O1ZXMgZGUgYXJxdWl2b3MgKC5iYXQsIC5wczEsIC5qc29uKSBlIHBhc3RhcyBkZSBjb25maWd1cmHDp8Ojby4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrQWx3YXlzU2hvd1Njcm9sbGJhcnMiIENvbnRlbnQ9Ik1hbnRlciBiYXJyYXMgZGUgcm9sYWdlbSBzZW1wcmUgdmlzw612ZWlzIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJFdml0YSBxdWUgYXMgYmFycmFzIGRlIHJvbGFnZW0gc2VqYW0gb2N1bHRhZGFzIGF1dG9tYXRpY2FtZW50ZSBwZWxhIGludGVyZmFjZS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIERlc2VtcGVuaG8gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJEZXNlbXBlbmhvLCBMYXTDqm5jaWEgZSBBcm1hemVuYW1lbnRvIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM5RUNFNkEiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtPcHRpbWl6ZU5ldHdvcmtMYXRlbmN5IiBDb250ZW50PSJPdGltaXphciBsYXTDqm5jaWEgZGUgcmVkZSAoTmV0d29ya1Rocm90dGxpbmcpIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJEZXNhdGl2YSBhIGxpbWl0YcOnw6NvIGRlIHJlZGUgZG8gV2luZG93cyBwYXJhIG1lbm9yIGxhdMOqbmNpYSBlbSBjb25leMO1ZXMgZSBqb2dvcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZUdhbWVEVlIiIENvbnRlbnQ9IkRlc2F0aXZhciBHYW1lRFZSIGUgY2FwdHVyYSBlbSBzZWd1bmRvIHBsYW5vIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJFbGltaW5hIHNvYnJlY2FyZ2EgZGUgcHJvY2Vzc2Fkb3IgZSBwbGFjYSBkZSB2w61kZW8gZ2VyYWRhIHBvciBncmF2YcOnw7VlcyBhdXRvbcOhdGljYXMgZGUgdGVsYS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrTGluZWFyTW91c2UiIENvbnRlbnQ9IlJlc3Bvc3RhIGxpbmVhciBkbyBwb250ZWlybyBkbyBtb3VzZSAoUHJlY2lzw6NvIDE6MSkiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkRlc2F0aXZhIGEgYWNlbGVyYcOnw6NvIGFydGlmaWNpYWwgZG8gcG9udGVpcm8gcGFyYSBjb25zaXN0w6puY2lhIGRlIG1vdmltZW50by4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZVN0aWNreUtleXMiIENvbnRlbnQ9IkRlc2F0aXZhciBhdGFsaG8gZGUgVGVjbGFzIGRlIEFkZXLDqm5jaWEiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkltcGVkZSBhIGV4aWJpw6fDo28gZG8gZGnDoWxvZ28gZGUgY29uZmlybWHDp8OjbyBhbyBwcmVzc2lvbmFyIGEgdGVjbGEgU2hpZnQgY29uc2VjdXRpdmFtZW50ZS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrSW5zdGFudE1lbnVEZWxheSIgQ29udGVudD0iUmVtb3ZlciBhdHJhc28gbmEgYWJlcnR1cmEgZGUgbWVudXMgKDAgbXMpIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJSZWR1eiBvIHRlbXBvIGRlIGVzcGVyYSBuYSBhYmVydHVyYSBkZSBzdWJtZW51cyBzdXNwZW5zb3MgcGFyYSByZXNwb3N0YSBpbWVkaWF0YS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrT3B0aW1pemVTc2RBY2Nlc3MiIENvbnRlbnQ9Ik90aW1pemFyIGdyYXZhw6fDtWVzIGVtIFNTRCAoRGlzYWJsZUxhc3RBY2Nlc3MpIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJEZXNhdGl2YSBhIGdyYXZhw6fDo28gY29udMOtbnVhIGRlIGRhdGEgZGUgw7psdGltbyBhY2Vzc28sIHJlZHV6aW5kbyBlc2NyaXRhcyBlIHByZXNlcnZhbmRvIG8gU1NELiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtDbGVhblRlbXBGaWxlcyIgQ29udGVudD0iTGltcGFyIGFycXVpdm9zIHRlbXBvcsOhcmlvcyBkbyBzaXN0ZW1hIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJFc3ZhemlhIGNhY2hlcyBlIGFycXVpdm9zIHRlbXBvcsOhcmlvcyBuw6NvIHV0aWxpemFkb3MgcGVsbyBzaXN0ZW1hIG9wZXJhY2lvbmFsLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDI6IFByaXZhY2lkYWRlLCBEZWJsb2F0IGUgU2lzdGVtYSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIxIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgUHJpdmFjaWRhZGUgJiBEZWJsb2F0IC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUHJpdmFjaWRhZGUsIFRlbGVtZXRyaWEgZSBBcGxpY2F0aXZvcyBQYWRyw6NvIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNCQjlBRjciIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlVGVsZW1ldHJ5IiBDb250ZW50PSJEZXNhdGl2YXIgdGVsZW1ldHJpYSBlIHNlcnZpw6dvcyBkZSBkaWFnbsOzc3RpY28iIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkRlc2F0aXZhIERpYWdUcmFjaywgdGVsZW1ldHJpYSBkZSBhcHBzLCBjb2xldG9yIGRlIGludmVudMOhcmlvLCByZWxhdMOzcmlvcyBXRVIgZGUgdHJhdmFtZW50b3MgZSBwcm9wYWdhbmRhcy9kaWNhcyBkZSBudXZlbSBubyBJbmljaWFyLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlQ2VpcFRhc2tzIiBDb250ZW50PSJEZXNhdGl2YXIgdGFyZWZhcyBhZ2VuZGFkYXMgZGUgZGlhZ27Ds3N0aWNvIChDRUlQKSIgSXNDaGVja2VkPSJGYWxzZSIgVG9vbFRpcD0iRGVzYXRpdmEgcm90aW5hcyBhZ2VuZGFkYXMgZGUgdGVsZW1ldHJpYSBleGVjdXRhZGFzIGR1cmFudGUgcGVyw61vZG9zIGRlIG9jaW9zaWRhZGUuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVDb3BpbG90UmVjYWxsIiBDb250ZW50PSJEZXNhdGl2YXIgV2luZG93cyBDb3BpbG90IGUgcmVjdXJzb3MgZGUgSUEgUmVjYWxsIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJEZXNhdGl2YSBvIGFzc2lzdGVudGUgQ29waWxvdCwgQ29ydGFuYSBlIHJvdGluYXMgZGUgYW7DoWxpc2UgY29udMOtbnVhIGRlIHRlbGEgZW0gc2VndW5kbyBwbGFuby4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZUJpbmdTZWFyY2giIENvbnRlbnQ9IkRlc2F0aXZhciByZXN1bHRhZG9zIGRvIEJpbmcgbm8gbWVudSBJbmljaWFyIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJNYW50w6ltIGEgYnVzY2EgZG8gbWVudSBJbmljaWFyIGVzdHJpdGFtZW50ZSBsb2NhbCBwYXJhIHJlc3Bvc3RhcyBpbWVkaWF0YXMuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0RlYmxvYXRFZGdlIiBDb250ZW50PSJPdGltaXphciB0ZWxlbWV0cmlhIGRvIE1pY3Jvc29mdCBFZGdlIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJEZXNhdGl2YSBtw6l0cmljYXMgZGUgbmF2ZWdhw6fDo28sIGFzc2lzdGVudGVzIGRlIGNvbXByYSwgcGVyc2lzdMOqbmNpYSBkZSBwcm9jZXNzb3MgYW8gZmVjaGFyIGUgcHLDqS1jYXJyZWdhbWVudG8uIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa1JlbW92ZVV3cEJsb2F0IiBDb250ZW50PSJSZW1vdmVyIGFwbGljYXRpdm9zIHByw6ktaW5zdGFsYWRvcyBkZXNuZWNlc3PDoXJpb3MiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IlJlbW92ZSBwYWNvdGVzIHByb21vY2lvbmFpcyBwcsOpLWluc3RhbGFkb3MgZGUgZW50cmV0ZW5pbWVudG8gZSByZWRlcyBzb2NpYWlzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgU2lzdGVtYSAmIEVuZXJnaWEgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJTaXN0ZW1hLCBHcsOhZmljb3MgZSBHZXJlbmNpYW1lbnRvIGRlIEVuZXJnaWEiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0UwQUY2OCIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0NhbGlicmF0ZUdwdSIgQ29udGVudD0iQ2FsaWJyYXIgdG9sZXLDom5jaWEgZGUgZHJpdmVyIGdyw6FmaWNvIChUZHJEZWxheSBlIEhBR1MpIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJBdW1lbnRhIGEgdG9sZXLDom5jaWEgcGFyYSByZWN1cGVyYcOnw6NvIGRvIGRyaXZlciBncsOhZmljbyBlIGF0aXZhIG8gYWdlbmRhbWVudG8gZGUgR1BVIHBvciBoYXJkd2FyZS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrU21hcnRIaWJlcm5hdGlvbiIgQ29udGVudD0iR2VyZW5jaWFtZW50byBpbnRlbGlnZW50ZSBkZSBoaWJlcm5hw6fDo28iIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkRlc2F0aXZhIGhpYmVybmHDp8OjbyBlbSBkZXNrdG9wIChyZWN1cGVyYSBlc3Bhw6dvIFNTRCkgb3UgYXRpdmEgaGliZXJuYcOnw6NvIGNvbXBhY3RhIGUgc3VzcGVuZGUgaW5kZXhhw6fDo28gbmEgYmF0ZXJpYSBlbSBub3RlYm9va3MuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVSZXNlcnZlZFN0b3JhZ2UiIENvbnRlbnQ9IkRlc2F0aXZhciBBcm1hemVuYW1lbnRvIFJlc2VydmFkbyBkbyBXaW5kb3dzIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJMaWJlcmEgYXByb3hpbWFkYW1lbnRlIDcgR0IgZGUgZXNwYcOnbyBlbSBkaXNjbyBhbnRlcmlvcm1lbnRlIHJldGlkb3MgcGVsbyBzaXN0ZW1hIG9wZXJhY2lvbmFsLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtPcHRpbWl6ZVN2Y0hvc3QiIENvbnRlbnQ9IkNhbGlicmFyIGRpdmlzw6NvIGRlIHByb2Nlc3NvcyBkZSBzZXJ2acOnb3MgKFN2Y0hvc3QpIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJBanVzdGEgbyBpc29sYW1lbnRvIGRlIHNlcnZpw6dvcyBkZSBhY29yZG8gY29tIGEgcXVhbnRpZGFkZSB0b3RhbCBkZSBtZW3Ds3JpYSBSQU0uIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0VuYWJsZUxvbmdQYXRocyIgQ29udGVudD0iSGFiaWxpdGFyIHN1cG9ydGUgYSBjYW1pbmhvcyBsb25nb3MgZGUgYXJxdWl2b3MiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IlJlbW92ZSBhIGxpbWl0YcOnw6NvIGxlZ2FkYSBkZSAyNjAgY2FyYWN0ZXJlcyAoTUFYX1BBVEgpIGVtIGNhbWluaG9zIGRlIGFycXVpdm9zIGUgcGFzdGFzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlTG9ja1NjcmVlbiIgQ29udGVudD0iUHVsYXIgdGVsYSBkZSBibG9xdWVpbyBlc3TDoXRpY2EiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkFwcmVzZW50YSBvIGNhbXBvIGRlIGF1dGVudGljYcOnw6NvIGRpcmV0YW1lbnRlIGFvIGxpZ2FyIG91IGRlc2Jsb3F1ZWFyIG8gY29tcHV0YWRvci4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrSXNEZXYiIENvbnRlbnQ9IkNvbmZpZ3VyYcOnw7VlcyBwYXJhIGRlc2Vudm9sdmVkb3JlcyAoRGlhZ27Ds3N0aWNvcyBkZSBCb290IGUgUkRQKSIgSXNDaGVja2VkPSJGYWxzZSIgVG9vbFRpcD0iSGFiaWxpdGEgbWVuc2FnZW5zIGRldGFsaGFkYXMgZGUgaW5pY2lhbGl6YcOnw6NvICh2ZXJib3Nlc3RhdHVzKSBlIHJlbW92ZSBhdmlzb3MgcmVwZXRpdGl2b3MgZGUgY29uZXjDo28gUkRQLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEdWFsQm9vdFV0YyIgQ29udGVudD0iU2luY3Jvbml6YXIgUmVsw7NnaW8gVVRDIHBhcmEgRHVhbCBCb290IChMaW51eCAvIEZlZG9yYSkiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkNvbmZpZ3VyYSBvIHJlbMOzZ2lvIGRhIHBsYWNhLW3Do2UgZW0gVVRDIChwYWRyw6NvIG9maWNpYWwgZG8gTGludXgpIGUgc2luY3Jvbml6YSBhdXRvbWF0aWNhbWVudGUgY29tIG8gc2Vydmlkb3IgTlRQIG9maWNpYWwsIGVsaW1pbmFuZG8gYSBkaWZlcmVuw6dhIGRlIGhvcsOhcmlvIG5vIGR1YWwgYm9vdC4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIEluZGVwZW5kZW50ZSBkZSBBY2FvIGUgUHJvZ3Jlc3NvIGRhcyBPdGltaXphY29lcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjEwIiBQYWRkaW5nPSIxNiwxMiIgTWFyZ2luPSI2LDEyLDYsNiI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Sb3dEZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLlJvd0RlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIExpbmhhIDE6IFN0YXR1cyBkYSBvdGltaXphY2FvICsgUG9yY2VudGFnZW0gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBOYW1lPSJsYmxTdGF0dXNUd2Vha3MiIEdyaWQuUm93PSIwIiBHcmlkLkNvbHVtbj0iMCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRleHQ9IkFzIG90aW1pemHDp8O1ZXMgc8OjbyBhcGxpY2FkYXMgZGlyZXRhbWVudGUgbm8gUmVnaXN0cm8gZSBub3Mgc2VydmnDp29zIGRvIHNpc3RlbWEuIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiBNYXJnaW49IjAsMCwwLDgiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUZXh0VHJpbW1pbmc9IkNoYXJhY3RlckVsbGlwc2lzIiAvPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIE5hbWU9ImxibFBlcmNlbnRUd2Vha3MiIEdyaWQuUm93PSIwIiBHcmlkLkNvbHVtbj0iMSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRleHQ9IjAlIiBGb250U2l6ZT0iMTIiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM0QURFODAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiBIb3Jpem9udGFsQWxpZ25tZW50PSJSaWdodCIgTWFyZ2luPSIwLDAsMCw4IiAvPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIExpbmhhIDI6IEJhcnJhIGRlIFByb2dyZXNzbyArIEJvdGFvIGRlIEFjYW8gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFByb2dyZXNzQmFyIE5hbWU9InBiVHdlYWtzIiBHcmlkLlJvdz0iMSIgR3JpZC5Db2x1bW49IjAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEhlaWdodD0iMTAiIE1pbmltdW09IjAiIE1heGltdW09IjEwMCIgVmFsdWU9IjAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiMxMzE0MUYiIEZvcmVncm91bmQ9IiMyMkM1NUUiIEJvcmRlclRoaWNrbmVzcz0iMCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgTWFyZ2luPSIwLDAsMTYsMCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5BcHBseU9wdGltaXphdGlvbnMiIEdyaWQuUm93PSIxIiBHcmlkLkNvbHVtbj0iMSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIENvbnRlbnQ9IkFwbGljYXIgT3RpbWl6YcOnw7VlcyBTZWxlY2lvbmFkYXMiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBCYWNrZ3JvdW5kPSIjMTZBMzRBIiBCb3JkZXJCcnVzaD0iIzIyQzU1RSIgRm9yZWdyb3VuZD0iV2hpdGUiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb250V2VpZ2h0PSJCb2xkIiBGb250U2l6ZT0iMTMiIFBhZGRpbmc9IjIwLDEwIiBDdXJzb3I9IkhhbmQiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdHlsZSBUYXJnZXRUeXBlPSJCb3JkZXIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkNvcm5lclJhZGl1cyIgVmFsdWU9IjgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0eWxlPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbi5SZXNvdXJjZXM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9CdXR0b24+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgIDwvU2Nyb2xsVmlld2VyPgogICAgICAgICAgICA8L1RhYkl0ZW0+CgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8IS0tIEFCQSAzOiBSRUNVUlNPUyBPUENJT05BSVMgRE8gV0lORE9XUyAoRElTTSkgICAgICAgICAgICAgIC0tPgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8VGFiSXRlbSBOYW1lPSJ0YWJJdGVtRmVhdHVyZXMiIEhlYWRlcj0iIFJlY3Vyc29zIE9wY2lvbmFpcyAvIEV4dHJhcyAiPgogICAgICAgICAgICAgICAgPFNjcm9sbFZpZXdlciBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIE1hcmdpbj0iMTAiPgogICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIE5vdGlmaWNhY2FvIGRlIFJlY3Vyc29zIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMxQTFCMjYiIEJvcmRlckJydXNoPSIjMkYzNTRGIiBCb3JkZXJUaGlja25lc3M9IjEiIENvcm5lclJhZGl1cz0iOCIgUGFkZGluZz0iMTQiIE1hcmdpbj0iNiwwLDYsMTAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJSZWN1cnNvcyBvcGNpb25haXMgZG8gV2luZG93cyBnZXJlbmNpYWRvcyBuYXRpdmFtZW50ZSB2aWEgRElTTToiIEZvbnRTaXplPSIxNSIgRm9udFdlaWdodD0iU2VtaUJvbGQiIEZvcmVncm91bmQ9IiNDOEQzRjUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBQZXJmaXMgUsOhcGlkb3MgZGUgUmVjdXJzb3MgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUGVyZmlzIFLDoXBpZG9zIGRlIFJlY3Vyc29zOiIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJTZW1pQm9sZCIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSI4LDQsOCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8VW5pZm9ybUdyaWQgQ29sdW1ucz0iMiIgTWFyZ2luPSIwLDAsMCwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgUGVyZmlsIEdlcmFsIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUGVyZmlsIEdlcmFsIiBGb250U2l6ZT0iMTUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiMzOEJERjgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iQ29tcGF0aWJpbGlkYWRlIGVzc2VuY2lhbCBjb20gam9nb3MgZSBwcm9ncmFtYXMgbGVnYWRvcyBzZW0gY29uc3VtbyBleHRyYSBkZSByZWN1cnNvcy4iIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgTWFyZ2luPSIwLDMsMCw2IiBUZXh0V3JhcHBpbmc9IldyYXAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0i4oCiIEhhYmlsaXRhIGFwZW5hcyBvIC5ORVQgRnJhbWV3b3JrIDMuNSAoMi4wLzMuMCkmI3gwYTvigKIgTWFudMOpbSByZWN1cnNvcyBkZSB2aXJ0dWFsaXphw6fDo28gZGVzYXRpdmFkb3MiIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSIwLDIsMCwxMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5QcmVzZXRGZWF0R2VuZXJhbCIgQ29udGVudD0iU2VsZWNpb25hciBQZXJmaWwgR2VyYWwgKC5ORVQgYXBlbmFzKSIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBCYWNrZ3JvdW5kPSIjMDI4NEM3IiBCb3JkZXJCcnVzaD0iIzM4QkRGOCIgRm9yZWdyb3VuZD0iV2hpdGUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIFBlcmZpbCBEZXYgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJQZXJmaWwgRGVzZW52b2x2ZWRvciAoRGV2KSIgRm9udFNpemU9IjE1IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjQkI5QUY3IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkFtYmllbnRlIGNvbXBsZXRvIGRlIGRlc2Vudm9sdmltZW50bywgY29udMOqaW5lcmVzIGUgdGVzdGVzIHNlZ3Vyb3MgaXNvbGFkb3MuIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsNiIgVGV4dFdyYXBwaW5nPSJXcmFwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IuKAoiBIYWJpbGl0YSB0b2RvcyBvcyA1IHJlY3Vyc29zIG9wY2lvbmFpcyYjeDBhO+KAoiAuTkVUIDMuNSwgV1NMMiwgSHlwZXItViwgU2FuZGJveCBlIFBsYXRhZm9ybWEgVk0iIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSIwLDIsMCwxMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5QcmVzZXRGZWF0RGV2IiBDb250ZW50PSJTZWxlY2lvbmFyIFBlcmZpbCBEZXNlbnZvbHZlZG9yIChUdWRvKSIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBCYWNrZ3JvdW5kPSIjN0MzQUVEIiBCb3JkZXJCcnVzaD0iIzhCNUNGNiIgRm9yZWdyb3VuZD0iV2hpdGUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvVW5pZm9ybUdyaWQ+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIEJhcnJhIGRlIEZlcnJhbWVudGFzIGRlIFNlbGXDp8OjbyBkZSBSZWN1cnNvcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjEyIiBNYXJnaW49IjYsMCw2LDEwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlNlbGXDp8OjbyBQZXJzb25hbGl6YWRhIGRlIFJlY3Vyc29zOiIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSIgT3JpZW50YXRpb249Ikhvcml6b250YWwiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0blNlbGVjdEFsbEZlYXQiIENvbnRlbnQ9Ik1hcmNhciBUb2RvcyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBNYXJnaW49IjAsMCw2LDAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuRGVzZWxlY3RBbGxGZWF0IiBDb250ZW50PSJEZXNtYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkNvbXBvbmVudGVzIGUgUmVjdXJzb3MgZG8gU2lzdGVtYSIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0RDRkZGIiBNYXJnaW49IjAsMCwwLDgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImZlYXROZXRGeDMiIENvbnRlbnQ9Ii5ORVQgRnJhbWV3b3JrIDMuNSAoQ29tcGF0aWJpbGlkYWRlIGxlZ2FkYSBjb20gdmVyc8O1ZXMgMi4wIGUgMy4wKSIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iZmVhdFdzbCIgQ29udGVudD0iU3Vic2lzdGVtYSBkbyBXaW5kb3dzIHBhcmEgTGludXggKFdTTDIpIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJmZWF0Vm1QbGF0Zm9ybSIgQ29udGVudD0iUGxhdGFmb3JtYSBkZSBNw6FxdWluYSBWaXJ0dWFsIChQcsOpLXJlcXVpc2l0byBkbyBXU0wyKSIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iZmVhdEh5cGVyViIgQ29udGVudD0iSHlwZXItViAoVmlydHVhbGl6YcOnw6NvIG5hdGl2YSBwYXJhIG3DoXF1aW5hcyB2aXJ0dWFpcyBlIERvY2tlcikiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImZlYXRTYW5kYm94IiBDb250ZW50PSJXaW5kb3dzIFNhbmRib3ggKEFtYmllbnRlIGlzb2xhZG8gcGFyYSB0ZXN0ZXMgc2VndXJvcykiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIEluZGVwZW5kZW50ZSBkZSBBY2FvIGUgUHJvZ3Jlc3NvIGRlIFJlY3Vyc29zIERJU00gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSIxMCIgUGFkZGluZz0iMTYsMTIiIE1hcmdpbj0iNiwxMiw2LDYiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuUm93RGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBMaW5oYSAxOiBTdGF0dXMgZG8gcmVjdXJzbyArIFBvcmNlbnRhZ2VtIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0ibGJsU3RhdHVzRmVhdHVyZXMiIEdyaWQuUm93PSIwIiBHcmlkLkNvbHVtbj0iMCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRleHQ9IlJlcXVlciBjb25leMOjbyBjb20gYSBpbnRlcm5ldCBwYXJhIGJhaXhhciBhcnF1aXZvcyBkZSBjb21wb25lbnRlcyBhZGljaW9uYWlzIGRhIE1pY3Jvc29mdC4iCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIE1hcmdpbj0iMCwwLDAsOCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIFRleHRUcmltbWluZz0iQ2hhcmFjdGVyRWxsaXBzaXMiIC8+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0ibGJsUGVyY2VudEZlYXR1cmVzIiBHcmlkLlJvdz0iMCIgR3JpZC5Db2x1bW49IjEiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICBUZXh0PSIwJSIgRm9udFNpemU9IjEyIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjQkI5QUY3IgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgSG9yaXpvbnRhbEFsaWdubWVudD0iUmlnaHQiIE1hcmdpbj0iMCwwLDAsOCIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBMaW5oYSAyOiBCYXJyYSBkZSBQcm9ncmVzc28gKyBCb3RhbyBkZSBBY2FvIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxQcm9ncmVzc0JhciBOYW1lPSJwYkZlYXR1cmVzIiBHcmlkLlJvdz0iMSIgR3JpZC5Db2x1bW49IjAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEhlaWdodD0iMTAiIE1pbmltdW09IjAiIE1heGltdW09IjEwMCIgVmFsdWU9IjAiCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiMxMzE0MUYiIEZvcmVncm91bmQ9IiM4QjVDRjYiIEJvcmRlclRoaWNrbmVzcz0iMCIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgTWFyZ2luPSIwLDAsMTYsMCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5FbmFibGVGZWF0dXJlcyIgR3JpZC5Sb3c9IjEiIEdyaWQuQ29sdW1uPSIxIgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgQ29udGVudD0iSGFiaWxpdGFyIFJlY3Vyc29zIFNlbGVjaW9uYWRvcyIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEJhY2tncm91bmQ9IiM3QzNBRUQiIEJvcmRlckJydXNoPSIjOEI1Q0Y2IiBGb3JlZ3JvdW5kPSJXaGl0ZSIKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIEZvbnRXZWlnaHQ9IkJvbGQiIEZvbnRTaXplPSIxMyIgUGFkZGluZz0iMjAsMTAiIEN1cnNvcj0iSGFuZCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24uUmVzb3VyY2VzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0eWxlIFRhcmdldFR5cGU9IkJvcmRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3R5bGU+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgPC9TY3JvbGxWaWV3ZXI+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDwhLS0gQUJBIDQ6IFJFR0lTVFJPIEUgTE9HUyBFTSBURU1QTyBSRUFMICAgICAgICAgICAgICAgICAgICAgLS0+CiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDxUYWJJdGVtIE5hbWU9InRhYkl0ZW1Mb2ciIEhlYWRlcj0iIFJlZ2lzdHJvIGUgTG9ncyAiPgogICAgICAgICAgICAgICAgPEdyaWQgTWFyZ2luPSIxMCI+CiAgICAgICAgICAgICAgICAgICAgPEdyaWQuUm93RGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSIqIiAvPgogICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Sb3c9IjAiIE9yaWVudGF0aW9uPSJIb3Jpem9udGFsIiBNYXJnaW49IjAsMCwwLDgiPgogICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkFjb21wYW5oYW1lbnRvIGVtIHRlbXBvIHJlYWwgZGEgZXhlY3XDp8OjbyBlIGF1ZGl0b3JpYSBkZSBzaXN0ZW1hOiIgRm9udFNpemU9IjEzIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkJhY2tUb09wdGlvbnMiIENvbnRlbnQ9IuKshSBWb2x0YXIgw6BzIE9ww6fDtWVzIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iMTIsMCwwLDAiIFBhZGRpbmc9IjEwLDMiIEZvbnRTaXplPSIxMSIgQmFja2dyb3VuZD0iIzI1NjNFQiIgQm9yZGVyQnJ1c2g9IiMzQjgyRjYiIEZvcmVncm91bmQ9IldoaXRlIiBGb250V2VpZ2h0PSJCb2xkIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bk9wZW5Mb2dGb2xkZXIiIENvbnRlbnQ9IkFicmlyIFBhc3RhIGRlIExvZ3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSI4LDAsMCwwIiBQYWRkaW5nPSI4LDMiIEZvbnRTaXplPSIxMSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5DbGVhckxvZ0NvbnNvbGUiIENvbnRlbnQ9IkxpbXBhciBDb25zb2xlIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iOCwwLDAsMCIgUGFkZGluZz0iOCwzIiBGb250U2l6ZT0iMTEiIC8+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgoKICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEdyaWQuUm93PSIxIiBCYWNrZ3JvdW5kPSIjMEEwQjEwIiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjgiPgogICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJveCBOYW1lPSJ0eHRDb25zb2xlTG9nIiBCYWNrZ3JvdW5kPSJUcmFuc3BhcmVudCIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgRm9udEZhbWlseT0iQ29uc29sYXMsIENhc2NhZGlhIENvZGUsIENvdXJpZXIgTmV3IiBGb250U2l6ZT0iMTIiIElzUmVhZE9ubHk9IlRydWUiIEJvcmRlclRoaWNrbmVzcz0iMCIgVGV4dFdyYXBwaW5nPSJXcmFwIiBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIFRleHQ9IkRFV0lOIEJvb3N0ZXIgcHJvbnRvLiBTZWxlY2lvbmUgcHJvZ3JhbWFzIG91IG90aW1pemHDp8O1ZXMgcGFyYSBjb21lw6dhci4iIC8+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgPC9UYWJDb250cm9sPgoKCiAgICA8L0dyaWQ+CjwvV2luZG93Pgo=
'@))

# ==============================================================================
# DEWIN Entrypoint Principal
# ==============================================================================
try {
    Initialize-DewinLogging

    $hw = Get-DewinHardwareInfo

    if ($Profile -ne 'GUI' -or $Silent) {
        # ExecuÃ§Ã£o em Modo Linha de Comando (Headless / Silencioso)
        $chosenPreset = if ($Profile -eq 'GUI') { $hw.RecommendedProfile } else { $Profile }
        Write-Host "Iniciando DEWIN Booster em modo CLI com perfil: $chosenPreset" -ForegroundColor Cyan
        $presetData = Get-DewinPreset -Name $chosenPreset
        Invoke-DewinExecution -Tweaks $presetData.Tweaks -Apps $presetData.Apps -Features $presetData.Features -Hardware $hw
        if (-not $NoRestart) {
            $r = Read-Host "Deseja reiniciar o computador agora? (S/N)"
            if ($r -match '^[sSyY]') { Restart-Computer }
        }
    } else {
        # ExecuÃ§Ã£o em Modo Interface GrÃ¡fica (WPF)
        Start-DewinGui -XamlString $global:DewinXaml -Hardware $hw
    }
} catch {
    Write-Host ""
    Write-Host "[!] Erro fatal durante a execuÃ§Ã£o do DEWIN:" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host ""
    Write-Host "Pressione Enter para fechar..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
    exit 1
}
