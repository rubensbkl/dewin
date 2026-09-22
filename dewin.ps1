# ==============================================================================
# DEWIN Booster - Universal Windows Optimizer & Debloater (Single-Script Edition)
# Execucao via terminal:
# irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral', 'GUI')]
    [string]$Profile = 'GUI',
    [switch]$Silent,
    [switch]$NoRestart
)

# 0. Codificacao UTF-8 para Console
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 1. Auto-Elevacao Administrativa (UAC)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[*] Privilegios de Administrador necessarios. Elevando via UAC...' -ForegroundColor Cyan
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
        Write-Host ' [!] PRIVILEGIOS DE ADMINISTRADOR NECESSARIOS' -ForegroundColor Yellow
        Write-Host ' O DEWIN precisa ser executado em um terminal com privilÃ©gios de Administrador.' -ForegroundColor Yellow
        Write-Host ' Clique com o botao direito no Iniciar -> Terminal (Administrador)' -ForegroundColor Cyan
        Write-Host ' e execute novamente:' -ForegroundColor Cyan
        Write-Host ' irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex' -ForegroundColor White
        Write-Host '==================================================================' -ForegroundColor Yellow
        exit 1
    }
}

# --- Modulo: src\core\Logger.ps1 ---
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


# --- Modulo: src\core\Registry.ps1 ---
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


# --- Modulo: src\core\Hardware.ps1 ---
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
        GpuNames         = 'Nao detectada'
        WinVersion       = 'Windows 11'
        WinBuild         = 0
        IsLaptop         = $false
        DeviceTypeStr    = 'Desktop'
        RecommendedProfile = 'DesktopGeral'
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
    $info.RecommendedProfile = if ($info.IsLaptop) { 'LaptopGeral' } else { 'DesktopGeral' }

    return [PSCustomObject]$info
}


# --- Modulo: src\tweaks\InterfaceTweaks.ps1 ---
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

    Write-DewinLog -Level STEP -Message '[*] Aplicando otimizacoes de interface e barra de tarefas...'
    $advExplorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    # Barra de tarefas: Ocultar caixa de pesquisa
    if ($HideSearch) {
        Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0
    }

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


# --- Modulo: src\tweaks\PerformanceTweaks.ps1 ---
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

    Write-DewinLog -Level STEP -Message '[*] Aplicando otimizacoes de desempenho, latencia e SSD...'

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

    # Resposta Linear do Mouse (1:1 sem aceleracao)
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

    Write-DewinLog -Level SUCCESS -Message '  [+] Desempenho, latencia de rede, GameDVR e SSD calibrados.'
}


# --- Modulo: src\tweaks\PrivacyTweaks.ps1 ---
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

    # Desativação de Copilot e IA Recall
    if ($DisableCopilotRecall) {
        Set-DewinReg -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
        Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowCopilotButton' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Value 1
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
    foreach ($app in $bloatwareList) {
        try {
            $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removedCount++
            }
            Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -eq $app } |
                Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }

    Write-DewinLog -Level SUCCESS -Message "  [+] Limpeza de $removedCount bloatwares concluida."
}


# --- Modulo: src\tweaks\SystemTweaks.ps1 ---
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
        [switch]$DisableLockScreen = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando calibracoes de sistema, GPU e energia...'

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
            Write-DewinLog -Level STEP -Message '  [*] Configurando hibernacao segura compacta para Notebook...'
            try {
                powercfg.exe /hibernate on 2>$null | Out-Null
                powercfg.exe /h /type reduced 2>$null | Out-Null
            } catch {}
        } else {
            Write-DewinLog -Level STEP -Message '  [*] Desativando hibernacao para Desktop (recuperando espaco SSD)...'
            try { powercfg.exe /hibernate off 2>$null | Out-Null } catch {}
        }
    }

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
        # Relógio da Placa-Mãe em UTC (sincronização perfeita com Dual-Boot Linux)
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal' -Value 1
        # Mensagens detalhadas de inicialização e desligamento
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'verbosestatus' -Value 1
        # Desativação de aviso repetitivo de RDP não assinado
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client' -Name 'RedirectionWarningDialogVersion' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Terminal Server Client' -Name 'RdpLaunchConsentAccepted' -Value 1
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Calibracoes de sistema, GPU e energia aplicadas com sucesso.'
}


# --- Modulo: src\packages\SoftwareInstaller.ps1 ---
# ==============================================================================
# DEWIN Packages: Instalador de Softwares via Winget
# ==============================================================================

function Get-DewinSoftwareCatalog {
    [CmdletBinding()]
    param()

    return @(
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Name = 'Visual C++ 2015-2022 (x64)'; Category = 'Essenciais'; Default = $true },
        @{ Id = 'Microsoft.VCRedist.2015+.x86'; Name = 'Visual C++ 2015-2022 (x86)'; Category = 'Essenciais'; Default = $true },
        @{ Id = '7zip.7zip';                   Name = '7-Zip (Compactador Ultra-Rápido)'; Category = 'Essenciais'; Default = $true },
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

    Write-DewinLog -Level STEP -Message "[*] Iniciando instalacao de $($AppIds.Count) pacotes via Winget..."

    $hasInternet = $false
    try {
        $hasInternet = [bool](Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue)
    } catch {}

    if (-not $hasInternet) {
        Write-DewinLog -Level WARN -Message '  [!] Sem conexao com a internet. Instalacao de pacotes ignorada.'
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
            $pct = 90 + [int](($current / $total) * 7)
            try { & $OnProgress $pct "Instalando ($current/$total): $appName..." } catch {}
        }

        Write-DewinLog -Level STEP -Message "  [*] Instalando $appName ($id)..."
        try {
            $wingetProc = Start-Process -FilePath 'winget.exe' -ArgumentList "install --id `"$id`" --exact --silent --accept-package-agreements --accept-source-agreements --force" -NoNewWindow -PassThru -Wait
            if ($wingetProc.ExitCode -eq 0) {
                Write-DewinLog -Level SUCCESS -Message "  [+] $appName instalado com sucesso."
            } else {
                Write-DewinLog -Level INFO -Message "  [i] Winget $appName finalizou com codigo $($wingetProc.ExitCode)" -NoConsole
            }
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Falha ao instalar ${appName}: $($_.Exception.Message)"
        }
    }
}


# --- Modulo: src\packages\WindowsFeatures.ps1 ---
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
            $pct = 85 + [int](($current / $total) * 5)
            try { & $OnProgress $pct "Habilitando ($current/$total): recurso $feat..." } catch {}
        }
        Write-DewinLog -Level STEP -Message "  [*] Habilitando recurso: $feat..."
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-DewinLog -Level SUCCESS -Message "  [+] Recurso $feat pronto."
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Nao foi possivel habilitar ${feat}: $($_.Exception.Message)"
        }
    }
}


# --- Modulo: src\engine\Presets.ps1 ---
# ==============================================================================
# DEWIN Engine: Mapeamento de Perfis de Otimização
# ==============================================================================

function Get-DewinPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet('DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral')]
        [string]$Name
    )

    $isLaptop = $Name -like 'Laptop*'
    $isDev = $Name -like '*Dev'

    $tweaks = [ordered]@{
        # Interface
        HideSearch              = $true
        HideTaskView            = $true
        CenterTaskbar           = $true
        TaskbarEndTask          = $true
        ClassicContextMenu      = $true
        LaunchToThisPC          = $true
        ShowExtensionsAndHidden = $true
        AlwaysShowScrollbars    = $true

        # Desempenho
        OptimizeNetworkLatency  = $true
        DisableGameDVR          = $true
        LinearMouse             = $true
        DisableStickyKeys       = $true
        InstantMenuDelay        = $true
        OptimizeSsdAccess       = $true
        CleanTempFiles          = $true

        # Privacidade
        DisableTelemetry        = $true
        DisableCeipTasks        = $true
        DisableCopilotRecall    = $true
        DisableBingSearch       = $true
        DebloatEdge             = $true
        RemoveUwpBloat          = $true

        # Sistema & Hardware
        CalibrateGpu            = $true
        SmartHibernation        = $true
        DisableReservedStorage  = $true
        OptimizeSvcHost         = $true
        EnableLongPaths         = $true
        DisableLockScreen       = $true
        IsLaptop                = $isLaptop
        IsDev                   = $isDev
    }

    # Softwares padrão por perfil
    $apps = @(
        'Microsoft.VCRedist.2015+.x64',
        'Microsoft.VCRedist.2015+.x86',
        '7zip.7zip',
        'Google.Chrome'
    )
    if ($isDev) {
        $apps += @('Microsoft.VisualStudioCode', 'Git.Git')
    }

    # Recursos DISM por perfil
    $features = @('NetFx3')
    if ($isDev) {
        $features += @('VirtualMachinePlatform', 'Microsoft-Windows-Subsystem-Linux', 'Microsoft-Hyper-V-All', 'Containers-DisposableClientVM')
    }

    return [PSCustomObject]@{
        Name        = $Name
        IsLaptop    = $isLaptop
        IsDev       = $isDev
        Tweaks      = $tweaks
        Apps        = $apps
        Features    = $features
        Description = switch ($Name) {
            'DesktopDev'   { 'Desktop Dev & Workstation: WSL2, Hyper-V, Sandbox, ferramentas Dev, sem hibernacao (recupera SSD).' }
            'DesktopGeral' { 'Desktop Geral & Jogos: Maxima leveza, menor latencia de rede e entrada, SSD liberado, sem virtualizacao.' }
            'LaptopDev'    { 'Notebook Dev & Workstation: WSL2, Hyper-V, Sandbox, ferramentas Dev, hibernacao segura compacta.' }
            'LaptopGeral'  { 'Notebook Geral & Jogos: Maxima autonomia de bateria e FPS, sem virtualizacao, hibernacao compacta.' }
        }
    }
}


# --- Modulo: src\engine\Runner.ps1 ---
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

    & $updateProgress 5 "Inicializando auditoria e configuracoes de sistema..."

    # 1. Cabecalho de Auditoria
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "DEWIN BOOSTER - REGISTRO DE AUDITORIA E OTIMIZAÇÕES"
    Write-DewinLog -Level RAW -Message "Data e Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-DewinLog -Level RAW -Message "Sistema Operacional: $($Hardware.WinVersion) (Build $($Hardware.WinBuild))"
    Write-DewinLog -Level RAW -Message "Dispositivo: $($Hardware.Manufacturer) $($Hardware.Model) ($($Hardware.DeviceTypeStr))"
    Write-DewinLog -Level RAW -Message "Memoria RAM: $($Hardware.RamTotalGB) GB"
    Write-DewinLog -Level RAW -Message "GPU(s): $($Hardware.GpuNames)"
    Write-DewinLog -Level RAW -Message "Usuario Administrador: $($Hardware.IsAdmin)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    # 2. Calibrações de Sistema, GPU e Energia
    & $updateProgress 15 "Calibrando GPU, energia e servicos de sistema..."
    Invoke-DewinSystemTweaks -IsLaptop ([bool]$Tweaks['IsLaptop']) `
                            -IsDev ([bool]$Tweaks['IsDev']) `
                            -RamGB ([int]$Hardware.RamTotalGB) `
                            -CalibrateGpu:([bool]$Tweaks['CalibrateGpu']) `
                            -SmartHibernation:([bool]$Tweaks['SmartHibernation']) `
                            -DisableReservedStorage:([bool]$Tweaks['DisableReservedStorage']) `
                            -OptimizeSvcHost:([bool]$Tweaks['OptimizeSvcHost']) `
                            -EnableLongPaths:([bool]$Tweaks['EnableLongPaths']) `
                            -DisableLockScreen:([bool]$Tweaks['DisableLockScreen'])

    # 3. Privacidade e Debloat
    & $updateProgress 35 "Aplicando ajustes de privacidade e telemetria..."
    Invoke-DewinPrivacyTweaks -DisableTelemetry:([bool]$Tweaks['DisableTelemetry']) `
                             -DisableCeipTasks:([bool]$Tweaks['DisableCeipTasks']) `
                             -DisableCopilotRecall:([bool]$Tweaks['DisableCopilotRecall']) `
                             -DisableBingSearch:([bool]$Tweaks['DisableBingSearch']) `
                             -DebloatEdge:([bool]$Tweaks['DebloatEdge'])

    if ([bool]$Tweaks['RemoveUwpBloat']) {
        & $updateProgress 50 "Removendo bloatwares UWP de terceiros..."
        Invoke-DewinDebloat
    }

    # 4. Interface e Barra de Tarefas
    & $updateProgress 65 "Otimizando interface, barra de tarefas e Explorer..."
    Invoke-DewinInterfaceTweaks -HideSearch:([bool]$Tweaks['HideSearch']) `
                               -HideTaskView:([bool]$Tweaks['HideTaskView']) `
                               -CenterTaskbar:([bool]$Tweaks['CenterTaskbar']) `
                               -TaskbarEndTask:([bool]$Tweaks['TaskbarEndTask']) `
                               -ClassicContextMenu:([bool]$Tweaks['ClassicContextMenu']) `
                               -LaunchToThisPC:([bool]$Tweaks['LaunchToThisPC']) `
                               -ShowExtensionsAndHidden:([bool]$Tweaks['ShowExtensionsAndHidden']) `
                               -AlwaysShowScrollbars:([bool]$Tweaks['AlwaysShowScrollbars'])

    # 5. Desempenho e Latência
    & $updateProgress 80 "Calibrando latencia de rede, GameDVR e SSD..."
    Invoke-DewinPerformanceTweaks -OptimizeNetworkLatency:([bool]$Tweaks['OptimizeNetworkLatency']) `
                                 -DisableGameDVR:([bool]$Tweaks['DisableGameDVR']) `
                                 -LinearMouse:([bool]$Tweaks['LinearMouse']) `
                                 -DisableStickyKeys:([bool]$Tweaks['DisableStickyKeys']) `
                                 -InstantMenuDelay:([bool]$Tweaks['InstantMenuDelay']) `
                                 -OptimizeSsdAccess:([bool]$Tweaks['OptimizeSsdAccess']) `
                                 -CleanTempFiles:([bool]$Tweaks['CleanTempFiles'])

    # 6. Reiniciar Explorer
    & $updateProgress 95 "Atualizando o Windows Explorer..."
    Restart-DewinExplorer

    # 7. Conclusão e Sumário
    $elapsedSec = if ($global:DewinTimer) { [math]::Round($global:DewinTimer.Elapsed.TotalSeconds, 1) } else { 0 }
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "OTIMIZAÇÕES APLICADAS COM SUCESSO"
    Write-DewinLog -Level RAW -Message "Tempo Total: $elapsedSec segundos"
    Write-DewinLog -Level RAW -Message "Estatisticas: Sucessos=$($global:DewinStats.Success), Avisos=$($global:DewinStats.Warnings), Erros=$($global:DewinStats.Errors)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    try {
        Copy-Item -Path $global:DewinLogPath -Destination $global:DewinLatestLog -Force -ErrorAction SilentlyContinue
    } catch {}

    & $updateProgress 100 "Otimizações finalizadas com sucesso em $elapsedSec s!"
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
    Write-DewinLog -Level RAW -Message "DEWIN BOOSTER - INSTALACAO DE SOFTWARES"
    Write-DewinLog -Level RAW -Message "Data e Hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-DewinLog -Level RAW -Message "Quantidade de Softwares Selecionados: $($Apps.Count)"
    Write-DewinLog -Level RAW -Message '=================================================================='

    & $updateProgress 10 "Instalando $($Apps.Count) softwares selecionados via Winget..."
    Install-DewinSoftware -AppIds $Apps -OnProgress {
        param($pct, $msg)
        & $updateProgress $pct $msg
    }

    $elapsedSec = if ($global:DewinTimer) { [math]::Round($global:DewinTimer.Elapsed.TotalSeconds, 1) } else { 0 }
    Write-DewinLog -Level RAW -Message '=================================================================='
    Write-DewinLog -Level RAW -Message "INSTALACAO DE SOFTWARES FINALIZADA"
    Write-DewinLog -Level RAW -Message "Tempo Total: $elapsedSec segundos"
    Write-DewinLog -Level RAW -Message '=================================================================='

    try {
        Copy-Item -Path $global:DewinLogPath -Destination $global:DewinLatestLog -Force -ErrorAction SilentlyContinue
    } catch {}

    & $updateProgress 100 "Instalação de programas finalizada em $elapsedSec s!"
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

    & $updateProgress 5 "Inicializando modulo DISM do Windows..."
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

    & $updateProgress 100 "Recursos do Windows configurados em $elapsedSec s!"
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


# --- Modulo: src\engine\Controller.ps1 ---
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
        "💡 Notebook identificado! Recomendamos o Perfil [3] Notebook Dev (se for programador) ou [4] Notebook Geral (para máxima autonomia de bateria e jogos)."
    } else {
        "💡 Desktop identificado! Recomendamos o Perfil [1] Desktop Dev (se for programador) ou [2] Desktop Geral / Jogos (para máxima taxa de FPS e menor latência)."
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
        'chkEnableLongPaths', 'chkDisableLockScreen', 'chkIsDev'
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

    # 3. Funcao de Aplicacao de Perfil
    $applyPresetToGui = {
        param([string]$PresetName)
        $preset = Get-DewinPreset -Name $PresetName

        foreach ($chkName in $allTweakChecks) {
            $tweakKey = $chkName.Substring(3)
            if ($preset.Tweaks.Contains($tweakKey) -and $gui[$chkName]) {
                $gui[$chkName].IsChecked = [bool]$preset.Tweaks[$tweakKey]
            }
        }

        foreach ($k in $appMap.Keys) {
            if ($gui[$k]) { $gui[$k].IsChecked = ($preset.Apps -contains $appMap[$k]) }
        }

        foreach ($k in $featMap.Keys) {
            if ($gui[$k]) { $gui[$k].IsChecked = ($preset.Features -contains $featMap[$k]) }
        }

        $gui['lblProgressStatus'].Text = "Perfil '$PresetName' selecionado nas abas de otimizações e softwares."
    }

    # 4. Vinculação dos Botões de Perfis Rápidos (Aba 2: Otimizações)
    $gui['btnPresetDesktopDev'].Add_Click({ & $applyPresetToGui 'DesktopDev' })
    $gui['btnPresetDesktopGeral'].Add_Click({ & $applyPresetToGui 'DesktopGeral' })
    $gui['btnPresetLaptopDev'].Add_Click({ & $applyPresetToGui 'LaptopDev' })
    $gui['btnPresetLaptopGeral'].Add_Click({ & $applyPresetToGui 'LaptopGeral' })

    # Botões de Seleção de Tweaks (Aba 2)
    $gui['btnSelectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
    })
    $gui['btnDeselectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    })
    $gui['btnResetRecommended'].Add_Click({
        & $applyPresetToGui $Hardware.RecommendedProfile
    })

    # Botões de Seleção de Softwares (Aba 1)
    $gui['btnSelectEssentialApps'].Add_Click({
        $essentialIds = @('appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome')
        foreach ($c in $allAppChecks) {
            if ($gui[$c]) { $gui[$c].IsChecked = ($essentialIds -contains $c) }
        }
        $gui['lblProgressStatus'].Text = "Softwares essenciais (VC++, 7-Zip, Chrome) selecionados."
    })
    $gui['btnSelectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
    })
    $gui['btnDeselectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
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

    # Inicializa com o perfil recomendado pré-marcado
    & $applyPresetToGui $Hardware.RecommendedProfile

    # 5. Executador Assíncrono com UI Responsiva (Thread-Safe)
    $allActionButtons = @(
        'btnInstallSoftwares', 'btnApplyOptimizations', 'btnEnableFeatures',
        'btnSelectEssentialApps', 'btnSelectAllApps', 'btnDeselectAllApps',
        'btnSelectAll', 'btnDeselectAll', 'btnResetRecommended',
        'btnPresetDesktopDev', 'btnPresetDesktopGeral', 'btnPresetLaptopDev', 'btnPresetLaptopGeral'
    )

    $runDewinAsync = {
        param(
            [string]$ActionTitle,
            [scriptblock]$TaskScriptBlock,
            [array]$TaskArgs,
            [scriptblock]$OnCompleted
        )

        foreach ($btn in $allActionButtons) {
            if ($gui[$btn]) { $gui[$btn].IsEnabled = $false }
        }

        # Muda imediatamente para a aba de Log para visualização em tempo real
        if ($gui['mainTabControl'] -and $gui['tabItemLog']) {
            $gui['mainTabControl'].SelectedItem = $gui['tabItemLog']
        }
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

        $uiTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $uiTimer.Interval = [TimeSpan]::FromMilliseconds(100)

        $tickAction = {
            $ui = if ($global:DewinGui) { $global:DewinGui } elseif ($gui) { $gui } else { $null }
            if (-not $ui) { return }

            $s = if ($global:DewinSync) { $global:DewinSync } elseif ($sync) { $sync } else { $null }
            if (-not $s) { return }

            $pct = [int]$s.Percent
            if ($pct -lt 0) { $pct = 0 }
            if ($pct -gt 100) { $pct = 100 }

            $ui['pbExecution'].Value = $pct
            $ui['lblProgressPercent'].Text = "${pct}%"
            if ($s.Status) { $ui['lblProgressStatus'].Text = [string]$s.Status }

            if ($s.Messages.Count -gt 0) {
                $batchBuilder = [System.Text.StringBuilder]::new()
                while ($s.Messages.Count -gt 0) {
                    $msg = $s.Messages[0]
                    $s.Messages.RemoveAt(0)
                    [void]$batchBuilder.AppendLine($msg)
                }
                $ui['txtConsoleLog'].AppendText($batchBuilder.ToString())
                $ui['txtConsoleLog'].ScrollToEnd()
            }

            if ($s.IsDone) {
                $uiTimer.Stop()
                try { $psAsync.EndInvoke($asyncResult) | Out-Null } catch {}
                $psAsync.Dispose()
                $runspace.Close()
                $runspace.Dispose()

                foreach ($btn in $allActionButtons) {
                    if ($ui[$btn]) { $ui[$btn].IsEnabled = $true }
                }

                if ($OnCompleted) {
                    try { & $OnCompleted $s } catch {}
                }
            }
        }.GetNewClosure()

        $uiTimer.Add_Tick($tickAction)
        $uiTimer.Start()
    }

    # 6. Evento de Instalação de Softwares (Aba 1: Botão Independente)
    $gui['btnInstallSoftwares'].Add_Click({
        $selectedApps = @()
        foreach ($k in $appMap.Keys) {
            if ($gui[$k] -and $gui[$k].IsChecked) { $selectedApps += $appMap[$k] }
        }

        if ($selectedApps.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                "Nenhum programa foi selecionado.`r`nPor favor, marque ao menos um software na lista para instalar.",
                "DEWIN Booster - Selecione Softwares",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnInstallSoftwares'].Content = "⏳ INSTALANDO PROGRAMAS..."

        & $runDewinAsync "Instalação de Softwares via Winget" {
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
            $gui['btnInstallSoftwares'].Content = "$([char]::ConvertFromUtf32(0x1F4E5)) BAIXAR / INSTALAR PROGRAMAS SELECIONADOS"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "⚠️ Falha ao instalar softwares: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro ao instalar os softwares:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro & Log.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Softwares instalados/atualizados com sucesso!"
                [System.Windows.MessageBox]::Show(
                    "Os softwares selecionados foram instalados ou atualizados com sucesso via Winget!",
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

        $gui['btnApplyOptimizations'].Content = "⏳ APLICANDO OTIMIZAÇÕES..."

        & $runDewinAsync "Otimizações do Sistema" {
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
            $gui['btnApplyOptimizations'].Content = "⚡ APLICAR OTIMIZAÇÕES SELECIONADAS"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "⚠️ Falha nas otimizações: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro durante as otimizações:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro & Log.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Otimizações finalizadas com sucesso!"
                $res = [System.Windows.MessageBox]::Show(
                    "Otimizações aplicadas com sucesso!`r`n`r`nRecomenda-se reiniciar o computador para que todas as alterações de kernel e serviços entrem em vigor.`r`nDeseja reiniciar agora?",
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
                "Nenhum recurso opcional foi selecionado.`r`nPor favor, marque ao menos um recurso do Windows.",
                "DEWIN Booster - Selecione Recursos",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnEnableFeatures'].Content = "⏳ HABILITANDO RECURSOS..."

        & $runDewinAsync "Recursos Opcionais do Windows (DISM)" {
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
            $gui['btnEnableFeatures'].Content = "⚙️ HABILITAR RECURSOS SELECIONADOS"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "⚠️ Falha nos recursos DISM: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro ao configurar os recursos:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro & Log.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Recursos opcionais habilitados com sucesso!"
                [System.Windows.MessageBox]::Show(
                    "Recursos opcionais habilitados com sucesso via DISM!",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
        }
    })

    # 9. Exibição da Janela Modal
    $window.ShowDialog() | Out-Null
}


# --- Interface Grafica XAML ---
$global:DewinXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DEWIN Booster - Otimizador &amp; Debloater do Windows"
        Height="800" Width="1100" MinHeight="700" MinWidth="980"
        WindowStartupLocation="CenterScreen"
        Background="#0F111A" Foreground="#C8D3F5"
        FontFamily="Segoe UI, Segoe UI Variable, Arial">

    <Window.Resources>
        <!-- Paleta de Cores Moderna (DEWIN Dark Theme) -->
        <SolidColorBrush x:Key="BgDark" Color="#0F111A" />
        <SolidColorBrush x:Key="BgCard" Color="#1A1B26" />
        <SolidColorBrush x:Key="BgCardAlt" Color="#24283B" />
        <SolidColorBrush x:Key="BorderCard" Color="#2F354F" />
        <SolidColorBrush x:Key="PrimaryCyan" Color="#7DCFFF" />
        <SolidColorBrush x:Key="PrimaryBlue" Color="#7AA2F7" />
        <SolidColorBrush x:Key="AccentGreen" Color="#9ECE6A" />
        <SolidColorBrush x:Key="AccentYellow" Color="#E0AF68" />
        <SolidColorBrush x:Key="TextPrimary" Color="#C8D3F5" />
        <SolidColorBrush x:Key="TextMuted" Color="#7982A9" />

        <!-- Estilo dos CheckBoxes Modernos -->
        <Style TargetType="CheckBox">
            <Setter Property="Foreground" Value="#C8D3F5" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Margin" Value="0,5,0,5" />
            <Setter Property="Cursor" Value="Hand" />
        </Style>

        <!-- Estilo dos Botoes Secundarios -->
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#24283B" />
            <Setter Property="Foreground" Value="#C8D3F5" />
            <Setter Property="BorderBrush" Value="#414868" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Padding" Value="12,6" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="FontWeight" Value="SemiBold" />
        </Style>

        <!-- Estilo dos Cards de Perfil e Agrupamentos -->
        <Style x:Key="ProfileCard" TargetType="Border">
            <Setter Property="Background" Value="#1A1B26" />
            <Setter Property="BorderBrush" Value="#2F354F" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="CornerRadius" Value="10" />
            <Setter Property="Padding" Value="16" />
            <Setter Property="Margin" Value="6" />
        </Style>

        <!-- Estilo Moderno da Barra de Progresso -->
        <Style TargetType="ProgressBar">
            <Setter Property="Background" Value="#24283B" />
            <Setter Property="Foreground" Value="#7DCFFF" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Border Background="{TemplateBinding Background}" CornerRadius="5" ClipToBounds="True">
                            <Grid Name="PART_Track">
                                <Border Name="PART_Indicator" Background="{TemplateBinding Foreground}" HorizontalAlignment="Left" CornerRadius="5" />
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="16">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" /> <!-- Cabecalho e Banner de Hardware -->
            <RowDefinition Height="*" />    <!-- Area Principal com Abas -->
            <RowDefinition Height="Auto" /> <!-- Rodape de Status e Progresso -->
        </Grid.RowDefinitions>

        <!-- 1. CABECALHO & BANNER DE HARDWARE -->
        <Border Grid.Row="0" Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="10" Padding="16" Margin="0,0,0,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="⚡ DEWIN BOOSTER" FontSize="20" FontWeight="Bold" Foreground="#7DCFFF" VerticalAlignment="Center" />
                        <Border Background="#24283B" CornerRadius="5" Padding="6,2" Margin="10,0,0,0" VerticalAlignment="Center">
                            <TextBlock Text="100% Nativo &amp; Open-Source" FontSize="11" Foreground="#9ECE6A" FontWeight="SemiBold" />
                        </Border>
                    </StackPanel>
                    <TextBlock Name="txtHardwareBanner" Text="Detectando componentes de hardware..." FontSize="12" Foreground="#7982A9" Margin="0,5,0,0" />
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#24283B" BorderBrush="#414868" BorderThickness="1" CornerRadius="8" Padding="10,6" Margin="4,0">
                        <TextBlock Name="txtDeviceType" Text="Detectando..." FontSize="12" FontWeight="Bold" Foreground="#7AA2F7" />
                    </Border>
                </StackPanel>
            </Grid>
        </Border>

        <!-- 2. ABAS PRINCIPAIS -->
        <TabControl Name="mainTabControl" Grid.Row="1" Background="#13141F" BorderBrush="#2F354F">
            
            <!-- ======================================================== -->
            <!-- ABA 1: PROGRAMAS & SOFTWARES (TELA INICIAL)             -->
            <!-- ======================================================== -->
            <TabItem Name="tabItemSoftwares" Header=" 📦 Programas &amp; Softwares ">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="10">
                    <StackPanel>
                        <!-- Cabecalho e Acoes Rapidas -->
                        <Border Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,0,6,10">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>
                                
                                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                                    <TextBlock Text="Instalação e Atualização Oficial via Winget" FontSize="16" FontWeight="Bold" Foreground="#7DCFFF" />
                                    <TextBlock Text="Selecione os softwares que deseja instalar silenciosamente no computador:" FontSize="12" Foreground="#7982A9" Margin="0,3,0,0" />
                                </StackPanel>

                                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                                    <Button Name="btnSelectEssentialApps" Content="⭐ Essenciais" Style="{StaticResource SecondaryButton}" Margin="0,0,6,0" ToolTip="Seleciona VC++, 7-Zip e Chrome" />
                                    <Button Name="btnSelectAllApps" Content="✓ Marcar Todos" Style="{StaticResource SecondaryButton}" Margin="0,0,6,0" />
                                    <Button Name="btnDeselectAllApps" Content="✗ Desmarcar Todos" Style="{StaticResource SecondaryButton}" />
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Catalogo de Softwares em Grid -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>

                            <!-- Coluna 1: Runtimes e Navegadores -->
                            <StackPanel Grid.Column="0">
                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="🛠️ Runtimes &amp; Utilitários Essenciais" FontSize="14" FontWeight="Bold" Foreground="#7DCFFF" Margin="0,0,0,8" />
                                        <CheckBox Name="appVcRedist64" Content="Visual C++ 2015-2022 (x64) - Essencial para Jogos e Softwares" IsChecked="True" />
                                        <CheckBox Name="appVcRedist86" Content="Visual C++ 2015-2022 (x86) - Compatibilidade de Jogos 32-bit" IsChecked="True" />
                                        <CheckBox Name="app7zip" Content="7-Zip - Compactador e Descompactador Ultra-Rápido" IsChecked="True" />
                                    </StackPanel>
                                </Border>

                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="🌐 Navegadores Web" FontSize="14" FontWeight="Bold" Foreground="#9ECE6A" Margin="0,0,0,8" />
                                        <CheckBox Name="appChrome" Content="Google Chrome - Navegador Web Rápido e Seguro" IsChecked="True" />
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Coluna 2: Desenvolvimento e Multimidia/Jogos -->
                            <StackPanel Grid.Column="1">
                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="💻 Ferramentas de Desenvolvimento" FontSize="14" FontWeight="Bold" Foreground="#BB9AF7" Margin="0,0,0,8" />
                                        <CheckBox Name="appVsCode" Content="Visual Studio Code - Editor de Código da Microsoft" IsChecked="False" />
                                        <CheckBox Name="appGit" Content="Git for Windows - Sistema de Controle de Versão" IsChecked="False" />
                                    </StackPanel>
                                </Border>

                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="🎮 Jogos, Áudio &amp; Comunicação" FontSize="14" FontWeight="Bold" Foreground="#E0AF68" Margin="0,0,0,8" />
                                        <CheckBox Name="appDiscord" Content="Discord - Comunicação por Voz, Vídeo e Chat" IsChecked="False" />
                                        <CheckBox Name="appSteam" Content="Steam - Plataforma de Jogos e Comunidade" IsChecked="False" />
                                        <CheckBox Name="appVlc" Content="VLC Media Player - Reprodutor de Áudio e Vídeo Universal" IsChecked="False" />
                                        <CheckBox Name="appSpotify" Content="Spotify - Música e Podcasts em Streaming" IsChecked="False" />
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>

                        <!-- Botao Independente de Instalacao de Softwares -->
                        <Border Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,10,6,6">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>

                                <TextBlock Text="💡 A instalação é feita em segundo plano via Winget oficial sem interromper suas atividades." FontSize="12" Foreground="#7982A9" VerticalAlignment="Center" />
                                
                                <Button Name="btnInstallSoftwares" Grid.Column="1" Content="📥 BAIXAR / INSTALAR PROGRAMAS SELECIONADOS" Background="#2563EB" BorderBrush="#3B82F6" Foreground="White" FontWeight="Bold" FontSize="13" Padding="20,10" Cursor="Hand">
                                    <Button.Resources>
                                        <Style TargetType="Border">
                                            <Setter Property="CornerRadius" Value="8" />
                                        </Style>
                                    </Button.Resources>
                                </Button>
                            </Grid>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ======================================================== -->
            <!-- ABA 2: OTIMIZACOES, PERFIS & TWEAKS                      -->
            <!-- ======================================================== -->
            <TabItem Name="tabItemTweaks" Header=" ⚡ Otimizações &amp; Perfis ">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="10">
                    <StackPanel>
                        <!-- Notificacao de Recomendacao de Hardware -->
                        <Border Background="#1C2738" BorderBrush="#2563EB" BorderThickness="1" CornerRadius="8" Padding="12" Margin="6,0,6,10">
                            <TextBlock Name="txtRecommendation" Text="Calculando melhor perfil para sua máquina..." FontSize="13" Foreground="#93C5FD" TextWrapping="Wrap" />
                        </Border>

                        <!-- Seção dos 4 Perfis Rápidos de 1 Clique -->
                        <TextBlock Text="⚡ Perfis Rápidos Prontos (Clique para configurar automaticamente os tweaks):" FontSize="14" FontWeight="SemiBold" Foreground="#C8D3F5" Margin="8,4,8,8" />
                        <UniformGrid Columns="2" Margin="0,0,0,10">
                            <!-- Card Desktop Dev -->
                            <Border Style="{StaticResource ProfileCard}">
                                <StackPanel>
                                    <TextBlock Text="🚀 Desktop - Dev &amp; Workstation" FontSize="15" FontWeight="Bold" Foreground="#7DCFFF" />
                                    <TextBlock Text="Foco em desenvolvimento, compilação de código e máxima resposta do processador." FontSize="12" Foreground="#7982A9" Margin="0,3,0,6" TextWrapping="Wrap" />
                                    <TextBlock Text="• Sem hibernação (recupera espaço SSD igual à RAM)&#x0a;• Menor latência de rede e CPU sem amarras&#x0a;• Telemetria desativada e Explorer limpo" FontSize="11" Foreground="#C8D3F5" Margin="0,2,0,10" />
                                    <Button Name="btnPresetDesktopDev" Content="Selecionar Perfil Dev Desktop" Style="{StaticResource SecondaryButton}" Background="#2563EB" BorderBrush="#3B82F6" Foreground="White" />
                                </StackPanel>
                            </Border>

                            <!-- Card Desktop Geral -->
                            <Border Style="{StaticResource ProfileCard}">
                                <StackPanel>
                                    <TextBlock Text="🎮 Desktop - Geral &amp; Jogos" FontSize="15" FontWeight="Bold" Foreground="#9ECE6A" />
                                    <TextBlock Text="Foco em leveza extrema, menores latências de entrada (input lag) e mais FPS." FontSize="12" Foreground="#7982A9" Margin="0,3,0,6" TextWrapping="Wrap" />
                                    <TextBlock Text="• Máxima leveza (zero serviços pesados)&#x0a;• GameDVR e captura desativados&#x0a;• Resposta linear de mouse 1:1 e SSD calibrado" FontSize="11" Foreground="#C8D3F5" Margin="0,2,0,10" />
                                    <Button Name="btnPresetDesktopGeral" Content="Selecionar Perfil Jogos Desktop" Style="{StaticResource SecondaryButton}" Background="#16A34A" BorderBrush="#22C55E" Foreground="White" />
                                </StackPanel>
                            </Border>

                            <!-- Card Notebook Dev -->
                            <Border Style="{StaticResource ProfileCard}">
                                <StackPanel>
                                    <TextBlock Text="💻 Notebook - Dev &amp; Workstation" FontSize="15" FontWeight="Bold" Foreground="#BB9AF7" />
                                    <TextBlock Text="Ambiente de desenvolvimento móvel sem esgotar o SSD e a bateria." FontSize="12" Foreground="#7982A9" Margin="0,3,0,6" TextWrapping="Wrap" />
                                    <TextBlock Text="• Hibernação segura compacta (~3 GB)&#x0a;• Sem perda de trabalho ao fechar a tampa&#x0a;• Proteção térmica e driver GPU calibrado" FontSize="11" Foreground="#C8D3F5" Margin="0,2,0,10" />
                                    <Button Name="btnPresetLaptopDev" Content="Selecionar Perfil Dev Notebook" Style="{StaticResource SecondaryButton}" Background="#7C3AED" BorderBrush="#8B5CF6" Foreground="White" />
                                </StackPanel>
                            </Border>

                            <!-- Card Notebook Geral -->
                            <Border Style="{StaticResource ProfileCard}">
                                <StackPanel>
                                    <TextBlock Text="🔋 Notebook - Geral &amp; Autonomia" FontSize="15" FontWeight="Bold" Foreground="#E0AF68" />
                                    <TextBlock Text="Máxima duração de bateria no uso diário, fluidez e alta performance em jogos." FontSize="12" Foreground="#7982A9" Margin="0,3,0,6" TextWrapping="Wrap" />
                                    <TextBlock Text="• Máxima autonomia de bateria&#x0a;• Hibernação segura compacta&#x0a;• Zero telemetria consumindo energia" FontSize="11" Foreground="#C8D3F5" Margin="0,2,0,10" />
                                    <Button Name="btnPresetLaptopGeral" Content="Selecionar Perfil Geral Notebook" Style="{StaticResource SecondaryButton}" Background="#D97706" BorderBrush="#F59E0B" Foreground="White" />
                                </StackPanel>
                            </Border>
                        </UniformGrid>

                        <!-- Barra de Ferramentas de Selecao dos Tweaks -->
                        <Border Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="12" Margin="6,0,6,10">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>

                                <TextBlock Text="Customização Fina das Otimizações do Sistema:" FontSize="14" FontWeight="Bold" Foreground="#C8D3F5" VerticalAlignment="Center" />

                                <StackPanel Grid.Column="1" Orientation="Horizontal">
                                    <Button Name="btnSelectAll" Content="✓ Marcar Todos os Tweaks" Style="{StaticResource SecondaryButton}" Margin="0,0,6,0" />
                                    <Button Name="btnDeselectAll" Content="✗ Desmarcar Todos" Style="{StaticResource SecondaryButton}" Margin="0,0,6,0" />
                                    <Button Name="btnResetRecommended" Content="🔄 Restaurar Recomendados" Style="{StaticResource SecondaryButton}" />
                                </StackPanel>
                            </Grid>
                        </Border>

                        <!-- Grid de Tweaks por Categoria -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>

                            <!-- Coluna 1: Interface e Desempenho -->
                            <StackPanel Grid.Column="0">
                                <!-- Card Interface -->
                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="🖥️ Interface &amp; Barra de Tarefas" FontSize="14" FontWeight="Bold" Foreground="#7DCFFF" Margin="0,0,0,8" />
                                        <CheckBox Name="chkHideSearch" Content="Ocultar Caixa de Pesquisa na Barra" IsChecked="True" ToolTip="Remove o botão/caixa de busca; o Iniciar continua buscando ao digitar." />
                                        <CheckBox Name="chkHideTaskView" Content="Ocultar Botão Multitarefa (Task View)" IsChecked="True" ToolTip="Remove o ícone da barra; o atalho Win+Tab continua ativo." />
                                        <CheckBox Name="chkCenterTaskbar" Content="Barra de Tarefas Centralizada (Padrão Win 11)" IsChecked="True" ToolTip="Mantém o visual moderno centralizado do Windows 11." />
                                        <CheckBox Name="chkTaskbarEndTask" Content="Ativar 'Finalizar Tarefa' no Botão Direito" IsChecked="True" ToolTip="Permite fechar apps travados direto na barra de tarefas." />
                                        <CheckBox Name="chkClassicContextMenu" Content="Menu de Contexto Clássico (Windows 10)" IsChecked="True" ToolTip="Acesso direto a todas as opções sem submenus lentos." />
                                        <CheckBox Name="chkLaunchToThisPC" Content="Abrir Explorer em 'Este Computador'" IsChecked="True" ToolTip="Abre os discos locais e remove Início e Galeria pesados." />
                                        <CheckBox Name="chkShowExtensionsAndHidden" Content="Exibir Extensões e Arquivos Ocultos" IsChecked="True" ToolTip="Essencial para inspecionar .bat, .json, .ps1 e AppData." />
                                        <CheckBox Name="chkAlwaysShowScrollbars" Content="Barras de Rolagem Sempre Visíveis" IsChecked="True" ToolTip="Evita barras de rolagem sumindo automaticamente." />
                                    </StackPanel>
                                </Border>

                                <!-- Card Desempenho -->
                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="⚡ Desempenho, Latência &amp; SSD" FontSize="14" FontWeight="Bold" Foreground="#9ECE6A" Margin="0,0,0,8" />
                                        <CheckBox Name="chkOptimizeNetworkLatency" Content="Otimizar Latência de Rede (NetworkThrottling)" IsChecked="True" ToolTip="Desativa a limitação de tráfego de rede para menor ping e latência." />
                                        <CheckBox Name="chkDisableGameDVR" Content="Desativar GameDVR e Captura em Segundo Plano" IsChecked="True" ToolTip="Evita perda de FPS e uso de CPU em jogos gravando tela à toa." />
                                        <CheckBox Name="chkLinearMouse" Content="Resposta Linear do Mouse 1:1" IsChecked="True" ToolTip="Desativa aceleração artificial de ponteiro do Windows." />
                                        <CheckBox Name="chkDisableStickyKeys" Content="Desativar Popup Teclas de Aderência" IsChecked="True" ToolTip="Elimina o aviso irritante ao pressionar Shift repetidamente." />
                                        <CheckBox Name="chkInstantMenuDelay" Content="Eliminar Atraso de Menus (Instantâneo 0ms)" IsChecked="True" ToolTip="Remove o atraso de 400ms na abertura de submenus." />
                                        <CheckBox Name="chkOptimizeSsdAccess" Content="Otimizar Gravações SSD (DisableLastAccess)" IsChecked="True" ToolTip="Reduz gravações desnecessárias aumentando vida útil do SSD." />
                                        <CheckBox Name="chkCleanTempFiles" Content="Limpar Arquivos Temporários de Sistema" IsChecked="True" ToolTip="Esvazia caches e arquivos temp desnecessários." />
                                    </StackPanel>
                                </Border>
                            </StackPanel>

                            <!-- Coluna 2: Privacidade, Debloat e Sistema -->
                            <StackPanel Grid.Column="1">
                                <!-- Card Privacidade & Debloat -->
                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="🛡️ Privacidade, Telemetria &amp; Debloat" FontSize="14" FontWeight="Bold" Foreground="#BB9AF7" Margin="0,0,0,8" />
                                        <CheckBox Name="chkDisableTelemetry" Content="Desativar Telemetria &amp; Serviços de Diagnóstico" IsChecked="True" ToolTip="Desativa DiagTrack e coleta invasiva de dados." />
                                        <CheckBox Name="chkDisableCeipTasks" Content="Desativar Tarefas Agendadas Ociosas (CEIP)" IsChecked="True" ToolTip="Impede tarefas pesadas rodando quando o PC está ocioso." />
                                        <CheckBox Name="chkDisableCopilotRecall" Content="Desativar Copilot &amp; IA Recall" IsChecked="True" ToolTip="Elimina botões e análises de IA em segundo plano." />
                                        <CheckBox Name="chkDisableBingSearch" Content="Desativar Bing e Sugestões na Busca do Iniciar" IsChecked="True" ToolTip="Pesquisa local instantânea sem resultados lentos da web." />
                                        <CheckBox Name="chkDebloatEdge" Content="Debloat do Microsoft Edge (Mantém WebView2)" IsChecked="True" ToolTip="Remove telemetria, assistentes e cupons mantendo compatibilidade." />
                                        <CheckBox Name="chkRemoveUwpBloat" Content="Remover 28 Bloatwares UWP de Terceiros" IsChecked="True" ToolTip="Remove TikTok, Spotify, Jogos e feeds patrocinados." />
                                    </StackPanel>
                                </Border>

                                <!-- Card Sistema & Energia -->
                                <Border Style="{StaticResource ProfileCard}">
                                    <StackPanel>
                                        <TextBlock Text="⚙️ Sistema, GPU &amp; Energia" FontSize="14" FontWeight="Bold" Foreground="#E0AF68" Margin="0,0,0,8" />
                                        <CheckBox Name="chkCalibrateGpu" Content="Calibração de GPU (TdrDelay = 8s + HAGS)" IsChecked="True" ToolTip="Evita quedas de driver de vídeo em cargas pesadas." />
                                        <CheckBox Name="chkSmartHibernation" Content="Hibernação Inteligente (Off Desktop / Compacta Laptop)" IsChecked="True" ToolTip="Recupera até 32 GB de SSD em desktops; mantém sono seguro em notebooks." />
                                        <CheckBox Name="chkDisableReservedStorage" Content="Desativar Armazenamento Reservado (~7 GB)" IsChecked="True" ToolTip="Libera espaço em disco bloqueado pelo Windows." />
                                        <CheckBox Name="chkOptimizeSvcHost" Content="Calibrar Memória de Serviços (SvcHost)" IsChecked="True" ToolTip="Ajusta limite de memória por processo de acordo com a RAM." />
                                        <CheckBox Name="chkEnableLongPaths" Content="Habilitar Caminhos Longos no Sistema de Arquivos" IsChecked="True" ToolTip="Remove o limite de 260 caracteres em caminhos de arquivos." />
                                        <CheckBox Name="chkDisableLockScreen" Content="Pular Tela de Bloqueio Estática" IsChecked="True" ToolTip="Vai direto para o campo de senha/PIN ao ligar o PC." />
                                        <CheckBox Name="chkIsDev" Content="Configurações Dev (Relógio UTC, RDP e Boot Detalhado)" IsChecked="False" ToolTip="Otimizações adicionais para programadores e dual-boot Linux." />
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </Grid>

                        <!-- Botao Independente de Aplicacao das Otimizacoes -->
                        <Border Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,10,6,6">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>

                                <TextBlock Text="💡 As otimizações são aplicadas cirurgicamente e o Windows Explorer é reiniciado de forma suave." FontSize="12" Foreground="#7982A9" VerticalAlignment="Center" />

                                <Button Name="btnApplyOptimizations" Grid.Column="1" Content="⚡ APLICAR OTIMIZAÇÕES SELECIONADAS" Background="#16A34A" BorderBrush="#22C55E" Foreground="White" FontWeight="Bold" FontSize="13" Padding="20,10" Cursor="Hand">
                                    <Button.Resources>
                                        <Style TargetType="Border">
                                            <Setter Property="CornerRadius" Value="8" />
                                        </Style>
                                    </Button.Resources>
                                </Button>
                            </Grid>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ======================================================== -->
            <!-- ABA 3: RECURSOS DO WINDOWS (DISM)                       -->
            <!-- ======================================================== -->
            <TabItem Name="tabItemFeatures" Header=" 🧩 Recursos do Windows ">
                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="10">
                    <StackPanel>
                        <Border Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,0,6,10">
                            <TextBlock Text="Recursos opcionais do Windows gerenciados nativamente via DISM:" FontSize="15" FontWeight="SemiBold" Foreground="#C8D3F5" />
                        </Border>
                        
                        <Border Style="{StaticResource ProfileCard}">
                            <StackPanel>
                                <TextBlock Text="⚙️ Recursos de Compatibilidade e Virtualização" FontSize="14" FontWeight="Bold" Foreground="#7DCFFF" Margin="0,0,0,8" />
                                <CheckBox Name="featNetFx3" Content=".NET Framework 3.5 (.NET 2.0 e 3.0 para softwares legados)" IsChecked="True" />
                                <CheckBox Name="featWsl" Content="Subsistema do Windows para Linux (WSL2)" IsChecked="False" />
                                <CheckBox Name="featVmPlatform" Content="Plataforma de Máquina Virtual (Pré-requisito do WSL2)" IsChecked="False" />
                                <CheckBox Name="featHyperV" Content="Hyper-V (Virtualização Nativa para VMs e Docker)" IsChecked="False" />
                                <CheckBox Name="featSandbox" Content="Windows Sandbox (Área Restrita Segura e Descartável)" IsChecked="False" />
                            </StackPanel>
                        </Border>

                        <!-- Botao Independente de Recursos DISM -->
                        <Border Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="14" Margin="6,10,6,6">
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>

                                <TextBlock Text="💡 Requer conexão com a internet para baixar arquivos de componentes adicionais da Microsoft." FontSize="12" Foreground="#7982A9" VerticalAlignment="Center" />

                                <Button Name="btnEnableFeatures" Grid.Column="1" Content="⚙️ HABILITAR RECURSOS SELECIONADOS" Background="#7C3AED" BorderBrush="#8B5CF6" Foreground="White" FontWeight="Bold" FontSize="13" Padding="20,10" Cursor="Hand">
                                    <Button.Resources>
                                        <Style TargetType="Border">
                                            <Setter Property="CornerRadius" Value="8" />
                                        </Style>
                                    </Button.Resources>
                                </Button>
                            </Grid>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </TabItem>

            <!-- ======================================================== -->
            <!-- ABA 4: LOG & AUDITORIA EM TEMPO REAL                     -->
            <!-- ======================================================== -->
            <TabItem Name="tabItemLog" Header=" 📜 Registro &amp; Log ">
                <Grid Margin="10">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="*" />
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBlock Text="Acompanhamento em tempo real da execução e auditoria:" FontSize="13" Foreground="#7982A9" VerticalAlignment="Center" />
                        <Button Name="btnOpenLogFolder" Content="📁 Abrir Pasta de Logs" Style="{StaticResource SecondaryButton}" Margin="12,0,0,0" Padding="8,3" FontSize="11" />
                        <Button Name="btnClearLogConsole" Content="🧹 Limpar Console" Style="{StaticResource SecondaryButton}" Margin="8,0,0,0" Padding="8,3" FontSize="11" />
                    </StackPanel>

                    <Border Grid.Row="1" Background="#0A0B10" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="8" Padding="8">
                        <TextBox Name="txtConsoleLog" Background="Transparent" Foreground="#9ECE6A" FontFamily="Consolas, Cascadia Code, Courier New" FontSize="12" IsReadOnly="True" BorderThickness="0" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Text="DEWIN Booster pronto. Selecione programas ou otimizações para começar." />
                    </Border>
                </Grid>
            </TabItem>

        </TabControl>

        <!-- 3. RODAPE GLOBAL DE STATUS & PROGRESSO -->
        <Border Grid.Row="2" Background="#1A1B26" BorderBrush="#2F354F" BorderThickness="1" CornerRadius="10" Padding="14,10" Margin="0,12,0,0">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto" />
                    <RowDefinition Height="Auto" />
                </Grid.RowDefinitions>

                <!-- Barra de Progresso e Status -->
                <Grid Grid.Row="0" Margin="0,0,0,8">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*" />
                        <ColumnDefinition Width="Auto" />
                    </Grid.ColumnDefinitions>
                    <TextBlock Name="lblProgressStatus" Text="Pronto. Escolha uma ação nas abas acima." FontSize="13" FontWeight="SemiBold" Foreground="#C8D3F5" VerticalAlignment="Center" />
                    <TextBlock Name="lblProgressPercent" Grid.Column="1" Text="0%" FontSize="13" FontWeight="Bold" Foreground="#7DCFFF" VerticalAlignment="Center" />
                </Grid>
                
                <ProgressBar Name="pbExecution" Grid.Row="1" Height="10" Minimum="0" Maximum="100" Background="#24283B" Foreground="#7DCFFF" BorderThickness="0" Value="0" />
            </Grid>
        </Border>

    </Grid>
</Window>

'@

# ==============================================================================
# DEWIN Entrypoint Principal
# ==============================================================================
try {
    Initialize-DewinLogging

    $hw = Get-DewinHardwareInfo

    if ($Profile -ne 'GUI' -or $Silent) {
        # Execucao em Modo Linha de Comando (Headless / Silencioso)
        $chosenPreset = if ($Profile -eq 'GUI') { $hw.RecommendedProfile } else { $Profile }
        Write-Host "Iniciando DEWIN Booster em modo CLI com perfil: $chosenPreset" -ForegroundColor Cyan
        $presetData = Get-DewinPreset -Name $chosenPreset
        Invoke-DewinExecution -Tweaks $presetData.Tweaks -Apps $presetData.Apps -Features $presetData.Features -Hardware $hw
        if (-not $NoRestart) {
            $r = Read-Host "Deseja reiniciar o computador agora? (S/N)"
            if ($r -match '^[sSyY]') { Restart-Computer }
        }
    } else {
        # Execucao em Modo Interface Grafica (WPF)
        Start-DewinGui -XamlString $global:DewinXaml -Hardware $hw
    }
} catch {
    Write-Host ""
    Write-Host "[!] Erro fatal durante a execucao do DEWIN:" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host ""
    Write-Host "Pressione Enter para fechar..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
    exit 1
}
