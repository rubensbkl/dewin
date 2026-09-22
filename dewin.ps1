# ==============================================================================
# DEWIN Booster - Universal Windows Optimizer & Debloater (Single-Script Edition)
# Execução via terminal:
# irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral', 'GUI')]
    [string]$Profile = 'GUI',
    [switch]$Silent,
    [switch]$NoRestart
)

# 0. Auto-correção de codificação para execução direta via powershell.exe -File
if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    if ('ç'.Length -ne 1) {
        $scriptBytes = [System.IO.File]::ReadAllBytes($PSCommandPath)
        $scriptText = [System.Text.Encoding]::UTF8.GetString($scriptBytes)
        $scriptBlock = [ScriptBlock]::Create($scriptText)
        $boundParams = $PSBoundParameters
        & $scriptBlock @boundParams
        return
    }
}

# 1. Codificação UTF-8 para Console
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# 2. Auto-Elevação Administrativa (UAC)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[*] Privilégios de Administrador necessários. Elevando via UAC...' -ForegroundColor Cyan
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
        Write-Host ' [!] PRIVILÉGIOS DE ADMINISTRADOR NECESSÁRIOS' -ForegroundColor Yellow
        Write-Host ' O DEWIN precisa ser executado em um terminal com privilégios de Administrador.' -ForegroundColor Yellow
        Write-Host ' Clique com o botão direito no Iniciar -> Terminal (Administrador)' -ForegroundColor Cyan
        Write-Host ' e execute novamente:' -ForegroundColor Cyan
        Write-Host ' irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex' -ForegroundColor White
        Write-Host '==================================================================' -ForegroundColor Yellow
        exit 1
    }
}

# --- Módulo: src\core\Logger.ps1 ---
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


# --- Módulo: src\core\Registry.ps1 ---
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


# --- Módulo: src\core\Hardware.ps1 ---
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


# --- Módulo: src\tweaks\InterfaceTweaks.ps1 ---
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


# --- Módulo: src\tweaks\PerformanceTweaks.ps1 ---
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


# --- Módulo: src\tweaks\PrivacyTweaks.ps1 ---
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

    Write-DewinLog -Level SUCCESS -Message "  [+] Limpeza de $removedCount bloatwares concluída."
}


# --- Módulo: src\tweaks\SystemTweaks.ps1 ---
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
            Write-DewinLog -Level STEP -Message '  [*] Configurando hibernação segura compacta para Notebook...'
            try {
                powercfg.exe /hibernate on 2>$null | Out-Null
                powercfg.exe /h /type reduced 2>$null | Out-Null
            } catch {}
        } else {
            Write-DewinLog -Level STEP -Message '  [*] Desativando hibernação para Desktop (recuperando espaço em disco SSD)...'
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

    Write-DewinLog -Level SUCCESS -Message '  [+] Calibrações de sistema, GPU e energia aplicadas com sucesso.'
}


# --- Módulo: src\packages\SoftwareInstaller.ps1 ---
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
            $pct = 90 + [int](($current / $total) * 7)
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


# --- Módulo: src\packages\WindowsFeatures.ps1 ---
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
            Write-DewinLog -Level WARN -Message "  [!] Não foi possível habilitar ${feat}: $($_.Exception.Message)"
        }
    }
}


# --- Módulo: src\engine\Presets.ps1 ---
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
            'DesktopDev'   { 'Desktop - Desenvolvimento: WSL2, Hyper-V, Sandbox, ferramentas essenciais, sem hibernação (liberação de espaço em SSD).' }
            'DesktopGeral' { 'Desktop - Geral e Jogos: Otimização de desempenho, menor latência de rede e entrada, espaço em SSD liberado, sem virtualização ativa.' }
            'LaptopDev'    { 'Notebook - Desenvolvimento: WSL2, Hyper-V, Sandbox, ferramentas essenciais, hibernação compacta com preservação de energia.' }
            'LaptopGeral'  { 'Notebook - Geral e Autonomia: Eficiência energética aprimorada, maior autonomia de bateria, sem virtualização ativa, hibernação compacta.' }
        }
    }
}


# --- Módulo: src\engine\Runner.ps1 ---
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
                            -DisableLockScreen:([bool]$Tweaks['DisableLockScreen'])

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

    # 6. Reiniciar Explorer
    & $updateProgress 95 "Reiniciando o Windows Explorer..."
    Restart-DewinExplorer

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


# --- Módulo: src\engine\Controller.ps1 ---
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
        "Notebook identificado. Perfil recomendado: 'Notebook - Desenvolvimento' (para desenvolvedores) ou 'Notebook - Geral e Autonomia' (para máxima duração de bateria e jogos)."
    } else {
        "Desktop identificado. Perfil recomendado: 'Desktop - Desenvolvimento' (para desenvolvedores) ou 'Desktop - Geral e Jogos' (para máxima taxa de FPS e menor latência)."
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

        $gui['btnInstallSoftwares'].Content = "Instalando programas..."

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
            $gui['btnInstallSoftwares'].Content = "Instalar Programas Selecionados"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "Falha na instalação de programas: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro ao instalar os programas selecionados:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Programas instalados e atualizados com sucesso."
                [System.Windows.MessageBox]::Show(
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
            $gui['btnApplyOptimizations'].Content = "Aplicar Otimizações Selecionadas"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "Falha na aplicação de otimizações: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro durante as otimizações:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Otimizações aplicadas com sucesso."
                $res = [System.Windows.MessageBox]::Show(
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
                "Nenhum recurso opcional foi selecionado.`r`nPor favor, marque ao menos um recurso do Windows.",
                "DEWIN Booster - Selecione Recursos",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnEnableFeatures'].Content = "Habilitando recursos..."

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
            $gui['btnEnableFeatures'].Content = "Habilitar Recursos Selecionados"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "Falha na habilitação de recursos DISM: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro ao configurar os recursos:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Recursos opcionais habilitados com sucesso."
                [System.Windows.MessageBox]::Show(
                    "Recursos opcionais habilitados com sucesso via DISM.",
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


# --- Interface Gráfica XAML ---
$global:DewinXaml = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(@'
PFdpbmRvdyB4bWxucz0iaHR0cDovL3NjaGVtYXMubWljcm9zb2Z0LmNvbS93aW5meC8yMDA2L3hhbWwvcHJlc2VudGF0aW9uIgogICAgICAgIHhtbG5zOng9Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vd2luZngvMjAwNi94YW1sIgogICAgICAgIFRpdGxlPSJERVdJTiBCb29zdGVyIC0gT3RpbWl6YWRvciBlIEdlcmVuY2lhZG9yIGRvIFdpbmRvd3MiCiAgICAgICAgSGVpZ2h0PSI4MDAiIFdpZHRoPSIxMTAwIiBNaW5IZWlnaHQ9IjcwMCIgTWluV2lkdGg9Ijk4MCIKICAgICAgICBXaW5kb3dTdGFydHVwTG9jYXRpb249IkNlbnRlclNjcmVlbiIKICAgICAgICBCYWNrZ3JvdW5kPSIjMEYxMTFBIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IgogICAgICAgIEZvbnRGYW1pbHk9IlNlZ29lIFVJLCBTZWdvZSBVSSBWYXJpYWJsZSwgQXJpYWwiPgoKICAgIDxXaW5kb3cuUmVzb3VyY2VzPgogICAgICAgIDwhLS0gUGFsZXRhIGRlIENvcmVzIE1vZGVybmEgKERFV0lOIERhcmsgVGhlbWUpIC0tPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJnRGFyayIgQ29sb3I9IiMwRjExMUEiIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQmdDYXJkIiBDb2xvcj0iIzFBMUIyNiIgLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJCZ0NhcmRBbHQiIENvbG9yPSIjMjQyODNCIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJvcmRlckNhcmQiIENvbG9yPSIjMkYzNTRGIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlByaW1hcnlDeWFuIiBDb2xvcj0iIzdEQ0ZGRiIgLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJQcmltYXJ5Qmx1ZSIgQ29sb3I9IiM3QUEyRjciIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQWNjZW50R3JlZW4iIENvbG9yPSIjOUVDRTZBIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkFjY2VudFllbGxvdyIgQ29sb3I9IiNFMEFGNjgiIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iVGV4dFByaW1hcnkiIENvbG9yPSIjQzhEM0Y1IiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlRleHRNdXRlZCIgQ29sb3I9IiM3OTgyQTkiIC8+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBDaGVja0JveGVzIE1vZGVybm9zIC0tPgogICAgICAgIDxTdHlsZSBUYXJnZXRUeXBlPSJDaGVja0JveCI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvcmVncm91bmQiIFZhbHVlPSIjQzhEM0Y1IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250U2l6ZSIgVmFsdWU9IjEzIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJNYXJnaW4iIFZhbHVlPSIwLDUsMCw1IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJDdXJzb3IiIFZhbHVlPSJIYW5kIiAvPgogICAgICAgIDwvU3R5bGU+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBCb3RvZXMgU2VjdW5kYXJpb3MgLS0+CiAgICAgICAgPFN0eWxlIHg6S2V5PSJTZWNvbmRhcnlCdXR0b24iIFRhcmdldFR5cGU9IkJ1dHRvbiI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJhY2tncm91bmQiIFZhbHVlPSIjMjQyODNCIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb3JlZ3JvdW5kIiBWYWx1ZT0iI0M4RDNGNSIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyQnJ1c2giIFZhbHVlPSIjNDE0ODY4IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCb3JkZXJUaGlja25lc3MiIFZhbHVlPSIxIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJQYWRkaW5nIiBWYWx1ZT0iMTIsNiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ3Vyc29yIiBWYWx1ZT0iSGFuZCIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9udFdlaWdodCIgVmFsdWU9IlNlbWlCb2xkIiAvPgogICAgICAgIDwvU3R5bGU+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBDYXJkcyBkZSBQZXJmaWwgZSBBZ3J1cGFtZW50b3MgLS0+CiAgICAgICAgPFN0eWxlIHg6S2V5PSJQcm9maWxlQ2FyZCIgVGFyZ2V0VHlwZT0iQm9yZGVyIj4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQmFja2dyb3VuZCIgVmFsdWU9IiMxQTFCMjYiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlckJydXNoIiBWYWx1ZT0iIzJGMzU0RiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyVGhpY2tuZXNzIiBWYWx1ZT0iMSIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iMTAiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlBhZGRpbmciIFZhbHVlPSIxNiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iTWFyZ2luIiBWYWx1ZT0iNiIgLz4KICAgICAgICA8L1N0eWxlPgoKICAgICAgICA8IS0tIEVzdGlsbyBNb2Rlcm5vIGRhIEJhcnJhIGRlIFByb2dyZXNzbyAtLT4KICAgICAgICA8U3R5bGUgVGFyZ2V0VHlwZT0iUHJvZ3Jlc3NCYXIiPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCYWNrZ3JvdW5kIiBWYWx1ZT0iIzI0MjgzQiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgVmFsdWU9IiM3RENGRkYiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlclRoaWNrbmVzcyIgVmFsdWU9IjAiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlRlbXBsYXRlIj4KICAgICAgICAgICAgICAgIDxTZXR0ZXIuVmFsdWU+CiAgICAgICAgICAgICAgICAgICAgPENvbnRyb2xUZW1wbGF0ZSBUYXJnZXRUeXBlPSJQcm9ncmVzc0JhciI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0ie1RlbXBsYXRlQmluZGluZyBCYWNrZ3JvdW5kfSIgQ29ybmVyUmFkaXVzPSI1IiBDbGlwVG9Cb3VuZHM9IlRydWUiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQgTmFtZT0iUEFSVF9UcmFjayI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBOYW1lPSJQQVJUX0luZGljYXRvciIgQmFja2dyb3VuZD0ie1RlbXBsYXRlQmluZGluZyBGb3JlZ3JvdW5kfSIgSG9yaXpvbnRhbEFsaWdubWVudD0iTGVmdCIgQ29ybmVyUmFkaXVzPSI1IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICA8L0NvbnRyb2xUZW1wbGF0ZT4KICAgICAgICAgICAgICAgIDwvU2V0dGVyLlZhbHVlPgogICAgICAgICAgICA8L1NldHRlcj4KICAgICAgICA8L1N0eWxlPgogICAgPC9XaW5kb3cuUmVzb3VyY2VzPgoKICAgIDxHcmlkIE1hcmdpbj0iMTYiPgogICAgICAgIDxHcmlkLlJvd0RlZmluaXRpb25zPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iIC8+IDwhLS0gQ2FiZWNhbGhvIGUgQmFubmVyIGRlIEhhcmR3YXJlIC0tPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IioiIC8+ICAgIDwhLS0gQXJlYSBQcmluY2lwYWwgY29tIEFiYXMgLS0+CiAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4gPCEtLSBSb2RhcGUgZGUgU3RhdHVzIGUgUHJvZ3Jlc3NvIC0tPgogICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KCiAgICAgICAgPCEtLSAxLiBDQUJFQ0FMSE8gJiBCQU5ORVIgREUgSEFSRFdBUkUgLS0+CiAgICAgICAgPEJvcmRlciBHcmlkLlJvdz0iMCIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSIxMCIgUGFkZGluZz0iMTYiIE1hcmdpbj0iMCwwLDAsMTIiPgogICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIwIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iREVXSU4gQk9PU1RFUiIgRm9udFNpemU9IjIwIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0RDRkZGIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMyNDI4M0IiIENvcm5lclJhZGl1cz0iNSIgUGFkZGluZz0iNiwyIiBNYXJnaW49IjEwLDAsMCwwIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iTmF0aXZvIGUgZGUgQ8OzZGlnbyBBYmVydG8iIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgRm9udFdlaWdodD0iU2VtaUJvbGQiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIE5hbWU9InR4dEhhcmR3YXJlQmFubmVyIiBUZXh0PSJEZXRlY3RhbmRvIGNvbXBvbmVudGVzIGRlIGhhcmR3YXJlLi4uIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCw1LDAsMCIgLz4KICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KCiAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSIgT3JpZW50YXRpb249Ikhvcml6b250YWwiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzI0MjgzQiIgQm9yZGVyQnJ1c2g9IiM0MTQ4NjgiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxMCw2IiBNYXJnaW49IjQsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0idHh0RGV2aWNlVHlwZSIgVGV4dD0iRGV0ZWN0YW5kby4uLiIgRm9udFNpemU9IjEyIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0FBMkY3IiAvPgogICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgIDwhLS0gMi4gQUJBUyBQUklOQ0lQQUlTIC0tPgogICAgICAgIDxUYWJDb250cm9sIE5hbWU9Im1haW5UYWJDb250cm9sIiBHcmlkLlJvdz0iMSIgQmFja2dyb3VuZD0iIzEzMTQxRiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiPgogICAgICAgICAgICAKICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPCEtLSBBQkEgMTogUFJPR1JBTUFTICYgQVBMSUNBVElWT1MgKFRFTEEgSU5JQ0lBTCkgICAgICAgICAgICAtLT4KICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gTmFtZT0idGFiSXRlbVNvZnR3YXJlcyIgSGVhZGVyPSIgUHJvZ3JhbWFzIGUgQXBsaWNhdGl2b3MgIj4KICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIiBNYXJnaW49IjEwIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYWJlY2FsaG8gZSBBY29lcyBSYXBpZGFzIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMxQTFCMjYiIEJvcmRlckJydXNoPSIjMkYzNTRGIiBCb3JkZXJUaGlja25lc3M9IjEiIENvcm5lclJhZGl1cz0iOCIgUGFkZGluZz0iMTQiIE1hcmdpbj0iNiwwLDYsMTAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjAiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9Ikluc3RhbGHDp8OjbyBlIEF0dWFsaXphw6fDo28gZGUgU29mdHdhcmVzIHZpYSBXaW5nZXQiIEZvbnRTaXplPSIxNiIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJTZWxlY2lvbmUgb3MgcHJvZ3JhbWFzIHF1ZSBkZXNlamEgaW5zdGFsYXIgc2lsZW5jaW9zYW1lbnRlIG5vIGNvbXB1dGFkb3I6IiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIxIiBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuU2VsZWN0RXNzZW50aWFsQXBwcyIgQ29udGVudD0iRXNzZW5jaWFpcyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBNYXJnaW49IjAsMCw2LDAiIFRvb2xUaXA9IlNlbGVjaW9uYSBWaXN1YWwgQysrLCA3LVppcCBlIEdvb2dsZSBDaHJvbWUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuU2VsZWN0QWxsQXBwcyIgQ29udGVudD0iTWFyY2FyIFRvZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iMCwwLDYsMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5EZXNlbGVjdEFsbEFwcHMiIENvbnRlbnQ9IkRlc21hcmNhciBUb2RvcyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhdGFsb2dvIGRlIFNvZnR3YXJlcyBlbSBHcmlkIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDE6IFJ1bnRpbWVzIGUgTmF2ZWdhZG9yZXMgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJSdW50aW1lcyBlIFV0aWxpdMOhcmlvcyBFc3NlbmNpYWlzIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3RENGRkYiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBWY1JlZGlzdDY0IiBDb250ZW50PSJWaXN1YWwgQysrIDIwMTUtMjAyMiAoeDY0KSAtIFByw6ktcmVxdWlzaXRvIHBhcmEgam9nb3MgZSBwcm9ncmFtYXMiIElzQ2hlY2tlZD0iVHJ1ZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBWY1JlZGlzdDg2IiBDb250ZW50PSJWaXN1YWwgQysrIDIwMTUtMjAyMiAoeDg2KSAtIENvbXBhdGliaWxpZGFkZSBkZSBhcGxpY2F0aXZvcyAzMi1iaXQiIElzQ2hlY2tlZD0iVHJ1ZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHA3emlwIiBDb250ZW50PSI3LVppcCAtIENvbXBhY3RhZG9yIGUgZGVzY29tcGFjdGFkb3IgZGUgYWx0YSBwZXJmb3JtYW5jZSIgSXNDaGVja2VkPSJUcnVlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iTmF2ZWdhZG9yZXMgV2ViIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM5RUNFNkEiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBDaHJvbWUiIENvbnRlbnQ9Ikdvb2dsZSBDaHJvbWUgLSBOYXZlZ2Fkb3Igd2ViIG1vZGVybm8gZSBzZWd1cm8iIElzQ2hlY2tlZD0iVHJ1ZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDI6IERlc2Vudm9sdmltZW50byBlIE11bHRpbWlkaWEvSm9nb3MgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJGZXJyYW1lbnRhcyBkZSBEZXNlbnZvbHZpbWVudG8iIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0JCOUFGNyIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcFZzQ29kZSIgQ29udGVudD0iVmlzdWFsIFN0dWRpbyBDb2RlIC0gRWRpdG9yIGRlIGPDs2RpZ28gZGEgTWljcm9zb2Z0IiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcEdpdCIgQ29udGVudD0iR2l0IGZvciBXaW5kb3dzIC0gU2lzdGVtYSBkaXN0cmlidcOtZG8gZGUgY29udHJvbGUgZGUgdmVyc8OjbyIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkNvbXVuaWNhw6fDo28sIE3DrWRpYSBlIEpvZ29zIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNFMEFGNjgiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBEaXNjb3JkIiBDb250ZW50PSJEaXNjb3JkIC0gQ29tdW5pY2HDp8OjbyBwb3Igdm96LCB2w61kZW8gZSB0ZXh0byIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBTdGVhbSIgQ29udGVudD0iU3RlYW0gLSBQbGF0YWZvcm1hIGRlIGpvZ29zIGUgY29tdW5pZGFkZSBkaWdpdGFsIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcFZsYyIgQ29udGVudD0iVkxDIE1lZGlhIFBsYXllciAtIFJlcHJvZHV0b3IgZGUgw6F1ZGlvIGUgdsOtZGVvIHVuaXZlcnNhbCIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBTcG90aWZ5IiBDb250ZW50PSJTcG90aWZ5IC0gU3RyZWFtaW5nIGRlIG3DunNpY2EgZSBwb2RjYXN0cyIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIEJvdGFvIEluZGVwZW5kZW50ZSBkZSBJbnN0YWxhY2FvIGRlIFNvZnR3YXJlcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjE0IiBNYXJnaW49IjYsMTAsNiw2Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkEgaW5zdGFsYcOnw6NvIMOpIHJlYWxpemFkYSBlbSBzZWd1bmRvIHBsYW5vIHZpYSBXaW5nZXQgb2ZpY2lhbCwgc2VtIGludGVycm9tcGVyIGFzIGF0aXZpZGFkZXMgZW0gZXhlY3XDp8Ojby4iIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkluc3RhbGxTb2Z0d2FyZXMiIEdyaWQuQ29sdW1uPSIxIiBDb250ZW50PSJJbnN0YWxhciBQcm9ncmFtYXMgU2VsZWNpb25hZG9zIiBCYWNrZ3JvdW5kPSIjMjU2M0VCIiBCb3JkZXJCcnVzaD0iIzNCODJGNiIgRm9yZWdyb3VuZD0iV2hpdGUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvbnRTaXplPSIxMyIgUGFkZGluZz0iMjAsMTAiIEN1cnNvcj0iSGFuZCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24uUmVzb3VyY2VzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0eWxlIFRhcmdldFR5cGU9IkJvcmRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3R5bGU+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgPC9TY3JvbGxWaWV3ZXI+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDwhLS0gQUJBIDI6IE9USU1JWkFDT0VTIERPIFNJU1RFTUEgRSBQRVJGSVMgICAgICAgICAgICAgICAgICAgLS0+CiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDxUYWJJdGVtIE5hbWU9InRhYkl0ZW1Ud2Vha3MiIEhlYWRlcj0iIE90aW1pemHDp8O1ZXMgZG8gU2lzdGVtYSAiPgogICAgICAgICAgICAgICAgPFNjcm9sbFZpZXdlciBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIE1hcmdpbj0iMTAiPgogICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIE5vdGlmaWNhY2FvIGRlIFJlY29tZW5kYWNhbyBkZSBIYXJkd2FyZSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUMyNzM4IiBCb3JkZXJCcnVzaD0iIzI1NjNFQiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjEyIiBNYXJnaW49IjYsMCw2LDEwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0idHh0UmVjb21tZW5kYXRpb24iIFRleHQ9IkNhbGN1bGFuZG8gbWVsaG9yIHBlcmZpbCBwYXJhIHN1YSBtw6FxdWluYS4uLiIgRm9udFNpemU9IjEzIiBGb3JlZ3JvdW5kPSIjOTNDNUZEIiBUZXh0V3JhcHBpbmc9IldyYXAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBTZcOnw6NvIGRvcyA0IFBlcmZpcyBSw6FwaWRvcyBkZSAxIENsaXF1ZSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJQZXJmaXMgUmVjb21lbmRhZG9zIGRlIENvbmZpZ3VyYcOnw6NvOiIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJTZW1pQm9sZCIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSI4LDQsOCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8VW5pZm9ybUdyaWQgQ29sdW1ucz0iMiIgTWFyZ2luPSIwLDAsMCwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgRGVza3RvcCBEZXYgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJEZXNrdG9wIC0gRGVzZW52b2x2aW1lbnRvIiBGb250U2l6ZT0iMTUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3RENGRkYiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iT3RpbWl6YWRvIHBhcmEgY29tcGlsYcOnw6NvLCBjb250w6ppbmVyZXMgZSByZXNwb3N0YSDDoWdpbCBkZSBwcm9jZXNzYW1lbnRvLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBNYXJnaW49IjAsMywwLDYiIFRleHRXcmFwcGluZz0iV3JhcCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSLigKIgU2VtIGhpYmVybmHDp8OjbyAocmVjdXBlcmEgZXNwYcOnbyBlbSBkaXNjbyBTU0QgaWd1YWwgw6AgUkFNKSYjeDBhO+KAoiBNZW5vciBsYXTDqm5jaWEgZGUgcmVkZSBlIHNlbSBsaW1pdGHDp8OjbyBkZSBwcm9jZXNzYWRvciYjeDBhO+KAoiBUZWxlbWV0cmlhIGRlc2F0aXZhZGEgZSBFeHBsb3JhZG9yIGRlIEFycXVpdm9zIGxpbXBvIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0RGVza3RvcERldiIgQ29udGVudD0iU2VsZWNpb25hciBQZXJmaWwgRGVza3RvcCBEZXNlbnZvbHZpbWVudG8iIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzI1NjNFQiIgQm9yZGVyQnJ1c2g9IiMzQjgyRjYiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBEZXNrdG9wIEdlcmFsIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iRGVza3RvcCAtIEdlcmFsIGUgSm9nb3MiIEZvbnRTaXplPSIxNSIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJGb2NvIGVtIHRheGEgZGUgcXVhZHJvcyAoRlBTKSwgbWVub3IgbGF0w6puY2lhIGRlIGVudHJhZGEgZSBtw6F4aW1hIHJlc3BvbnNpdmlkYWRlLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBNYXJnaW49IjAsMywwLDYiIFRleHRXcmFwcGluZz0iV3JhcCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSLigKIgU2VydmnDp29zIHNlY3VuZMOhcmlvcyBkZXNuZWNlc3PDoXJpb3MgZGVzYXRpdmFkb3MmI3gwYTvigKIgR2FtZURWUiBlIGNhcHR1cmEgZGUgdGVsYSBkZXNhdGl2YWRvcyYjeDBhO+KAoiBSZXNwb3N0YSBkZSBtb3VzZSBsaW5lYXIgMToxIGUgZ3JhdmHDp8OjbyBTU0QgY2FsaWJyYWRhIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0RGVza3RvcEdlcmFsIiBDb250ZW50PSJTZWxlY2lvbmFyIFBlcmZpbCBEZXNrdG9wIEdlcmFsIGUgSm9nb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzE2QTM0QSIgQm9yZGVyQnJ1c2g9IiMyMkM1NUUiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBOb3RlYm9vayBEZXYgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJOb3RlYm9vayAtIERlc2Vudm9sdmltZW50byIgRm9udFNpemU9IjE1IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjQkI5QUY3IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkFtYmllbnRlIGRlIGRlc2Vudm9sdmltZW50byBtw7N2ZWwgY29tIHByZXNlcnZhw6fDo28gZGUgYmF0ZXJpYSBlIGFybWF6ZW5hbWVudG8uIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsNiIgVGV4dFdyYXBwaW5nPSJXcmFwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IuKAoiBIaWJlcm5hw6fDo28gc2VndXJhIGNvbXBhY3RhIGNvbSBwcmVzZXJ2YcOnw6NvIGRlIGVzdGFkbyYjeDBhO+KAoiBQcmV2ZW7Dp8OjbyBjb250cmEgcGVyZGEgZGUgZGFkb3MgYW8gZmVjaGFyIGEgdGFtcGEmI3gwYTvigKIgQ2FsaWJyYcOnw6NvIGRlIHJlc3Bvc3RhIHTDqXJtaWNhIGUgZXN0YWJpbGlkYWRlIGdyw6FmaWNhIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0TGFwdG9wRGV2IiBDb250ZW50PSJTZWxlY2lvbmFyIFBlcmZpbCBOb3RlYm9vayBEZXNlbnZvbHZpbWVudG8iIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzdDM0FFRCIgQm9yZGVyQnJ1c2g9IiM4QjVDRjYiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBOb3RlYm9vayBHZXJhbCAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9Ik5vdGVib29rIC0gR2VyYWwgZSBBdXRvbm9taWEiIEZvbnRTaXplPSIxNSIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0UwQUY2OCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJNw6F4aW1hIGVmaWNpw6puY2lhIGVuZXJnw6l0aWNhIG5vIHVzbyBkacOhcmlvLCBmbHVpZGV6IGUgZXN0YWJpbGlkYWRlIGVtIGpvZ29zLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBNYXJnaW49IjAsMywwLDYiIFRleHRXcmFwcGluZz0iV3JhcCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSLigKIgT3RpbWl6YcOnw6NvIHBhcmEgbWFpb3IgYXV0b25vbWlhIGRhIGJhdGVyaWEmI3gwYTvigKIgSGliZXJuYcOnw6NvIGNvbXBhY3RhIGNvbSBiYWl4byBjb25zdW1vIGVtIHJlcG91c28mI3gwYTvigKIgRWxpbWluYcOnw6NvIGRlIHJvdGluYXMgZW0gc2VndW5kbyBwbGFubyBxdWUgY29uc29tZW0gZW5lcmdpYSIgRm9udFNpemU9IjExIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IiBNYXJnaW49IjAsMiwwLDEwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0blByZXNldExhcHRvcEdlcmFsIiBDb250ZW50PSJTZWxlY2lvbmFyIFBlcmZpbCBOb3RlYm9vayBHZXJhbCBlIEF1dG9ub21pYSIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBCYWNrZ3JvdW5kPSIjRDk3NzA2IiBCb3JkZXJCcnVzaD0iI0Y1OUUwQiIgRm9yZWdyb3VuZD0iV2hpdGUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvVW5pZm9ybUdyaWQ+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIEJhcnJhIGRlIEZlcnJhbWVudGFzIGRlIFNlbGVjYW8gZG9zIFR3ZWFrcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjEyIiBNYXJnaW49IjYsMCw2LDEwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlNlbGXDp8OjbyBQZXJzb25hbGl6YWRhIGRlIE90aW1pemHDp8O1ZXM6IiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNDOEQzRjUiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIxIiBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuU2VsZWN0QWxsIiBDb250ZW50PSJNYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSIwLDAsNiwwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkRlc2VsZWN0QWxsIiBDb250ZW50PSJEZXNtYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSIwLDAsNiwwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0blJlc2V0UmVjb21tZW5kZWQiIENvbnRlbnQ9IlJlc3RhdXJhciBSZWNvbWVuZGFkb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBHcmlkIGRlIFR3ZWFrcyBwb3IgQ2F0ZWdvcmlhIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDE6IEludGVyZmFjZSBlIERlc2VtcGVuaG8gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIEludGVyZmFjZSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkludGVyZmFjZSBlIEJhcnJhIGRlIFRhcmVmYXMiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0hpZGVTZWFyY2giIENvbnRlbnQ9Ik9jdWx0YXIgY2FpeGEgZGUgcGVzcXVpc2EgbmEgYmFycmEgZGUgdGFyZWZhcyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJPY3VsdGEgYSBiYXJyYSBkZSBwZXNxdWlzYTsgYSBidXNjYSBkbyBtZW51IEluaWNpYXIgcGVybWFuZWNlIGRpc3BvbsOtdmVsIGFvIGRpZ2l0YXIuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0hpZGVUYXNrVmlldyIgQ29udGVudD0iT2N1bHRhciBib3TDo28gZGUgVmlzw6NvIGRlIFRhcmVmYXMgKFRhc2sgVmlldykiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iT2N1bHRhIG8gw61jb25lIGRhIGJhcnJhOyBvIGF0YWxobyBXaW4rVGFiIHBlcm1hbmVjZSB0b3RhbG1lbnRlIGZ1bmNpb25hbC4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrQ2VudGVyVGFza2JhciIgQ29udGVudD0iQWxpbmhhbWVudG8gY2VudHJhbGl6YWRvIGRhIGJhcnJhIGRlIHRhcmVmYXMiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iTWFudMOpbSBhIGJhcnJhIGRlIHRhcmVmYXMgY2VudHJhbGl6YWRhIG5vIHBhZHLDo28gbW9kZXJubyBkbyBXaW5kb3dzIDExLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtUYXNrYmFyRW5kVGFzayIgQ29udGVudD0iQXRpdmFyIG9ww6fDo28gJ0ZpbmFsaXphciBUYXJlZmEnIG5vIGJvdMOjbyBkaXJlaXRvIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IlBlcm1pdGUgZW5jZXJyYXIgcHJvY2Vzc29zIG7Do28gcmVzcG9uc2l2b3MgZGlyZXRhbWVudGUgcGVsbyBib3TDo28gZGlyZWl0byBuYSBiYXJyYSBkZSB0YXJlZmFzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtDbGFzc2ljQ29udGV4dE1lbnUiIENvbnRlbnQ9Ik1lbnUgZGUgY29udGV4dG8gY2zDoXNzaWNvIChlc3RpbG8gV2luZG93cyAxMCkiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRXhpYmUgdG9kYXMgYXMgb3DDp8O1ZXMgZG8gbWVudSBkZSBjb250ZXh0byBkaXJldGFtZW50ZSwgc2VtIHN1Ym1lbnVzIGFkaWNpb25haXMuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0xhdW5jaFRvVGhpc1BDIiBDb250ZW50PSJBYnJpciBFeHBsb3JhZG9yIGRlIEFycXVpdm9zIGVtICdFc3RlIENvbXB1dGFkb3InIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkNvbmZpZ3VyYSBvIEV4cGxvcmFkb3IgZGUgQXJxdWl2b3MgcGFyYSBpbmljaWFyIG5hcyB1bmlkYWRlcyBkZSBkaXNjbywgcmVtb3ZlbmRvIHDDoWdpbmFzIGxlbnRhcyBkZSBJbsOtY2lvIGUgR2FsZXJpYS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrU2hvd0V4dGVuc2lvbnNBbmRIaWRkZW4iIENvbnRlbnQ9IkV4aWJpciBleHRlbnPDtWVzIGUgYXJxdWl2b3Mgb2N1bHRvcyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJGYWNpbGl0YSBhIHZpc3VhbGl6YcOnw6NvIGRlIGV4dGVuc8O1ZXMgZGUgYXJxdWl2b3MgKC5iYXQsIC5wczEsIC5qc29uKSBlIHBhc3RhcyBkZSBjb25maWd1cmHDp8Ojby4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrQWx3YXlzU2hvd1Njcm9sbGJhcnMiIENvbnRlbnQ9Ik1hbnRlciBiYXJyYXMgZGUgcm9sYWdlbSBzZW1wcmUgdmlzw612ZWlzIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkV2aXRhIHF1ZSBhcyBiYXJyYXMgZGUgcm9sYWdlbSBzZWphbSBvY3VsdGFkYXMgYXV0b21hdGljYW1lbnRlIHBlbGEgaW50ZXJmYWNlLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhcmQgRGVzZW1wZW5obyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkRlc2VtcGVuaG8sIExhdMOqbmNpYSBlIEFybWF6ZW5hbWVudG8iIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa09wdGltaXplTmV0d29ya0xhdGVuY3kiIENvbnRlbnQ9Ik90aW1pemFyIGxhdMOqbmNpYSBkZSByZWRlIChOZXR3b3JrVGhyb3R0bGluZykiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRGVzYXRpdmEgYSBsaW1pdGHDp8OjbyBkZSByZWRlIGRvIFdpbmRvd3MgcGFyYSBtZW5vciBsYXTDqm5jaWEgZW0gY29uZXjDtWVzIGUgam9nb3MuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVHYW1lRFZSIiBDb250ZW50PSJEZXNhdGl2YXIgR2FtZURWUiBlIGNhcHR1cmEgZW0gc2VndW5kbyBwbGFubyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJFbGltaW5hIHNvYnJlY2FyZ2EgZGUgcHJvY2Vzc2Fkb3IgZSBwbGFjYSBkZSB2w61kZW8gZ2VyYWRhIHBvciBncmF2YcOnw7VlcyBhdXRvbcOhdGljYXMgZGUgdGVsYS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrTGluZWFyTW91c2UiIENvbnRlbnQ9IlJlc3Bvc3RhIGxpbmVhciBkbyBwb250ZWlybyBkbyBtb3VzZSAoUHJlY2lzw6NvIDE6MSkiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRGVzYXRpdmEgYSBhY2VsZXJhw6fDo28gYXJ0aWZpY2lhbCBkbyBwb250ZWlybyBwYXJhIGNvbnNpc3TDqm5jaWEgZGUgbW92aW1lbnRvLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlU3RpY2t5S2V5cyIgQ29udGVudD0iRGVzYXRpdmFyIGF0YWxobyBkZSBUZWNsYXMgZGUgQWRlcsOqbmNpYSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJJbXBlZGUgYSBleGliacOnw6NvIGRvIGRpw6Fsb2dvIGRlIGNvbmZpcm1hw6fDo28gYW8gcHJlc3Npb25hciBhIHRlY2xhIFNoaWZ0IGNvbnNlY3V0aXZhbWVudGUuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0luc3RhbnRNZW51RGVsYXkiIENvbnRlbnQ9IlJlbW92ZXIgYXRyYXNvIG5hIGFiZXJ0dXJhIGRlIG1lbnVzICgwIG1zKSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJSZWR1eiBvIHRlbXBvIGRlIGVzcGVyYSBuYSBhYmVydHVyYSBkZSBzdWJtZW51cyBzdXNwZW5zb3MgcGFyYSByZXNwb3N0YSBpbWVkaWF0YS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrT3B0aW1pemVTc2RBY2Nlc3MiIENvbnRlbnQ9Ik90aW1pemFyIGdyYXZhw6fDtWVzIGVtIFNTRCAoRGlzYWJsZUxhc3RBY2Nlc3MpIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIGEgZ3JhdmHDp8OjbyBjb250w61udWEgZGUgZGF0YSBkZSDDumx0aW1vIGFjZXNzbywgcmVkdXppbmRvIGVzY3JpdGFzIGUgcHJlc2VydmFuZG8gbyBTU0QuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0NsZWFuVGVtcEZpbGVzIiBDb250ZW50PSJMaW1wYXIgYXJxdWl2b3MgdGVtcG9yw6FyaW9zIGRvIHNpc3RlbWEiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRXN2YXppYSBjYWNoZXMgZSBhcnF1aXZvcyB0ZW1wb3LDoXJpb3MgbsOjbyB1dGlsaXphZG9zIHBlbG8gc2lzdGVtYSBvcGVyYWNpb25hbC4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENvbHVuYSAyOiBQcml2YWNpZGFkZSwgRGVibG9hdCBlIFNpc3RlbWEgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIFByaXZhY2lkYWRlICYgRGVibG9hdCAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlByaXZhY2lkYWRlLCBUZWxlbWV0cmlhIGUgQXBsaWNhdGl2b3MgUGFkcsOjbyIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjQkI5QUY3IiBNYXJnaW49IjAsMCwwLDgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZVRlbGVtZXRyeSIgQ29udGVudD0iRGVzYXRpdmFyIHRlbGVtZXRyaWEgZSBzZXJ2acOnb3MgZGUgZGlhZ27Ds3N0aWNvIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIG8gc2VydmnDp28gRGlhZ1RyYWNrIGUgbyBlbnZpbyBkZSBkYWRvcyBkaWFnbsOzc3RpY29zIHBhcmEgc2Vydmlkb3JlcyBleHRlcm5vcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZUNlaXBUYXNrcyIgQ29udGVudD0iRGVzYXRpdmFyIHRhcmVmYXMgYWdlbmRhZGFzIGRlIGRpYWduw7NzdGljbyAoQ0VJUCkiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRGVzYXRpdmEgcm90aW5hcyBhZ2VuZGFkYXMgZGUgdGVsZW1ldHJpYSBleGVjdXRhZGFzIGR1cmFudGUgcGVyw61vZG9zIGRlIG9jaW9zaWRhZGUuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVDb3BpbG90UmVjYWxsIiBDb250ZW50PSJEZXNhdGl2YXIgV2luZG93cyBDb3BpbG90IGUgcmVjdXJzb3MgZGUgSUEgUmVjYWxsIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIG8gYXNzaXN0ZW50ZSBDb3BpbG90IGUgcm90aW5hcyBkZSBhbsOhbGlzZSBjb250w61udWEgZGUgdGVsYSBlbSBzZWd1bmRvIHBsYW5vLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlQmluZ1NlYXJjaCIgQ29udGVudD0iRGVzYXRpdmFyIHJlc3VsdGFkb3MgZG8gQmluZyBubyBtZW51IEluaWNpYXIiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iTWFudMOpbSBhIGJ1c2NhIGRvIG1lbnUgSW5pY2lhciBlc3RyaXRhbWVudGUgbG9jYWwgcGFyYSByZXNwb3N0YXMgaW1lZGlhdGFzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEZWJsb2F0RWRnZSIgQ29udGVudD0iT3RpbWl6YXIgdGVsZW1ldHJpYSBkbyBNaWNyb3NvZnQgRWRnZSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJEZXNhdGl2YSBvIGVudmlvIGRlIG3DqXRyaWNhcyBkZSBuYXZlZ2HDp8OjbyBlIGFzc2lzdGVudGVzIGRlIGNvbXByYSwgcHJlc2VydmFuZG8gbyBXZWJWaWV3Mi4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrUmVtb3ZlVXdwQmxvYXQiIENvbnRlbnQ9IlJlbW92ZXIgYXBsaWNhdGl2b3MgcHLDqS1pbnN0YWxhZG9zIGRlc25lY2Vzc8OhcmlvcyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJSZW1vdmUgcGFjb3RlcyBwcm9tb2Npb25haXMgcHLDqS1pbnN0YWxhZG9zIGRlIGVudHJldGVuaW1lbnRvIGUgcmVkZXMgc29jaWFpcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIFNpc3RlbWEgJiBFbmVyZ2lhIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iU2lzdGVtYSwgR3LDoWZpY29zIGUgR2VyZW5jaWFtZW50byBkZSBFbmVyZ2lhIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNFMEFGNjgiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtDYWxpYnJhdGVHcHUiIENvbnRlbnQ9IkNhbGlicmFyIHRvbGVyw6JuY2lhIGRlIGRyaXZlciBncsOhZmljbyAoVGRyRGVsYXkgZSBIQUdTKSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJBdW1lbnRhIGEgdG9sZXLDom5jaWEgcGFyYSByZWN1cGVyYcOnw6NvIGRvIGRyaXZlciBncsOhZmljbyBlIGF0aXZhIG8gYWdlbmRhbWVudG8gZGUgR1BVIHBvciBoYXJkd2FyZS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrU21hcnRIaWJlcm5hdGlvbiIgQ29udGVudD0iR2VyZW5jaWFtZW50byBpbnRlbGlnZW50ZSBkZSBoaWJlcm5hw6fDo28iIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRGVzYXRpdmEgYSBoaWJlcm5hw6fDo28gZW0gY29tcHV0YWRvcmVzIGRlIG1lc2EgcGFyYSByZWN1cGVyYXIgZXNwYcOnbyBlbSBkaXNjbyBTU0Qgb3UgY29uZmlndXJhIG1vZG8gY29tcGFjdG8gZW0gbm90ZWJvb2tzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlUmVzZXJ2ZWRTdG9yYWdlIiBDb250ZW50PSJEZXNhdGl2YXIgQXJtYXplbmFtZW50byBSZXNlcnZhZG8gZG8gV2luZG93cyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJMaWJlcmEgYXByb3hpbWFkYW1lbnRlIDcgR0IgZGUgZXNwYcOnbyBlbSBkaXNjbyBhbnRlcmlvcm1lbnRlIHJldGlkb3MgcGVsbyBzaXN0ZW1hIG9wZXJhY2lvbmFsLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtPcHRpbWl6ZVN2Y0hvc3QiIENvbnRlbnQ9IkNhbGlicmFyIGRpdmlzw6NvIGRlIHByb2Nlc3NvcyBkZSBzZXJ2acOnb3MgKFN2Y0hvc3QpIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkFqdXN0YSBvIGlzb2xhbWVudG8gZGUgc2VydmnDp29zIGRlIGFjb3JkbyBjb20gYSBxdWFudGlkYWRlIHRvdGFsIGRlIG1lbcOzcmlhIFJBTS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRW5hYmxlTG9uZ1BhdGhzIiBDb250ZW50PSJIYWJpbGl0YXIgc3Vwb3J0ZSBhIGNhbWluaG9zIGxvbmdvcyBkZSBhcnF1aXZvcyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJSZW1vdmUgYSBsaW1pdGHDp8OjbyBsZWdhZGEgZGUgMjYwIGNhcmFjdGVyZXMgKE1BWF9QQVRIKSBlbSBjYW1pbmhvcyBkZSBhcnF1aXZvcyBlIHBhc3Rhcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZUxvY2tTY3JlZW4iIENvbnRlbnQ9IlB1bGFyIHRlbGEgZGUgYmxvcXVlaW8gZXN0w6F0aWNhIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkFwcmVzZW50YSBvIGNhbXBvIGRlIGF1dGVudGljYcOnw6NvIGRpcmV0YW1lbnRlIGFvIGxpZ2FyIG91IGRlc2Jsb3F1ZWFyIG8gY29tcHV0YWRvci4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrSXNEZXYiIENvbnRlbnQ9IkNvbmZpZ3VyYcOnw7VlcyBwYXJhIGRlc2Vudm9sdmVkb3JlcyAoUmVsw7NnaW8gVVRDIGUgRGlhZ27Ds3N0aWNvcykiIElzQ2hlY2tlZD0iRmFsc2UiIFRvb2xUaXA9IkNvbmZpZ3VyYSBvIHJlbMOzZ2lvIGRhIHBsYWNhLW3Do2UgZW0gVVRDIHBhcmEgc2luY3Jvbml6YcOnw6NvIGNvbSBMaW51eCBlIGhhYmlsaXRhIG1lbnNhZ2VucyBkZXRhbGhhZGFzIGRlIGJvb3QuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KCiAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQm90YW8gSW5kZXBlbmRlbnRlIGRlIEFwbGljYWNhbyBkYXMgT3RpbWl6YWNvZXMgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCIgTWFyZ2luPSI2LDEwLDYsNiI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJBcyBjb25maWd1cmHDp8O1ZXMgc8OjbyBhcGxpY2FkYXMgbm8gUmVnaXN0cm8gZSBub3Mgc2VydmnDp29zIGRvIHNpc3RlbWEgY29tIHJlaW5pY2lhbGl6YcOnw6NvIGxpbXBhIGRvIEV4cGxvcmFkb3IgZGUgQXJxdWl2b3MuIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuQXBwbHlPcHRpbWl6YXRpb25zIiBHcmlkLkNvbHVtbj0iMSIgQ29udGVudD0iQXBsaWNhciBPdGltaXphw6fDtWVzIFNlbGVjaW9uYWRhcyIgQmFja2dyb3VuZD0iIzE2QTM0QSIgQm9yZGVyQnJ1c2g9IiMyMkM1NUUiIEZvcmVncm91bmQ9IldoaXRlIiBGb250V2VpZ2h0PSJCb2xkIiBGb250U2l6ZT0iMTMiIFBhZGRpbmc9IjIwLDEwIiBDdXJzb3I9IkhhbmQiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdHlsZSBUYXJnZXRUeXBlPSJCb3JkZXIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkNvcm5lclJhZGl1cyIgVmFsdWU9IjgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0eWxlPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbi5SZXNvdXJjZXM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9CdXR0b24+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgIDwvU2Nyb2xsVmlld2VyPgogICAgICAgICAgICA8L1RhYkl0ZW0+CgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8IS0tIEFCQSAzOiBSRUNVUlNPUyBPUENJT05BSVMgRE8gV0lORE9XUyAoRElTTSkgICAgICAgICAgICAgIC0tPgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8VGFiSXRlbSBOYW1lPSJ0YWJJdGVtRmVhdHVyZXMiIEhlYWRlcj0iIFJlY3Vyc29zIE9wY2lvbmFpcyBkbyBXaW5kb3dzICI+CiAgICAgICAgICAgICAgICA8U2Nyb2xsVmlld2VyIFZlcnRpY2FsU2Nyb2xsQmFyVmlzaWJpbGl0eT0iQXV0byIgTWFyZ2luPSIxMCI+CiAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCIgTWFyZ2luPSI2LDAsNiwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlJlY3Vyc29zIG9wY2lvbmFpcyBkbyBXaW5kb3dzIGdlcmVuY2lhZG9zIG5hdGl2YW1lbnRlIHZpYSBESVNNOiIgRm9udFNpemU9IjE1IiBGb250V2VpZ2h0PSJTZW1pQm9sZCIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iQ29tcG9uZW50ZXMgZSBSZWN1cnNvcyBkbyBTaXN0ZW1hIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3RENGRkYiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iZmVhdE5ldEZ4MyIgQ29udGVudD0iLk5FVCBGcmFtZXdvcmsgMy41IChDb21wYXRpYmlsaWRhZGUgbGVnYWRhIGNvbSB2ZXJzw7VlcyAyLjAgZSAzLjApIiBJc0NoZWNrZWQ9IlRydWUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImZlYXRXc2wiIENvbnRlbnQ9IlN1YnNpc3RlbWEgZG8gV2luZG93cyBwYXJhIExpbnV4IChXU0wyKSIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iZmVhdFZtUGxhdGZvcm0iIENvbnRlbnQ9IlBsYXRhZm9ybWEgZGUgTcOhcXVpbmEgVmlydHVhbCAoUHLDqS1yZXF1aXNpdG8gZG8gV1NMMikiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImZlYXRIeXBlclYiIENvbnRlbnQ9Ikh5cGVyLVYgKFZpcnR1YWxpemHDp8OjbyBuYXRpdmEgcGFyYSBtw6FxdWluYXMgdmlydHVhaXMgZSBEb2NrZXIpIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJmZWF0U2FuZGJveCIgQ29udGVudD0iV2luZG93cyBTYW5kYm94IChBbWJpZW50ZSBpc29sYWRvIHBhcmEgdGVzdGVzIHNlZ3Vyb3MpIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQm90YW8gSW5kZXBlbmRlbnRlIGRlIFJlY3Vyc29zIERJU00gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCIgTWFyZ2luPSI2LDEwLDYsNiI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJSZXF1ZXIgY29uZXjDo28gY29tIGEgaW50ZXJuZXQgcGFyYSBiYWl4YXIgYXJxdWl2b3MgZGUgY29tcG9uZW50ZXMgYWRpY2lvbmFpcyBkYSBNaWNyb3NvZnQuIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuRW5hYmxlRmVhdHVyZXMiIEdyaWQuQ29sdW1uPSIxIiBDb250ZW50PSJIYWJpbGl0YXIgUmVjdXJzb3MgU2VsZWNpb25hZG9zIiBCYWNrZ3JvdW5kPSIjN0MzQUVEIiBCb3JkZXJCcnVzaD0iIzhCNUNGNiIgRm9yZWdyb3VuZD0iV2hpdGUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvbnRTaXplPSIxMyIgUGFkZGluZz0iMjAsMTAiIEN1cnNvcj0iSGFuZCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24uUmVzb3VyY2VzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0eWxlIFRhcmdldFR5cGU9IkJvcmRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3R5bGU+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgPC9TY3JvbGxWaWV3ZXI+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDwhLS0gQUJBIDQ6IFJFR0lTVFJPIEUgTE9HUyBFTSBURU1QTyBSRUFMICAgICAgICAgICAgICAgICAgICAgLS0+CiAgICAgICAgICAgIDwhLS0gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0gLS0+CiAgICAgICAgICAgIDxUYWJJdGVtIE5hbWU9InRhYkl0ZW1Mb2ciIEhlYWRlcj0iIFJlZ2lzdHJvIGUgTG9ncyAiPgogICAgICAgICAgICAgICAgPEdyaWQgTWFyZ2luPSIxMCI+CiAgICAgICAgICAgICAgICAgICAgPEdyaWQuUm93RGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSIqIiAvPgogICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Sb3c9IjAiIE9yaWVudGF0aW9uPSJIb3Jpem9udGFsIiBNYXJnaW49IjAsMCwwLDgiPgogICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkFjb21wYW5oYW1lbnRvIGVtIHRlbXBvIHJlYWwgZGEgZXhlY3XDp8OjbyBlIGF1ZGl0b3JpYSBkZSBzaXN0ZW1hOiIgRm9udFNpemU9IjEzIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bk9wZW5Mb2dGb2xkZXIiIENvbnRlbnQ9IkFicmlyIFBhc3RhIGRlIExvZ3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSIxMiwwLDAsMCIgUGFkZGluZz0iOCwzIiBGb250U2l6ZT0iMTEiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuQ2xlYXJMb2dDb25zb2xlIiBDb250ZW50PSJMaW1wYXIgQ29uc29sZSIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBNYXJnaW49IjgsMCwwLDAiIFBhZGRpbmc9IjgsMyIgRm9udFNpemU9IjExIiAvPgogICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KCiAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBHcmlkLlJvdz0iMSIgQmFja2dyb3VuZD0iIzBBMEIxMCIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSI4Ij4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCb3ggTmFtZT0idHh0Q29uc29sZUxvZyIgQmFja2dyb3VuZD0iVHJhbnNwYXJlbnQiIEZvcmVncm91bmQ9IiM5RUNFNkEiIEZvbnRGYW1pbHk9IkNvbnNvbGFzLCBDYXNjYWRpYSBDb2RlLCBDb3VyaWVyIE5ldyIgRm9udFNpemU9IjEyIiBJc1JlYWRPbmx5PSJUcnVlIiBCb3JkZXJUaGlja25lc3M9IjAiIFRleHRXcmFwcGluZz0iV3JhcCIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIiBUZXh0PSJERVdJTiBCb29zdGVyIHByb250by4gU2VsZWNpb25lIHByb2dyYW1hcyBvdSBvdGltaXphw6fDtWVzIHBhcmEgY29tZcOnYXIuIiAvPgogICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICA8L1RhYkl0ZW0+CgogICAgICAgIDwvVGFiQ29udHJvbD4KCiAgICAgICAgPCEtLSAzLiBST0RBUEUgR0xPQkFMIERFIFNUQVRVUyAmIFBST0dSRVNTTyAtLT4KICAgICAgICA8Qm9yZGVyIEdyaWQuUm93PSIyIiBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjEwIiBQYWRkaW5nPSIxNCwxMCIgTWFyZ2luPSIwLDEyLDAsMCI+CiAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgPEdyaWQuUm93RGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4KICAgICAgICAgICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICA8IS0tIEJhcnJhIGRlIFByb2dyZXNzbyBlIFN0YXR1cyAtLT4KICAgICAgICAgICAgICAgIDxHcmlkIEdyaWQuUm93PSIwIiBNYXJnaW49IjAsMCwwLDgiPgogICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0ibGJsUHJvZ3Jlc3NTdGF0dXMiIFRleHQ9IlByb250by4gU2VsZWNpb25lIGFzIGNvbmZpZ3VyYcOnw7VlcyBkZXNlamFkYXMgbmFzIGFiYXMgYWNpbWEuIiBGb250U2l6ZT0iMTMiIEZvbnRXZWlnaHQ9IlNlbWlCb2xkIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgogICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0ibGJsUHJvZ3Jlc3NQZXJjZW50IiBHcmlkLkNvbHVtbj0iMSIgVGV4dD0iMCUiIEZvbnRTaXplPSIxMyIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgLz4KICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgPFByb2dyZXNzQmFyIE5hbWU9InBiRXhlY3V0aW9uIiBHcmlkLlJvdz0iMSIgSGVpZ2h0PSIxMCIgTWluaW11bT0iMCIgTWF4aW11bT0iMTAwIiBCYWNrZ3JvdW5kPSIjMjQyODNCIiBGb3JlZ3JvdW5kPSIjN0RDRkZGIiBCb3JkZXJUaGlja25lc3M9IjAiIFZhbHVlPSIwIiAvPgogICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgPC9Cb3JkZXI+CgogICAgPC9HcmlkPgo8L1dpbmRvdz4K
'@))

# ==============================================================================
# DEWIN Entrypoint Principal
# ==============================================================================
try {
    Initialize-DewinLogging

    $hw = Get-DewinHardwareInfo

    if ($Profile -ne 'GUI' -or $Silent) {
        # Execução em Modo Linha de Comando (Headless / Silencioso)
        $chosenPreset = if ($Profile -eq 'GUI') { $hw.RecommendedProfile } else { $Profile }
        Write-Host "Iniciando DEWIN Booster em modo CLI com perfil: $chosenPreset" -ForegroundColor Cyan
        $presetData = Get-DewinPreset -Name $chosenPreset
        Invoke-DewinExecution -Tweaks $presetData.Tweaks -Apps $presetData.Apps -Features $presetData.Features -Hardware $hw
        if (-not $NoRestart) {
            $r = Read-Host "Deseja reiniciar o computador agora? (S/N)"
            if ($r -match '^[sSyY]') { Restart-Computer }
        }
    } else {
        # Execução em Modo Interface Gráfica (WPF)
        Start-DewinGui -XamlString $global:DewinXaml -Hardware $hw
    }
} catch {
    Write-Host ""
    Write-Host "[!] Erro fatal durante a execução do DEWIN:" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host ""
    Write-Host "Pressione Enter para fechar..." -ForegroundColor Yellow
    [void][System.Console]::ReadLine()
    exit 1
}
