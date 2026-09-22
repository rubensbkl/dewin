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

        $gui['lblProgressStatus'].Text = "Perfil de otimização '$($preset.Level)' aplicado na aba de configurações."
    }

    $applyFeaturePresetToGui = {
        param([string]$ProfileName)
        $featPreset = Get-DewinFeaturePreset -Profile $ProfileName

        foreach ($k in $featMap.Keys) {
            if ($gui[$k]) {
                $gui[$k].IsChecked = ($featPreset.Features -contains $featMap[$k])
            }
        }

        $gui['lblProgressStatus'].Text = "Perfil de recursos '$($featPreset.Profile)' aplicado na aba de extras."
    }

    # 4. Vinculação dos Botões de Níveis Rápidos (Aba 2: Otimizações)
    $gui['btnPresetTweakLight'].Add_Click({ & $applyTweakPresetToGui 'Light' })
    $gui['btnPresetTweakMedium'].Add_Click({ & $applyTweakPresetToGui 'Medium' })
    $gui['btnPresetTweakAggressive'].Add_Click({ & $applyTweakPresetToGui 'Aggressive' })

    # Botões de Seleção de Tweaks (Aba 2)
    $gui['btnSelectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
    })
    $gui['btnDeselectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    })
    $gui['btnResetRecommended'].Add_Click({
        & $applyTweakPresetToGui 'Medium'
    })

    # Botões de Perfis Rápidos e Seleção de Recursos (Aba 3: Extras / DISM)
    $gui['btnPresetFeatGeneral'].Add_Click({ & $applyFeaturePresetToGui 'General' })
    $gui['btnPresetFeatDev'].Add_Click({ & $applyFeaturePresetToGui 'Dev' })
    $gui['btnSelectAllFeat'].Add_Click({
        foreach ($c in $allFeatChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
    })
    $gui['btnDeselectAllFeat'].Add_Click({
        foreach ($c in $allFeatChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    })

    # Botões de Seleção de Softwares (Aba 1: Aplicativos - 100% Manual)
    $gui['btnSelectEssentialApps'].Add_Click({
        $essentialIds = @('appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome')
        foreach ($c in $allAppChecks) {
            if ($gui[$c]) { $gui[$c].IsChecked = ($essentialIds -contains $c) }
        }
        $gui['lblProgressStatus'].Text = "Softwares essenciais (VC++, 7-Zip, Chrome) selecionados manualmente."
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

    # Inicialização da interface:
    # 1. Aplicativos iniciam todos desmarcados
    foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    # 2. Otimizações iniciam com perfil Médio (Recomendado)
    & $applyTweakPresetToGui 'Medium'
    # 3. Recursos opcionais iniciam com perfil Geral (.NET 3.5 apenas)
    & $applyFeaturePresetToGui 'General'

    # 5. Executador Assíncrono com UI Responsiva (Thread-Safe)
    $allActionButtons = @(
        'btnInstallSoftwares', 'btnApplyOptimizations', 'btnEnableFeatures',
        'btnSelectEssentialApps', 'btnSelectAllApps', 'btnDeselectAllApps',
        'btnSelectAll', 'btnDeselectAll', 'btnResetRecommended',
        'btnPresetTweakLight', 'btnPresetTweakMedium', 'btnPresetTweakAggressive',
        'btnPresetFeatGeneral', 'btnPresetFeatDev', 'btnSelectAllFeat', 'btnDeselectAllFeat'
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


# --- Interface GrÃ¡fica XAML ---
$global:DewinXaml = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(@'
PFdpbmRvdyB4bWxucz0iaHR0cDovL3NjaGVtYXMubWljcm9zb2Z0LmNvbS93aW5meC8yMDA2L3hhbWwvcHJlc2VudGF0aW9uIgogICAgICAgIHhtbG5zOng9Imh0dHA6Ly9zY2hlbWFzLm1pY3Jvc29mdC5jb20vd2luZngvMjAwNi94YW1sIgogICAgICAgIFRpdGxlPSJERVdJTiBCb29zdGVyIC0gT3RpbWl6YWRvciBlIEdlcmVuY2lhZG9yIGRvIFdpbmRvd3MiCiAgICAgICAgSGVpZ2h0PSI4MDAiIFdpZHRoPSIxMTAwIiBNaW5IZWlnaHQ9IjcwMCIgTWluV2lkdGg9Ijk4MCIKICAgICAgICBXaW5kb3dTdGFydHVwTG9jYXRpb249IkNlbnRlclNjcmVlbiIKICAgICAgICBCYWNrZ3JvdW5kPSIjMEYxMTFBIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IgogICAgICAgIEZvbnRGYW1pbHk9IlNlZ29lIFVJLCBTZWdvZSBVSSBWYXJpYWJsZSwgQXJpYWwiPgoKICAgIDxXaW5kb3cuUmVzb3VyY2VzPgogICAgICAgIDwhLS0gUGFsZXRhIGRlIENvcmVzIE1vZGVybmEgKERFV0lOIERhcmsgVGhlbWUpIC0tPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJnRGFyayIgQ29sb3I9IiMwRjExMUEiIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQmdDYXJkIiBDb2xvcj0iIzFBMUIyNiIgLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJCZ0NhcmRBbHQiIENvbG9yPSIjMjQyODNCIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkJvcmRlckNhcmQiIENvbG9yPSIjMkYzNTRGIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlByaW1hcnlDeWFuIiBDb2xvcj0iIzdEQ0ZGRiIgLz4KICAgICAgICA8U29saWRDb2xvckJydXNoIHg6S2V5PSJQcmltYXJ5Qmx1ZSIgQ29sb3I9IiM3QUEyRjciIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iQWNjZW50R3JlZW4iIENvbG9yPSIjOUVDRTZBIiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IkFjY2VudFllbGxvdyIgQ29sb3I9IiNFMEFGNjgiIC8+CiAgICAgICAgPFNvbGlkQ29sb3JCcnVzaCB4OktleT0iVGV4dFByaW1hcnkiIENvbG9yPSIjQzhEM0Y1IiAvPgogICAgICAgIDxTb2xpZENvbG9yQnJ1c2ggeDpLZXk9IlRleHRNdXRlZCIgQ29sb3I9IiM3OTgyQTkiIC8+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBDaGVja0JveGVzIE1vZGVybm9zIC0tPgogICAgICAgIDxTdHlsZSBUYXJnZXRUeXBlPSJDaGVja0JveCI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkZvcmVncm91bmQiIFZhbHVlPSIjQzhEM0Y1IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb250U2l6ZSIgVmFsdWU9IjEzIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJNYXJnaW4iIFZhbHVlPSIwLDUsMCw1IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJDdXJzb3IiIFZhbHVlPSJIYW5kIiAvPgogICAgICAgIDwvU3R5bGU+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBCb3RvZXMgU2VjdW5kYXJpb3MgLS0+CiAgICAgICAgPFN0eWxlIHg6S2V5PSJTZWNvbmRhcnlCdXR0b24iIFRhcmdldFR5cGU9IkJ1dHRvbiI+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJhY2tncm91bmQiIFZhbHVlPSIjMjQyODNCIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJGb3JlZ3JvdW5kIiBWYWx1ZT0iI0M4RDNGNSIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyQnJ1c2giIFZhbHVlPSIjNDE0ODY4IiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCb3JkZXJUaGlja25lc3MiIFZhbHVlPSIxIiAvPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJQYWRkaW5nIiBWYWx1ZT0iMTIsNiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ3Vyc29yIiBWYWx1ZT0iSGFuZCIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9udFdlaWdodCIgVmFsdWU9IlNlbWlCb2xkIiAvPgogICAgICAgIDwvU3R5bGU+CgogICAgICAgIDwhLS0gRXN0aWxvIGRvcyBDYXJkcyBkZSBQZXJmaWwgZSBBZ3J1cGFtZW50b3MgLS0+CiAgICAgICAgPFN0eWxlIHg6S2V5PSJQcm9maWxlQ2FyZCIgVGFyZ2V0VHlwZT0iQm9yZGVyIj4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQmFja2dyb3VuZCIgVmFsdWU9IiMxQTFCMjYiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlckJydXNoIiBWYWx1ZT0iIzJGMzU0RiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQm9yZGVyVGhpY2tuZXNzIiBWYWx1ZT0iMSIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iQ29ybmVyUmFkaXVzIiBWYWx1ZT0iMTAiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlBhZGRpbmciIFZhbHVlPSIxNiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iTWFyZ2luIiBWYWx1ZT0iNiIgLz4KICAgICAgICA8L1N0eWxlPgoKICAgICAgICA8IS0tIEVzdGlsbyBNb2Rlcm5vIGRhIEJhcnJhIGRlIFByb2dyZXNzbyAtLT4KICAgICAgICA8U3R5bGUgVGFyZ2V0VHlwZT0iUHJvZ3Jlc3NCYXIiPgogICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJCYWNrZ3JvdW5kIiBWYWx1ZT0iIzI0MjgzQiIgLz4KICAgICAgICAgICAgPFNldHRlciBQcm9wZXJ0eT0iRm9yZWdyb3VuZCIgVmFsdWU9IiM3RENGRkYiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkJvcmRlclRoaWNrbmVzcyIgVmFsdWU9IjAiIC8+CiAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IlRlbXBsYXRlIj4KICAgICAgICAgICAgICAgIDxTZXR0ZXIuVmFsdWU+CiAgICAgICAgICAgICAgICAgICAgPENvbnRyb2xUZW1wbGF0ZSBUYXJnZXRUeXBlPSJQcm9ncmVzc0JhciI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0ie1RlbXBsYXRlQmluZGluZyBCYWNrZ3JvdW5kfSIgQ29ybmVyUmFkaXVzPSI1IiBDbGlwVG9Cb3VuZHM9IlRydWUiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQgTmFtZT0iUEFSVF9UcmFjayI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBOYW1lPSJQQVJUX0luZGljYXRvciIgQmFja2dyb3VuZD0ie1RlbXBsYXRlQmluZGluZyBGb3JlZ3JvdW5kfSIgSG9yaXpvbnRhbEFsaWdubWVudD0iTGVmdCIgQ29ybmVyUmFkaXVzPSI1IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICA8L0NvbnRyb2xUZW1wbGF0ZT4KICAgICAgICAgICAgICAgIDwvU2V0dGVyLlZhbHVlPgogICAgICAgICAgICA8L1NldHRlcj4KICAgICAgICA8L1N0eWxlPgogICAgPC9XaW5kb3cuUmVzb3VyY2VzPgoKICAgIDxHcmlkIE1hcmdpbj0iMTYiPgogICAgICAgIDxHcmlkLlJvd0RlZmluaXRpb25zPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iIC8+IDwhLS0gQ2FiZWNhbGhvIGUgQmFubmVyIGRlIEhhcmR3YXJlIC0tPgogICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IioiIC8+ICAgIDwhLS0gQXJlYSBQcmluY2lwYWwgY29tIEFiYXMgLS0+CiAgICAgICAgICAgIDxSb3dEZWZpbml0aW9uIEhlaWdodD0iQXV0byIgLz4gPCEtLSBSb2RhcGUgZGUgU3RhdHVzIGUgUHJvZ3Jlc3NvIC0tPgogICAgICAgIDwvR3JpZC5Sb3dEZWZpbml0aW9ucz4KCiAgICAgICAgPCEtLSAxLiBDQUJFQ0FMSE8gJiBCQU5ORVIgREUgSEFSRFdBUkUgLS0+CiAgICAgICAgPEJvcmRlciBHcmlkLlJvdz0iMCIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSIxMCIgUGFkZGluZz0iMTYiIE1hcmdpbj0iMCwwLDAsMTIiPgogICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIwIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iREVXSU4gQk9PU1RFUiIgRm9udFNpemU9IjIwIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0RDRkZGIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMyNDI4M0IiIENvcm5lclJhZGl1cz0iNSIgUGFkZGluZz0iNiwyIiBNYXJnaW49IjEwLDAsMCwwIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iTmF0aXZvIGUgZGUgQ8OzZGlnbyBBYmVydG8iIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgRm9udFdlaWdodD0iU2VtaUJvbGQiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIE5hbWU9InR4dEhhcmR3YXJlQmFubmVyIiBUZXh0PSJEZXRlY3RhbmRvIGNvbXBvbmVudGVzIGRlIGhhcmR3YXJlLi4uIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCw1LDAsMCIgLz4KICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KCiAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSIgT3JpZW50YXRpb249Ikhvcml6b250YWwiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzI0MjgzQiIgQm9yZGVyQnJ1c2g9IiM0MTQ4NjgiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxMCw2IiBNYXJnaW49IjQsMCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgTmFtZT0idHh0RGV2aWNlVHlwZSIgVGV4dD0iRGV0ZWN0YW5kby4uLiIgRm9udFNpemU9IjEyIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0FBMkY3IiAvPgogICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgIDwhLS0gMi4gQUJBUyBQUklOQ0lQQUlTIC0tPgogICAgICAgIDxUYWJDb250cm9sIE5hbWU9Im1haW5UYWJDb250cm9sIiBHcmlkLlJvdz0iMSIgQmFja2dyb3VuZD0iIzEzMTQxRiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiPgogICAgICAgICAgICAKICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPCEtLSBBQkEgMTogUFJPR1JBTUFTICYgQVBMSUNBVElWT1MgKFRFTEEgSU5JQ0lBTCkgICAgICAgICAgICAtLT4KICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gTmFtZT0idGFiSXRlbVNvZnR3YXJlcyIgSGVhZGVyPSIgUHJvZ3JhbWFzIGUgQXBsaWNhdGl2b3MgIj4KICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIiBNYXJnaW49IjEwIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYWJlY2FsaG8gZSBBY29lcyBSYXBpZGFzIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMxQTFCMjYiIEJvcmRlckJydXNoPSIjMkYzNTRGIiBCb3JkZXJUaGlja25lc3M9IjEiIENvcm5lclJhZGl1cz0iOCIgUGFkZGluZz0iMTQiIE1hcmdpbj0iNiwwLDYsMTAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjAiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9Ikluc3RhbGHDp8OjbyBlIEF0dWFsaXphw6fDo28gZGUgU29mdHdhcmVzIHZpYSBXaW5nZXQiIEZvbnRTaXplPSIxNiIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJTZWxlY2lvbmUgb3MgcHJvZ3JhbWFzIHF1ZSBkZXNlamEgaW5zdGFsYXIgc2lsZW5jaW9zYW1lbnRlIG5vIGNvbXB1dGFkb3I6IiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsIEdyaWQuQ29sdW1uPSIxIiBPcmllbnRhdGlvbj0iSG9yaXpvbnRhbCIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuU2VsZWN0RXNzZW50aWFsQXBwcyIgQ29udGVudD0iRXNzZW5jaWFpcyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBNYXJnaW49IjAsMCw2LDAiIFRvb2xUaXA9IlNlbGVjaW9uYSBWaXN1YWwgQysrLCA3LVppcCBlIEdvb2dsZSBDaHJvbWUiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuU2VsZWN0QWxsQXBwcyIgQ29udGVudD0iTWFyY2FyIFRvZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iMCwwLDYsMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5EZXNlbGVjdEFsbEFwcHMiIENvbnRlbnQ9IkRlc21hcmNhciBUb2RvcyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENhdGFsb2dvIGRlIFNvZnR3YXJlcyBlbSBHcmlkIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ29sdW5hIDE6IFJ1bnRpbWVzIGUgTmF2ZWdhZG9yZXMgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJSdW50aW1lcyBlIFV0aWxpdMOhcmlvcyBFc3NlbmNpYWlzIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3RENGRkYiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBWY1JlZGlzdDY0IiBDb250ZW50PSJWaXN1YWwgQysrIDIwMTUtMjAyMiAoeDY0KSAtIFByw6ktcmVxdWlzaXRvIHBhcmEgam9nb3MgZSBwcm9ncmFtYXMiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iYXBwVmNSZWRpc3Q4NiIgQ29udGVudD0iVmlzdWFsIEMrKyAyMDE1LTIwMjIgKHg4NikgLSBDb21wYXRpYmlsaWRhZGUgZGUgYXBsaWNhdGl2b3MgMzItYml0IiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImFwcDd6aXAiIENvbnRlbnQ9IjctWmlwIC0gQ29tcGFjdGFkb3IgZSBkZXNjb21wYWN0YWRvciBkZSBhbHRhIHBlcmZvcm1hbmNlIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iTmF2ZWdhZG9yZXMgV2ViIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM5RUNFNkEiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBDaHJvbWUiIENvbnRlbnQ9Ikdvb2dsZSBDaHJvbWUgLSBOYXZlZ2Fkb3Igd2ViIG1vZGVybm8gZSBzZWd1cm8iIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENvbHVuYSAyOiBEZXNlbnZvbHZpbWVudG8gZSBNdWx0aW1pZGlhL0pvZ29zIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjEiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iRmVycmFtZW50YXMgZGUgRGVzZW52b2x2aW1lbnRvIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNCQjlBRjciIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBWc0NvZGUiIENvbnRlbnQ9IlZpc3VhbCBTdHVkaW8gQ29kZSAtIEVkaXRvciBkZSBjw7NkaWdvIGRhIE1pY3Jvc29mdCIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBHaXQiIENvbnRlbnQ9IkdpdCBmb3IgV2luZG93cyAtIFNpc3RlbWEgZGlzdHJpYnXDrWRvIGRlIGNvbnRyb2xlIGRlIHZlcnPDo28iIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJDb211bmljYcOnw6NvLCBNw61kaWEgZSBKb2dvcyIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjRTBBRjY4IiBNYXJnaW49IjAsMCwwLDgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iYXBwRGlzY29yZCIgQ29udGVudD0iRGlzY29yZCAtIENvbXVuaWNhw6fDo28gcG9yIHZveiwgdsOtZGVvIGUgdGV4dG8iIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iYXBwU3RlYW0iIENvbnRlbnQ9IlN0ZWFtIC0gUGxhdGFmb3JtYSBkZSBqb2dvcyBlIGNvbXVuaWRhZGUgZGlnaXRhbCIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJhcHBWbGMiIENvbnRlbnQ9IlZMQyBNZWRpYSBQbGF5ZXIgLSBSZXByb2R1dG9yIGRlIMOhdWRpbyBlIHbDrWRlbyB1bml2ZXJzYWwiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iYXBwU3BvdGlmeSIgQ29udGVudD0iU3BvdGlmeSAtIFN0cmVhbWluZyBkZSBtw7pzaWNhIGUgcG9kY2FzdHMiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBCb3RhbyBJbmRlcGVuZGVudGUgZGUgSW5zdGFsYWNhbyBkZSBTb2Z0d2FyZXMgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxNCIgTWFyZ2luPSI2LDEwLDYsNiI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJBIGluc3RhbGHDp8OjbyDDqSByZWFsaXphZGEgZW0gc2VndW5kbyBwbGFubyB2aWEgV2luZ2V0IG9maWNpYWwsIHNlbSBpbnRlcnJvbXBlciBhcyBhdGl2aWRhZGVzIGVtIGV4ZWN1w6fDo28uIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5JbnN0YWxsU29mdHdhcmVzIiBHcmlkLkNvbHVtbj0iMSIgQ29udGVudD0iSW5zdGFsYXIgUHJvZ3JhbWFzIFNlbGVjaW9uYWRvcyIgQmFja2dyb3VuZD0iIzI1NjNFQiIgQm9yZGVyQnJ1c2g9IiMzQjgyRjYiIEZvcmVncm91bmQ9IldoaXRlIiBGb250V2VpZ2h0PSJCb2xkIiBGb250U2l6ZT0iMTMiIFBhZGRpbmc9IjIwLDEwIiBDdXJzb3I9IkhhbmQiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uLlJlc291cmNlcz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdHlsZSBUYXJnZXRUeXBlPSJCb3JkZXIiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTZXR0ZXIgUHJvcGVydHk9IkNvcm5lclJhZGl1cyIgVmFsdWU9IjgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0eWxlPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0J1dHRvbi5SZXNvdXJjZXM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9CdXR0b24+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgIDwvU2Nyb2xsVmlld2VyPgogICAgICAgICAgICA8L1RhYkl0ZW0+CgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8IS0tIEFCQSAyOiBPVElNSVpBQ09FUyBETyBTSVNURU1BIEUgUEVSRklTICAgICAgICAgICAgICAgICAgIC0tPgogICAgICAgICAgICA8IS0tID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09IC0tPgogICAgICAgICAgICA8VGFiSXRlbSBOYW1lPSJ0YWJJdGVtVHdlYWtzIiBIZWFkZXI9IiBPdGltaXphw6fDtWVzIGRvIFNpc3RlbWEgIj4KICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIiBNYXJnaW49IjEwIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBOb3RpZmljYWNhbyBkZSBSZWNvbWVuZGFjYW8gZGUgSGFyZHdhcmUgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFDMjczOCIgQm9yZGVyQnJ1c2g9IiMyNTYzRUIiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxMiIgTWFyZ2luPSI2LDAsNiwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIE5hbWU9InR4dFJlY29tbWVuZGF0aW9uIiBUZXh0PSJDYWxjdWxhbmRvIG1lbGhvciBwZXJmaWwgcGFyYSBzdWEgbcOhcXVpbmEuLi4iIEZvbnRTaXplPSIxMyIgRm9yZWdyb3VuZD0iIzkzQzVGRCIgVGV4dFdyYXBwaW5nPSJXcmFwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gU2XDp8OjbyBkb3MgMyBOw612ZWlzIFLDoXBpZG9zIGRlIE90aW1pemHDp8OjbyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJOw612ZWlzIFLDoXBpZG9zIGRlIE90aW1pemHDp8OjbzoiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iU2VtaUJvbGQiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iOCw0LDgsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPFVuaWZvcm1HcmlkIENvbHVtbnM9IjMiIE1hcmdpbj0iMCwwLDAsMTAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIFBvdWNvIE90aW1pemFkbyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlBvdWNvIE90aW1pemFkbyIgRm9udFNpemU9IjE1IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjMzhCREY4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9Ik90aW1pemHDp8O1ZXMgZXNzZW5jaWFpcyBlIHNlZ3VyYXMsIG1hbnRlbmRvIGEgZXhwZXJpw6puY2lhIGNsw6Fzc2ljYSBkbyBXaW5kb3dzIDExIGludGFjdGEuIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsNiIgVGV4dFdyYXBwaW5nPSJXcmFwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IuKAoiBMaW1wZXphIGRlIGFycXVpdm9zIHRlbXBvcsOhcmlvcyBlIFNTRCYjeDBhO+KAoiBEZXNhdGl2YcOnw6NvIGRlIHRlbGVtZXRyaWEgYsOhc2ljYSBlIEJpbmcmI3gwYTvigKIgTWVudXMgcsOhcGlkb3MgZSBzdXBvcnRlIGEgY2FtaW5ob3MgbG9uZ29zIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0VHdlYWtMaWdodCIgQ29udGVudD0iU2VsZWNpb25hciBQb3VjbyBPdGltaXphZG8iIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzAyODRDNyIgQm9yZGVyQnJ1c2g9IiMzOEJERjgiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBNw6lkaW8gKFJlY29tZW5kYWRvKSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9Ik3DqWRpbyAoUmVjb21lbmRhZG8pIiBGb250U2l6ZT0iMTUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM0QURFODAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iRXF1aWzDrWJyaW8gaWRlYWwgZW50cmUgZGVzZW1wZW5obywgcHJpdmFjaWRhZGUsIHJlbW/Dp8OjbyBkZSBibG9hdCBlIGZsdWlkZXogZG8gc2lzdGVtYS4iIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgTWFyZ2luPSIwLDMsMCw2IiBUZXh0V3JhcHBpbmc9IldyYXAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0i4oCiIFJlbW/Dp8OjbyBkZSAyOCBibG9hdHdhcmVzIGUgdGVsZW1ldHJpYSYjeDBhO+KAoiBCYWl4YSBsYXTDqm5jaWEgZGUgcmVkZSBlIHNlbSBHYW1lRFZSJiN4MGE74oCiIE1lbnUgY2zDoXNzaWNvIGUgaGliZXJuYcOnw6NvIGludGVsaWdlbnRlIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0VHdlYWtNZWRpdW0iIENvbnRlbnQ9IlNlbGVjaW9uYXIgTcOpZGlvIChSZWNvbWVuZGFkbykiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzE2QTM0QSIgQm9yZGVyQnJ1c2g9IiMyMkM1NUUiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCAxMDAlIE90aW1pemFkbyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IjEwMCUgT3RpbWl6YWRvIiBGb250U2l6ZT0iMTUiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiNCQjlBRjciIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iTcOheGltbyBkZXNlbXBlbmhvIGFic29sdXRvIHBhcmEgam9nYWRvcmVzLCBjcmlhZG9yZXMgZSBkZXNlbnZvbHZlZG9yZXMgZXhpZ2VudGVzLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBNYXJnaW49IjAsMywwLDYiIFRleHRXcmFwcGluZz0iV3JhcCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSLigKIgVG9kYXMgYXMgMjggb3RpbWl6YcOnw7VlcyBhdGl2YWRhcyYjeDBhO+KAoiBDYWxpYnJhw6fDo28gZGUgR1BVLCBDUFUgZSBtZW3Ds3JpYSYjeDBhO+KAoiBSZWzDs2dpbyBVVEMgZSBpbmljaWFsaXphw6fDo28gbGltcGEiIEZvbnRTaXplPSIxMSIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgTWFyZ2luPSIwLDIsMCwxMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5QcmVzZXRUd2Vha0FnZ3Jlc3NpdmUiIENvbnRlbnQ9IlNlbGVjaW9uYXIgMTAwJSBPdGltaXphZG8iIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzdDM0FFRCIgQm9yZGVyQnJ1c2g9IiM4QjVDRjYiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICA8L1VuaWZvcm1HcmlkPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBCYXJyYSBkZSBGZXJyYW1lbnRhcyBkZSBTZWxlY2FvIGRvcyBUd2Vha3MgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxMiIgTWFyZ2luPSI2LDAsNiwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJTZWxlw6fDo28gUGVyc29uYWxpemFkYSBkZSBPdGltaXphw6fDtWVzOiIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLkNvbHVtbj0iMSIgT3JpZW50YXRpb249Ikhvcml6b250YWwiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0blNlbGVjdEFsbCIgQ29udGVudD0iTWFyY2FyIFRvZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iMCwwLDYsMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5EZXNlbGVjdEFsbCIgQ29udGVudD0iRGVzbWFyY2FyIFRvZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iMCwwLDYsMCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5SZXNldFJlY29tbWVuZGVkIiBDb250ZW50PSJSZXN0YXVyYXIgUmVjb21lbmRhZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gR3JpZCBkZSBUd2Vha3MgcG9yIENhdGVnb3JpYSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8IS0tIENvbHVuYSAxOiBJbnRlcmZhY2UgZSBEZXNlbXBlbmhvIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBJbnRlcmZhY2UgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJJbnRlcmZhY2UgZSBCYXJyYSBkZSBUYXJlZmFzIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM3RENGRkYiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtIaWRlU2VhcmNoIiBDb250ZW50PSJPY3VsdGFyIGNhaXhhIGRlIHBlc3F1aXNhIG5hIGJhcnJhIGRlIHRhcmVmYXMiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iT2N1bHRhIGEgYmFycmEgZGUgcGVzcXVpc2E7IGEgYnVzY2EgZG8gbWVudSBJbmljaWFyIHBlcm1hbmVjZSBkaXNwb27DrXZlbCBhbyBkaWdpdGFyLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtIaWRlVGFza1ZpZXciIENvbnRlbnQ9Ik9jdWx0YXIgYm90w6NvIGRlIFZpc8OjbyBkZSBUYXJlZmFzIChUYXNrIFZpZXcpIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9Ik9jdWx0YSBvIMOtY29uZSBkYSBiYXJyYTsgbyBhdGFsaG8gV2luK1RhYiBwZXJtYW5lY2UgdG90YWxtZW50ZSBmdW5jaW9uYWwuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0NlbnRlclRhc2tiYXIiIENvbnRlbnQ9IkFsaW5oYW1lbnRvIGNlbnRyYWxpemFkbyBkYSBiYXJyYSBkZSB0YXJlZmFzIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9Ik1hbnTDqW0gYSBiYXJyYSBkZSB0YXJlZmFzIGNlbnRyYWxpemFkYSBubyBwYWRyw6NvIG1vZGVybm8gZG8gV2luZG93cyAxMS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrVGFza2JhckVuZFRhc2siIENvbnRlbnQ9IkF0aXZhciBvcMOnw6NvICdGaW5hbGl6YXIgVGFyZWZhJyBubyBib3TDo28gZGlyZWl0byIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJQZXJtaXRlIGVuY2VycmFyIHByb2Nlc3NvcyBuw6NvIHJlc3BvbnNpdm9zIGRpcmV0YW1lbnRlIHBlbG8gYm90w6NvIGRpcmVpdG8gbmEgYmFycmEgZGUgdGFyZWZhcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrQ2xhc3NpY0NvbnRleHRNZW51IiBDb250ZW50PSJNZW51IGRlIGNvbnRleHRvIGNsw6Fzc2ljbyAoZXN0aWxvIFdpbmRvd3MgMTApIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkV4aWJlIHRvZGFzIGFzIG9ww6fDtWVzIGRvIG1lbnUgZGUgY29udGV4dG8gZGlyZXRhbWVudGUsIHNlbSBzdWJtZW51cyBhZGljaW9uYWlzLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtMYXVuY2hUb1RoaXNQQyIgQ29udGVudD0iQWJyaXIgRXhwbG9yYWRvciBkZSBBcnF1aXZvcyBlbSAnRXN0ZSBDb21wdXRhZG9yJyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJDb25maWd1cmEgbyBFeHBsb3JhZG9yIGRlIEFycXVpdm9zIHBhcmEgaW5pY2lhciBuYXMgdW5pZGFkZXMgZGUgZGlzY28sIHJlbW92ZW5kbyBww6FnaW5hcyBsZW50YXMgZGUgSW7DrWNpbyBlIEdhbGVyaWEuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa1Nob3dFeHRlbnNpb25zQW5kSGlkZGVuIiBDb250ZW50PSJFeGliaXIgZXh0ZW5zw7VlcyBlIGFycXVpdm9zIG9jdWx0b3MiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRmFjaWxpdGEgYSB2aXN1YWxpemHDp8OjbyBkZSBleHRlbnPDtWVzIGRlIGFycXVpdm9zICguYmF0LCAucHMxLCAuanNvbikgZSBwYXN0YXMgZGUgY29uZmlndXJhw6fDo28uIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Fsd2F5c1Nob3dTY3JvbGxiYXJzIiBDb250ZW50PSJNYW50ZXIgYmFycmFzIGRlIHJvbGFnZW0gc2VtcHJlIHZpc8OtdmVpcyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJFdml0YSBxdWUgYXMgYmFycmFzIGRlIHJvbGFnZW0gc2VqYW0gb2N1bHRhZGFzIGF1dG9tYXRpY2FtZW50ZSBwZWxhIGludGVyZmFjZS4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIERlc2VtcGVuaG8gLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJEZXNlbXBlbmhvLCBMYXTDqm5jaWEgZSBBcm1hemVuYW1lbnRvIiBGb250U2l6ZT0iMTQiIEZvbnRXZWlnaHQ9IkJvbGQiIEZvcmVncm91bmQ9IiM5RUNFNkEiIE1hcmdpbj0iMCwwLDAsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtPcHRpbWl6ZU5ldHdvcmtMYXRlbmN5IiBDb250ZW50PSJPdGltaXphciBsYXTDqm5jaWEgZGUgcmVkZSAoTmV0d29ya1Rocm90dGxpbmcpIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIGEgbGltaXRhw6fDo28gZGUgcmVkZSBkbyBXaW5kb3dzIHBhcmEgbWVub3IgbGF0w6puY2lhIGVtIGNvbmV4w7VlcyBlIGpvZ29zLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlR2FtZURWUiIgQ29udGVudD0iRGVzYXRpdmFyIEdhbWVEVlIgZSBjYXB0dXJhIGVtIHNlZ3VuZG8gcGxhbm8iIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRWxpbWluYSBzb2JyZWNhcmdhIGRlIHByb2Nlc3NhZG9yIGUgcGxhY2EgZGUgdsOtZGVvIGdlcmFkYSBwb3IgZ3JhdmHDp8O1ZXMgYXV0b23DoXRpY2FzIGRlIHRlbGEuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0xpbmVhck1vdXNlIiBDb250ZW50PSJSZXNwb3N0YSBsaW5lYXIgZG8gcG9udGVpcm8gZG8gbW91c2UgKFByZWNpc8OjbyAxOjEpIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIGEgYWNlbGVyYcOnw6NvIGFydGlmaWNpYWwgZG8gcG9udGVpcm8gcGFyYSBjb25zaXN0w6puY2lhIGRlIG1vdmltZW50by4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZVN0aWNreUtleXMiIENvbnRlbnQ9IkRlc2F0aXZhciBhdGFsaG8gZGUgVGVjbGFzIGRlIEFkZXLDqm5jaWEiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iSW1wZWRlIGEgZXhpYmnDp8OjbyBkbyBkacOhbG9nbyBkZSBjb25maXJtYcOnw6NvIGFvIHByZXNzaW9uYXIgYSB0ZWNsYSBTaGlmdCBjb25zZWN1dGl2YW1lbnRlLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtJbnN0YW50TWVudURlbGF5IiBDb250ZW50PSJSZW1vdmVyIGF0cmFzbyBuYSBhYmVydHVyYSBkZSBtZW51cyAoMCBtcykiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iUmVkdXogbyB0ZW1wbyBkZSBlc3BlcmEgbmEgYWJlcnR1cmEgZGUgc3VibWVudXMgc3VzcGVuc29zIHBhcmEgcmVzcG9zdGEgaW1lZGlhdGEuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa09wdGltaXplU3NkQWNjZXNzIiBDb250ZW50PSJPdGltaXphciBncmF2YcOnw7VlcyBlbSBTU0QgKERpc2FibGVMYXN0QWNjZXNzKSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJEZXNhdGl2YSBhIGdyYXZhw6fDo28gY29udMOtbnVhIGRlIGRhdGEgZGUgw7psdGltbyBhY2Vzc28sIHJlZHV6aW5kbyBlc2NyaXRhcyBlIHByZXNlcnZhbmRvIG8gU1NELiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtDbGVhblRlbXBGaWxlcyIgQ29udGVudD0iTGltcGFyIGFycXVpdm9zIHRlbXBvcsOhcmlvcyBkbyBzaXN0ZW1hIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkVzdmF6aWEgY2FjaGVzIGUgYXJxdWl2b3MgdGVtcG9yw6FyaW9zIG7Do28gdXRpbGl6YWRvcyBwZWxvIHNpc3RlbWEgb3BlcmFjaW9uYWwuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDb2x1bmEgMjogUHJpdmFjaWRhZGUsIERlYmxvYXQgZSBTaXN0ZW1hIC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjEiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBQcml2YWNpZGFkZSAmIERlYmxvYXQgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJQcml2YWNpZGFkZSwgVGVsZW1ldHJpYSBlIEFwbGljYXRpdm9zIFBhZHLDo28iIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0JCOUFGNyIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVUZWxlbWV0cnkiIENvbnRlbnQ9IkRlc2F0aXZhciB0ZWxlbWV0cmlhIGUgc2VydmnDp29zIGRlIGRpYWduw7NzdGljbyIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJEZXNhdGl2YSBvIHNlcnZpw6dvIERpYWdUcmFjayBlIG8gZW52aW8gZGUgZGFkb3MgZGlhZ27Ds3N0aWNvcyBwYXJhIHNlcnZpZG9yZXMgZXh0ZXJub3MuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVDZWlwVGFza3MiIENvbnRlbnQ9IkRlc2F0aXZhciB0YXJlZmFzIGFnZW5kYWRhcyBkZSBkaWFnbsOzc3RpY28gKENFSVApIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIHJvdGluYXMgYWdlbmRhZGFzIGRlIHRlbGVtZXRyaWEgZXhlY3V0YWRhcyBkdXJhbnRlIHBlcsOtb2RvcyBkZSBvY2lvc2lkYWRlLiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJjaGtEaXNhYmxlQ29waWxvdFJlY2FsbCIgQ29udGVudD0iRGVzYXRpdmFyIFdpbmRvd3MgQ29waWxvdCBlIHJlY3Vyc29zIGRlIElBIFJlY2FsbCIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJEZXNhdGl2YSBvIGFzc2lzdGVudGUgQ29waWxvdCBlIHJvdGluYXMgZGUgYW7DoWxpc2UgY29udMOtbnVhIGRlIHRlbGEgZW0gc2VndW5kbyBwbGFuby4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZUJpbmdTZWFyY2giIENvbnRlbnQ9IkRlc2F0aXZhciByZXN1bHRhZG9zIGRvIEJpbmcgbm8gbWVudSBJbmljaWFyIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9Ik1hbnTDqW0gYSBidXNjYSBkbyBtZW51IEluaWNpYXIgZXN0cml0YW1lbnRlIGxvY2FsIHBhcmEgcmVzcG9zdGFzIGltZWRpYXRhcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGVibG9hdEVkZ2UiIENvbnRlbnQ9Ik90aW1pemFyIHRlbGVtZXRyaWEgZG8gTWljcm9zb2Z0IEVkZ2UiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iRGVzYXRpdmEgbyBlbnZpbyBkZSBtw6l0cmljYXMgZGUgbmF2ZWdhw6fDo28gZSBhc3Npc3RlbnRlcyBkZSBjb21wcmEsIHByZXNlcnZhbmRvIG8gV2ViVmlldzIuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa1JlbW92ZVV3cEJsb2F0IiBDb250ZW50PSJSZW1vdmVyIGFwbGljYXRpdm9zIHByw6ktaW5zdGFsYWRvcyBkZXNuZWNlc3PDoXJpb3MiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iUmVtb3ZlIHBhY290ZXMgcHJvbW9jaW9uYWlzIHByw6ktaW5zdGFsYWRvcyBkZSBlbnRyZXRlbmltZW50byBlIHJlZGVzIHNvY2lhaXMuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBTaXN0ZW1hICYgRW5lcmdpYSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgUHJvZmlsZUNhcmR9Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlNpc3RlbWEsIEdyw6FmaWNvcyBlIEdlcmVuY2lhbWVudG8gZGUgRW5lcmdpYSIgRm9udFNpemU9IjE0IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjRTBBRjY4IiBNYXJnaW49IjAsMCwwLDgiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrQ2FsaWJyYXRlR3B1IiBDb250ZW50PSJDYWxpYnJhciB0b2xlcsOibmNpYSBkZSBkcml2ZXIgZ3LDoWZpY28gKFRkckRlbGF5IGUgSEFHUykiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iQXVtZW50YSBhIHRvbGVyw6JuY2lhIHBhcmEgcmVjdXBlcmHDp8OjbyBkbyBkcml2ZXIgZ3LDoWZpY28gZSBhdGl2YSBvIGFnZW5kYW1lbnRvIGRlIEdQVSBwb3IgaGFyZHdhcmUuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa1NtYXJ0SGliZXJuYXRpb24iIENvbnRlbnQ9IkdlcmVuY2lhbWVudG8gaW50ZWxpZ2VudGUgZGUgaGliZXJuYcOnw6NvIiBJc0NoZWNrZWQ9IlRydWUiIFRvb2xUaXA9IkRlc2F0aXZhIGEgaGliZXJuYcOnw6NvIGVtIGNvbXB1dGFkb3JlcyBkZSBtZXNhIHBhcmEgcmVjdXBlcmFyIGVzcGHDp28gZW0gZGlzY28gU1NEIG91IGNvbmZpZ3VyYSBtb2RvIGNvbXBhY3RvIGVtIG5vdGVib29rcy4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrRGlzYWJsZVJlc2VydmVkU3RvcmFnZSIgQ29udGVudD0iRGVzYXRpdmFyIEFybWF6ZW5hbWVudG8gUmVzZXJ2YWRvIGRvIFdpbmRvd3MiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iTGliZXJhIGFwcm94aW1hZGFtZW50ZSA3IEdCIGRlIGVzcGHDp28gZW0gZGlzY28gYW50ZXJpb3JtZW50ZSByZXRpZG9zIHBlbG8gc2lzdGVtYSBvcGVyYWNpb25hbC4iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iY2hrT3B0aW1pemVTdmNIb3N0IiBDb250ZW50PSJDYWxpYnJhciBkaXZpc8OjbyBkZSBwcm9jZXNzb3MgZGUgc2VydmnDp29zIChTdmNIb3N0KSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJBanVzdGEgbyBpc29sYW1lbnRvIGRlIHNlcnZpw6dvcyBkZSBhY29yZG8gY29tIGEgcXVhbnRpZGFkZSB0b3RhbCBkZSBtZW3Ds3JpYSBSQU0uIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0VuYWJsZUxvbmdQYXRocyIgQ29udGVudD0iSGFiaWxpdGFyIHN1cG9ydGUgYSBjYW1pbmhvcyBsb25nb3MgZGUgYXJxdWl2b3MiIElzQ2hlY2tlZD0iVHJ1ZSIgVG9vbFRpcD0iUmVtb3ZlIGEgbGltaXRhw6fDo28gbGVnYWRhIGRlIDI2MCBjYXJhY3RlcmVzIChNQVhfUEFUSCkgZW0gY2FtaW5ob3MgZGUgYXJxdWl2b3MgZSBwYXN0YXMuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0Rpc2FibGVMb2NrU2NyZWVuIiBDb250ZW50PSJQdWxhciB0ZWxhIGRlIGJsb3F1ZWlvIGVzdMOhdGljYSIgSXNDaGVja2VkPSJUcnVlIiBUb29sVGlwPSJBcHJlc2VudGEgbyBjYW1wbyBkZSBhdXRlbnRpY2HDp8OjbyBkaXJldGFtZW50ZSBhbyBsaWdhciBvdSBkZXNibG9xdWVhciBvIGNvbXB1dGFkb3IuIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImNoa0lzRGV2IiBDb250ZW50PSJDb25maWd1cmHDp8O1ZXMgcGFyYSBkZXNlbnZvbHZlZG9yZXMgKFJlbMOzZ2lvIFVUQyBlIERpYWduw7NzdGljb3MpIiBJc0NoZWNrZWQ9IkZhbHNlIiBUb29sVGlwPSJDb25maWd1cmEgbyByZWzDs2dpbyBkYSBwbGFjYS1tw6NlIGVtIFVUQyBwYXJhIHNpbmNyb25pemHDp8OjbyBjb20gTGludXggZSBoYWJpbGl0YSBtZW5zYWdlbnMgZGV0YWxoYWRhcyBkZSBib290LiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQ+CgogICAgICAgICAgICAgICAgICAgICAgICA8IS0tIEJvdGFvIEluZGVwZW5kZW50ZSBkZSBBcGxpY2FjYW8gZGFzIE90aW1pemFjb2VzIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEJhY2tncm91bmQ9IiMxQTFCMjYiIEJvcmRlckJydXNoPSIjMkYzNTRGIiBCb3JkZXJUaGlja25lc3M9IjEiIENvcm5lclJhZGl1cz0iOCIgUGFkZGluZz0iMTQiIE1hcmdpbj0iNiwxMCw2LDYiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iQXMgY29uZmlndXJhw6fDtWVzIHPDo28gYXBsaWNhZGFzIG5vIFJlZ2lzdHJvIGUgbm9zIHNlcnZpw6dvcyBkbyBzaXN0ZW1hIGNvbSByZWluaWNpYWxpemHDp8OjbyBsaW1wYSBkbyBFeHBsb3JhZG9yIGRlIEFycXVpdm9zLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkFwcGx5T3B0aW1pemF0aW9ucyIgR3JpZC5Db2x1bW49IjEiIENvbnRlbnQ9IkFwbGljYXIgT3RpbWl6YcOnw7VlcyBTZWxlY2lvbmFkYXMiIEJhY2tncm91bmQ9IiMxNkEzNEEiIEJvcmRlckJydXNoPSIjMjJDNTVFIiBGb3JlZ3JvdW5kPSJXaGl0ZSIgRm9udFdlaWdodD0iQm9sZCIgRm9udFNpemU9IjEzIiBQYWRkaW5nPSIyMCwxMCIgQ3Vyc29yPSJIYW5kIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbi5SZXNvdXJjZXM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3R5bGUgVGFyZ2V0VHlwZT0iQm9yZGVyIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJDb3JuZXJSYWRpdXMiIFZhbHVlPSI4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdHlsZT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9CdXR0b24uUmVzb3VyY2VzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQnV0dG9uPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICA8L1Njcm9sbFZpZXdlcj4KICAgICAgICAgICAgPC9UYWJJdGVtPgoKICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPCEtLSBBQkEgMzogUkVDVVJTT1MgT1BDSU9OQUlTIERPIFdJTkRPV1MgKERJU00pICAgICAgICAgICAgICAtLT4KICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gTmFtZT0idGFiSXRlbUZlYXR1cmVzIiBIZWFkZXI9IiBSZWN1cnNvcyBPcGNpb25haXMgLyBFeHRyYXMgIj4KICAgICAgICAgICAgICAgIDxTY3JvbGxWaWV3ZXIgVmVydGljYWxTY3JvbGxCYXJWaXNpYmlsaXR5PSJBdXRvIiBNYXJnaW49IjEwIj4KICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBOb3RpZmljYWNhbyBkZSBSZWN1cnNvcyAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjE0IiBNYXJnaW49IjYsMCw2LDEwIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUmVjdXJzb3Mgb3BjaW9uYWlzIGRvIFdpbmRvd3MgZ2VyZW5jaWFkb3MgbmF0aXZhbWVudGUgdmlhIERJU006IiBGb250U2l6ZT0iMTUiIEZvbnRXZWlnaHQ9IlNlbWlCb2xkIiBGb3JlZ3JvdW5kPSIjQzhEM0Y1IiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KCiAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gUGVyZmlzIFLDoXBpZG9zIGRlIFJlY3Vyc29zIC0tPgogICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlBlcmZpcyBSw6FwaWRvcyBkZSBSZWN1cnNvczoiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iU2VtaUJvbGQiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iOCw0LDgsOCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPFVuaWZvcm1HcmlkIENvbHVtbnM9IjIiIE1hcmdpbj0iMCwwLDAsMTAiPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBDYXJkIFBlcmZpbCBHZXJhbCAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxTdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlBlcmZpbCBHZXJhbCIgRm9udFNpemU9IjE1IiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjMzhCREY4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IkNvbXBhdGliaWxpZGFkZSBlc3NlbmNpYWwgY29tIGpvZ29zIGUgcHJvZ3JhbWFzIGxlZ2Fkb3Mgc2VtIGNvbnN1bW8gZXh0cmEgZGUgcmVjdXJzb3MuIiBGb250U2l6ZT0iMTIiIEZvcmVncm91bmQ9IiM3OTgyQTkiIE1hcmdpbj0iMCwzLDAsNiIgVGV4dFdyYXBwaW5nPSJXcmFwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IuKAoiBIYWJpbGl0YSBhcGVuYXMgbyAuTkVUIEZyYW1ld29yayAzLjUgKDIuMC8zLjApJiN4MGE74oCiIE1hbnTDqW0gcmVjdXJzb3MgZGUgdmlydHVhbGl6YcOnw6NvIGRlc2F0aXZhZG9zIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0RmVhdEdlbmVyYWwiIENvbnRlbnQ9IlNlbGVjaW9uYXIgUGVyZmlsIEdlcmFsICguTkVUIGFwZW5hcykiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzAyODRDNyIgQm9yZGVyQnJ1c2g9IiMzOEJERjgiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwhLS0gQ2FyZCBQZXJmaWwgRGV2IC0tPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFByb2ZpbGVDYXJkfSI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iUGVyZmlsIERlc2Vudm9sdmVkb3IgKERldikiIEZvbnRTaXplPSIxNSIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0JCOUFGNyIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJBbWJpZW50ZSBjb21wbGV0byBkZSBkZXNlbnZvbHZpbWVudG8sIGNvbnTDqmluZXJlcyBlIHRlc3RlcyBzZWd1cm9zIGlzb2xhZG9zLiIgRm9udFNpemU9IjEyIiBGb3JlZ3JvdW5kPSIjNzk4MkE5IiBNYXJnaW49IjAsMywwLDYiIFRleHRXcmFwcGluZz0iV3JhcCIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSLigKIgSGFiaWxpdGEgdG9kb3Mgb3MgNSByZWN1cnNvcyBvcGNpb25haXMmI3gwYTvigKIgLk5FVCAzLjUsIFdTTDIsIEh5cGVyLVYsIFNhbmRib3ggZSBQbGF0YWZvcm1hIFZNIiBGb250U2l6ZT0iMTEiIEZvcmVncm91bmQ9IiNDOEQzRjUiIE1hcmdpbj0iMCwyLDAsMTAiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuUHJlc2V0RmVhdERldiIgQ29udGVudD0iU2VsZWNpb25hciBQZXJmaWwgRGVzZW52b2x2ZWRvciAoVHVkbykiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgQmFja2dyb3VuZD0iIzdDM0FFRCIgQm9yZGVyQnJ1c2g9IiM4QjVDRjYiIEZvcmVncm91bmQ9IldoaXRlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvU3RhY2tQYW5lbD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgogICAgICAgICAgICAgICAgICAgICAgICA8L1VuaWZvcm1HcmlkPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBCYXJyYSBkZSBGZXJyYW1lbnRhcyBkZSBTZWxlw6fDo28gZGUgUmVjdXJzb3MgLS0+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgQmFja2dyb3VuZD0iIzFBMUIyNiIgQm9yZGVyQnJ1c2g9IiMyRjM1NEYiIEJvcmRlclRoaWNrbmVzcz0iMSIgQ29ybmVyUmFkaXVzPSI4IiBQYWRkaW5nPSIxMiIgTWFyZ2luPSI2LDAsNiwxMCI+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZD4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8R3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvR3JpZC5Db2x1bW5EZWZpbml0aW9ucz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJTZWxlw6fDo28gUGVyc29uYWxpemFkYSBkZSBSZWN1cnNvczoiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iI0M4RDNGNSIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWwgR3JpZC5Db2x1bW49IjEiIE9yaWVudGF0aW9uPSJIb3Jpem9udGFsIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5TZWxlY3RBbGxGZWF0IiBDb250ZW50PSJNYXJjYXIgVG9kb3MiIFN0eWxlPSJ7U3RhdGljUmVzb3VyY2UgU2Vjb25kYXJ5QnV0dG9ufSIgTWFyZ2luPSIwLDAsNiwwIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8QnV0dG9uIE5hbWU9ImJ0bkRlc2VsZWN0QWxsRmVhdCIgQ29udGVudD0iRGVzbWFyY2FyIFRvZG9zIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgIDxCb3JkZXIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBQcm9maWxlQ2FyZH0iPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPFN0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBUZXh0PSJDb21wb25lbnRlcyBlIFJlY3Vyc29zIGRvIFNpc3RlbWEiIEZvbnRTaXplPSIxNCIgRm9udFdlaWdodD0iQm9sZCIgRm9yZWdyb3VuZD0iIzdEQ0ZGRiIgTWFyZ2luPSIwLDAsMCw4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJmZWF0TmV0RngzIiBDb250ZW50PSIuTkVUIEZyYW1ld29yayAzLjUgKENvbXBhdGliaWxpZGFkZSBsZWdhZGEgY29tIHZlcnPDtWVzIDIuMCBlIDMuMCkiIElzQ2hlY2tlZD0iVHJ1ZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iZmVhdFdzbCIgQ29udGVudD0iU3Vic2lzdGVtYSBkbyBXaW5kb3dzIHBhcmEgTGludXggKFdTTDIpIiBJc0NoZWNrZWQ9IkZhbHNlIiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxDaGVja0JveCBOYW1lPSJmZWF0Vm1QbGF0Zm9ybSIgQ29udGVudD0iUGxhdGFmb3JtYSBkZSBNw6FxdWluYSBWaXJ0dWFsIChQcsOpLXJlcXVpc2l0byBkbyBXU0wyKSIgSXNDaGVja2VkPSJGYWxzZSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q2hlY2tCb3ggTmFtZT0iZmVhdEh5cGVyViIgQ29udGVudD0iSHlwZXItViAoVmlydHVhbGl6YcOnw6NvIG5hdGl2YSBwYXJhIG3DoXF1aW5hcyB2aXJ0dWFpcyBlIERvY2tlcikiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENoZWNrQm94IE5hbWU9ImZlYXRTYW5kYm94IiBDb250ZW50PSJXaW5kb3dzIFNhbmRib3ggKEFtYmllbnRlIGlzb2xhZG8gcGFyYSB0ZXN0ZXMgc2VndXJvcykiIElzQ2hlY2tlZD0iRmFsc2UiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICAgICAgICAgIDwvQm9yZGVyPgoKICAgICAgICAgICAgICAgICAgICAgICAgPCEtLSBCb3RhbyBJbmRlcGVuZGVudGUgZGUgUmVjdXJzb3MgRElTTSAtLT4KICAgICAgICAgICAgICAgICAgICAgICAgPEJvcmRlciBCYWNrZ3JvdW5kPSIjMUExQjI2IiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjE0IiBNYXJnaW49IjYsMTAsNiw2Ij4KICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDxHcmlkLkNvbHVtbkRlZmluaXRpb25zPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iKiIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPENvbHVtbkRlZmluaXRpb24gV2lkdGg9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkLkNvbHVtbkRlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJsb2NrIFRleHQ9IlJlcXVlciBjb25leMOjbyBjb20gYSBpbnRlcm5ldCBwYXJhIGJhaXhhciBhcnF1aXZvcyBkZSBjb21wb25lbnRlcyBhZGljaW9uYWlzIGRhIE1pY3Jvc29mdC4iIEZvbnRTaXplPSIxMiIgRm9yZWdyb3VuZD0iIzc5ODJBOSIgVmVydGljYWxBbGlnbm1lbnQ9IkNlbnRlciIgLz4KCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5FbmFibGVGZWF0dXJlcyIgR3JpZC5Db2x1bW49IjEiIENvbnRlbnQ9IkhhYmlsaXRhciBSZWN1cnNvcyBTZWxlY2lvbmFkb3MiIEJhY2tncm91bmQ9IiM3QzNBRUQiIEJvcmRlckJydXNoPSIjOEI1Q0Y2IiBGb3JlZ3JvdW5kPSJXaGl0ZSIgRm9udFdlaWdodD0iQm9sZCIgRm9udFNpemU9IjEzIiBQYWRkaW5nPSIyMCwxMCIgQ3Vyc29yPSJIYW5kIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbi5SZXNvdXJjZXM+CiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U3R5bGUgVGFyZ2V0VHlwZT0iQm9yZGVyIj4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICA8U2V0dGVyIFByb3BlcnR5PSJDb3JuZXJSYWRpdXMiIFZhbHVlPSI4IiAvPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9TdHlsZT4KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9CdXR0b24uUmVzb3VyY2VzPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIDwvQnV0dG9uPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgICAgICAgICA8L0JvcmRlcj4KICAgICAgICAgICAgICAgICAgICA8L1N0YWNrUGFuZWw+CiAgICAgICAgICAgICAgICA8L1Njcm9sbFZpZXdlcj4KICAgICAgICAgICAgPC9UYWJJdGVtPgoKICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPCEtLSBBQkEgNDogUkVHSVNUUk8gRSBMT0dTIEVNIFRFTVBPIFJFQUwgICAgICAgICAgICAgICAgICAgICAtLT4KICAgICAgICAgICAgPCEtLSA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSAtLT4KICAgICAgICAgICAgPFRhYkl0ZW0gTmFtZT0idGFiSXRlbUxvZyIgSGVhZGVyPSIgUmVnaXN0cm8gZSBMb2dzICI+CiAgICAgICAgICAgICAgICA8R3JpZCBNYXJnaW49IjEwIj4KICAgICAgICAgICAgICAgICAgICA8R3JpZC5Sb3dEZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSJBdXRvIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IioiIC8+CiAgICAgICAgICAgICAgICAgICAgPC9HcmlkLlJvd0RlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgICAgICA8U3RhY2tQYW5lbCBHcmlkLlJvdz0iMCIgT3JpZW50YXRpb249Ikhvcml6b250YWwiIE1hcmdpbj0iMCwwLDAsOCI+CiAgICAgICAgICAgICAgICAgICAgICAgIDxUZXh0QmxvY2sgVGV4dD0iQWNvbXBhbmhhbWVudG8gZW0gdGVtcG8gcmVhbCBkYSBleGVjdcOnw6NvIGUgYXVkaXRvcmlhIGRlIHNpc3RlbWE6IiBGb250U2l6ZT0iMTMiIEZvcmVncm91bmQ9IiM3OTgyQTkiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CiAgICAgICAgICAgICAgICAgICAgICAgIDxCdXR0b24gTmFtZT0iYnRuT3BlbkxvZ0ZvbGRlciIgQ29udGVudD0iQWJyaXIgUGFzdGEgZGUgTG9ncyIgU3R5bGU9IntTdGF0aWNSZXNvdXJjZSBTZWNvbmRhcnlCdXR0b259IiBNYXJnaW49IjEyLDAsMCwwIiBQYWRkaW5nPSI4LDMiIEZvbnRTaXplPSIxMSIgLz4KICAgICAgICAgICAgICAgICAgICAgICAgPEJ1dHRvbiBOYW1lPSJidG5DbGVhckxvZ0NvbnNvbGUiIENvbnRlbnQ9IkxpbXBhciBDb25zb2xlIiBTdHlsZT0ie1N0YXRpY1Jlc291cmNlIFNlY29uZGFyeUJ1dHRvbn0iIE1hcmdpbj0iOCwwLDAsMCIgUGFkZGluZz0iOCwzIiBGb250U2l6ZT0iMTEiIC8+CiAgICAgICAgICAgICAgICAgICAgPC9TdGFja1BhbmVsPgoKICAgICAgICAgICAgICAgICAgICA8Qm9yZGVyIEdyaWQuUm93PSIxIiBCYWNrZ3JvdW5kPSIjMEEwQjEwIiBCb3JkZXJCcnVzaD0iIzJGMzU0RiIgQm9yZGVyVGhpY2tuZXNzPSIxIiBDb3JuZXJSYWRpdXM9IjgiIFBhZGRpbmc9IjgiPgogICAgICAgICAgICAgICAgICAgICAgICA8VGV4dEJveCBOYW1lPSJ0eHRDb25zb2xlTG9nIiBCYWNrZ3JvdW5kPSJUcmFuc3BhcmVudCIgRm9yZWdyb3VuZD0iIzlFQ0U2QSIgRm9udEZhbWlseT0iQ29uc29sYXMsIENhc2NhZGlhIENvZGUsIENvdXJpZXIgTmV3IiBGb250U2l6ZT0iMTIiIElzUmVhZE9ubHk9IlRydWUiIEJvcmRlclRoaWNrbmVzcz0iMCIgVGV4dFdyYXBwaW5nPSJXcmFwIiBWZXJ0aWNhbFNjcm9sbEJhclZpc2liaWxpdHk9IkF1dG8iIFRleHQ9IkRFV0lOIEJvb3N0ZXIgcHJvbnRvLiBTZWxlY2lvbmUgcHJvZ3JhbWFzIG91IG90aW1pemHDp8O1ZXMgcGFyYSBjb21lw6dhci4iIC8+CiAgICAgICAgICAgICAgICAgICAgPC9Cb3JkZXI+CiAgICAgICAgICAgICAgICA8L0dyaWQ+CiAgICAgICAgICAgIDwvVGFiSXRlbT4KCiAgICAgICAgPC9UYWJDb250cm9sPgoKICAgICAgICA8IS0tIDMuIFJPREFQRSBHTE9CQUwgREUgU1RBVFVTICYgUFJPR1JFU1NPIC0tPgogICAgICAgIDxCb3JkZXIgR3JpZC5Sb3c9IjIiIEJhY2tncm91bmQ9IiMxQTFCMjYiIEJvcmRlckJydXNoPSIjMkYzNTRGIiBCb3JkZXJUaGlja25lc3M9IjEiIENvcm5lclJhZGl1cz0iMTAiIFBhZGRpbmc9IjE0LDEwIiBNYXJnaW49IjAsMTIsMCwwIj4KICAgICAgICAgICAgPEdyaWQ+CiAgICAgICAgICAgICAgICA8R3JpZC5Sb3dEZWZpbml0aW9ucz4KICAgICAgICAgICAgICAgICAgICA8Um93RGVmaW5pdGlvbiBIZWlnaHQ9IkF1dG8iIC8+CiAgICAgICAgICAgICAgICAgICAgPFJvd0RlZmluaXRpb24gSGVpZ2h0PSJBdXRvIiAvPgogICAgICAgICAgICAgICAgPC9HcmlkLlJvd0RlZmluaXRpb25zPgoKICAgICAgICAgICAgICAgIDwhLS0gQmFycmEgZGUgUHJvZ3Jlc3NvIGUgU3RhdHVzIC0tPgogICAgICAgICAgICAgICAgPEdyaWQgR3JpZC5Sb3c9IjAiIE1hcmdpbj0iMCwwLDAsOCI+CiAgICAgICAgICAgICAgICAgICAgPEdyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgICAgIDxDb2x1bW5EZWZpbml0aW9uIFdpZHRoPSIqIiAvPgogICAgICAgICAgICAgICAgICAgICAgICA8Q29sdW1uRGVmaW5pdGlvbiBXaWR0aD0iQXV0byIgLz4KICAgICAgICAgICAgICAgICAgICA8L0dyaWQuQ29sdW1uRGVmaW5pdGlvbnM+CiAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBOYW1lPSJsYmxQcm9ncmVzc1N0YXR1cyIgVGV4dD0iUHJvbnRvLiBTZWxlY2lvbmUgYXMgY29uZmlndXJhw6fDtWVzIGRlc2VqYWRhcyBuYXMgYWJhcyBhY2ltYS4iIEZvbnRTaXplPSIxMyIgRm9udFdlaWdodD0iU2VtaUJvbGQiIEZvcmVncm91bmQ9IiNDOEQzRjUiIFZlcnRpY2FsQWxpZ25tZW50PSJDZW50ZXIiIC8+CiAgICAgICAgICAgICAgICAgICAgPFRleHRCbG9jayBOYW1lPSJsYmxQcm9ncmVzc1BlcmNlbnQiIEdyaWQuQ29sdW1uPSIxIiBUZXh0PSIwJSIgRm9udFNpemU9IjEzIiBGb250V2VpZ2h0PSJCb2xkIiBGb3JlZ3JvdW5kPSIjN0RDRkZGIiBWZXJ0aWNhbEFsaWdubWVudD0iQ2VudGVyIiAvPgogICAgICAgICAgICAgICAgPC9HcmlkPgogICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICA8UHJvZ3Jlc3NCYXIgTmFtZT0icGJFeGVjdXRpb24iIEdyaWQuUm93PSIxIiBIZWlnaHQ9IjEwIiBNaW5pbXVtPSIwIiBNYXhpbXVtPSIxMDAiIEJhY2tncm91bmQ9IiMyNDI4M0IiIEZvcmVncm91bmQ9IiM3RENGRkYiIEJvcmRlclRoaWNrbmVzcz0iMCIgVmFsdWU9IjAiIC8+CiAgICAgICAgICAgIDwvR3JpZD4KICAgICAgICA8L0JvcmRlcj4KCiAgICA8L0dyaWQ+CjwvV2luZG93Pgo=
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
