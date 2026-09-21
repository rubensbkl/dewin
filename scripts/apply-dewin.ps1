<#
.SYNOPSIS
    DEWIN Post-Install Runner & System Booster (Universal Edition)
.DESCRIPTION
    Script orquestrador pós-instalação e booster do projeto DEWIN.
    Suporte unificado para Desktops e Notebooks através da matriz 2x2:
    - [1] Desktop Dev & Workstation (WSL2, Hyper-V, sem hibernação, foco em SSD e CPU)
    - [2] Desktop Geral & Jogos (Criador / Gamer, sem virtualização, sem hibernação)
    - [3] Notebook Dev & Performance (Acer Nitro V 15 / dGPU, hibernação segura)
    - [4] Notebook Geral & Produtividade (ASUS VivoBook / Bateria, hibernação segura)
    - [5] Interface Gráfica do WinUtil (Ajuste Manual)
.NOTES
    Projeto: DEWIN (Windows 11 Pro 25H2)
#>

[CmdletBinding()]
param(
    [ValidateSet('DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral', 'GUI', 'Prompt')]
    [string]$Profile = 'Prompt',
    [switch]$NoRestart
)

# 1. Elevacao Administrativa
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Elevando permissoes para Administrador...' -ForegroundColor Yellow
    Start-Process powershell.exe -WorkingDirectory $PSScriptRoot -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Profile $Profile" -Verb RunAs
    exit
}

Clear-Host
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host '               DEWIN - OTIMIZADOR & BOOSTER DO SISTEMA             ' -ForegroundColor Cyan
Write-Host '         Universal Open-Source Edition | Windows 11 Pro           ' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host ''

# 2. Selecao de Perfil de Uso (Matriz 2x2)
$isLaptop = $false

if ($Profile -eq 'Prompt') {
    Write-Host 'Escolha o perfil para esta maquina:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  --- DESKTOPS ---' -ForegroundColor DarkGray
    Write-Host '  [1] Desktop — Dev & Workstation' -ForegroundColor Green
    Write-Host '      -> WSL2, Hyper-V, Sandbox, VC++, Chrome, 7-Zip, .NET, sem hibernacao.' -ForegroundColor Gray
    Write-Host '  [2] Desktop — Geral & Jogos (Criador / Gamer)' -ForegroundColor Cyan
    Write-Host '      -> Maxima leveza e FPS, sem virtualizacao, sem hibernacao (libera SSD).' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  --- NOTEBOOKS ---' -ForegroundColor DarkGray
    Write-Host '  [3] Notebook — Dev & Performance (ex: Acer Nitro V 15 / dGPU)' -ForegroundColor Green
    Write-Host '      -> WSL2, Hyper-V, GPU calibrada, bateria com hibernacao segura compacta.' -ForegroundColor Gray
    Write-Host '  [4] Notebook — Geral & Produtividade (ex: ASUS VivoBook / Bateria)' -ForegroundColor Cyan
    Write-Host '      -> Maxima autonomia de bateria, sem virtualizacao, hibernacao segura.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [5] Abrir Interface Visual do WinUtil (Ajuste Manual)' -ForegroundColor Magenta
    Write-Host '      -> Abre a tela grafica do WinUtil para inspecionar ou marcar manualmente.' -ForegroundColor Gray
    Write-Host ''
    
    $selection = Read-Host 'Digite a opcao desejada [1 a 5] (Padrao: 1)'
    switch ($selection) {
        '2' {
            $chosenProfile = 'dewin-desktop-geral.json'
            $profileName = 'Desktop — Geral & Jogos'
            $runMode = 'Auto'
            $isLaptop = $false
        }
        '3' {
            $chosenProfile = 'dewin-laptop-dev.json'
            $profileName = 'Notebook — Dev & Performance (Nitro V 15)'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        '4' {
            $chosenProfile = 'dewin-laptop-geral.json'
            $profileName = 'Notebook — Geral & Produtividade (VivoBook)'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        '5' {
            $chosenProfile = $null
            $profileName = 'Interface Grafica Manual'
            $runMode = 'GUI'
            $isLaptop = $false
        }
        Default {
            $chosenProfile = 'dewin-desktop-dev.json'
            $profileName = 'Desktop — Dev & Workstation'
            $runMode = 'Auto'
            $isLaptop = $false
        }
    }
} else {
    switch ($Profile) {
        'DesktopGeral' {
            $chosenProfile = 'dewin-desktop-geral.json'
            $profileName = 'Desktop — Geral & Jogos'
            $runMode = 'Auto'
            $isLaptop = $false
        }
        'LaptopDev' {
            $chosenProfile = 'dewin-laptop-dev.json'
            $profileName = 'Notebook — Dev & Performance (Nitro V 15)'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        'LaptopGeral' {
            $chosenProfile = 'dewin-laptop-geral.json'
            $profileName = 'Notebook — Geral & Produtividade (VivoBook)'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        'GUI' {
            $chosenProfile = $null
            $profileName = 'Interface Grafica Manual'
            $runMode = 'GUI'
            $isLaptop = $false
        }
        Default {
            $chosenProfile = 'dewin-desktop-dev.json'
            $profileName = 'Desktop — Dev & Workstation'
            $runMode = 'Auto'
            $isLaptop = $false
        }
    }
}

# 3. Localizar Arquivo de Perfil Selecionado
$tempProfilePath = $null
if ($runMode -eq 'Auto') {
    $profilePath = Join-Path -Path $PSScriptRoot -ChildPath ("..\winutil\" + $chosenProfile)

    if (-not (Test-Path -Path $profilePath)) {
        Write-Host ('[ERRO] Arquivo de perfil nao encontrado: ' + $profilePath) -ForegroundColor Red
        pause
        exit 1
    }

    $resolvedProfile = (Resolve-Path -Path $profilePath).Path
    Write-Host ''
    Write-Host ('[OK] Perfil selecionado: ' + $profileName) -ForegroundColor Green
    Write-Host ('[OK] Arquivo carregado: ' + $resolvedProfile) -ForegroundColor Gray

    # Verificacao de Espaco em Disco
    $driveC = Get-PSDrive C -ErrorAction SilentlyContinue
    $freeGB = if ($driveC) { [math]::Round($driveC.Free / 1GB, 1) } else { 0 }
    Write-Host ''
    if ($freeGB -gt 0) {
        $color = if ($freeGB -lt 35) { 'Yellow' } else { 'Cyan' }
        Write-Host ('[*] Espaco livre em C: ' + $freeGB + ' GB') -ForegroundColor $color
    }

    # Ponto de Restauracao
    Write-Host 'Criar Ponto de Restauracao do Windows antes de aplicar?' -ForegroundColor Yellow
    Write-Host '  -> Recomendado escolher [N] caso tenha pouco espaco livre (< 40 GB) ou o servico VSS trave.' -ForegroundColor Gray
    $askRestore = Read-Host 'Deseja criar Ponto de Restauracao? (S/N) [Padrao: N]'
    $createRestorePoint = ($askRestore -match '^[sSyY]')

    $profileData = Get-Content -Path $resolvedProfile | ConvertFrom-Json
    if (-not $createRestorePoint) {
        $profileData = @($profileData | Where-Object { $_ -ne 'WPFTweaksRestorePoint' })
        Write-Host '[*] Ponto de Restauracao ignorado. Indo direto para as otimizacoes.' -ForegroundColor Yellow
    } else {
        Write-Host '[*] Ponto de Restauracao ativado.' -ForegroundColor Green
    }

    # Gera arquivo temporario com o perfil
    $tempProfilePath = Join-Path -Path $env:TEMP -ChildPath ("dewin-run-" + [System.Guid]::NewGuid().ToString().Substring(0,8) + ".json")
    $profileData | ConvertTo-Json | Set-Content -Path $tempProfilePath
    $resolvedProfile = $tempProfilePath
} else {
    $resolvedProfile = $null
    Write-Host ''
    Write-Host '[OK] Modo selecionado: Interface Grafica (Manual)' -ForegroundColor Green
    Write-Host 'Dica: Para carregar o perfil visualmente, use Import Configuration nas configuracoes do WinUtil.' -ForegroundColor Yellow
    Write-Host ''
}

# 4. Calibracao de Hardware & Bateria (Desktop vs. Notebook)
Write-Host ''
Write-Host '[*] Calibrando parametros de hardware e energia...' -ForegroundColor Cyan

# 4.1. Calibracao GPU para DaVinci Resolve, Unreal Engine e Jogos
try {
    $gpuPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    if (-not (Test-Path $gpuPath)) { New-Item -Path $gpuPath -Force | Out-Null }
    Set-ItemProperty -Path $gpuPath -Name 'TdrDelay' -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $gpuPath -Name 'TdrDdiDelay' -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $gpuPath -Name 'HwSchMode' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
} catch {}

# 4.2. Gerenciamento de Energia e Bateria
try {
    if ($isLaptop) {
        # Notebook: Garante hibernacao compacta para seguranca de bateria critica (< 3%) e sono na mochila
        powercfg /h on 2>$null
        powercfg /h /type reduced 2>$null
        Write-Host '  [+] Notebook: Hibernacao segura configurada em modo reduzido (type reduced ~3GB).' -ForegroundColor Green
    } else {
        # Desktop: Desativa hibernacao para liberar 16 a 24 GB de SSD
        powercfg /h off 2>$null
        Write-Host '  [+] Desktop: Hibernacao desativada para recuperar espaco em SSD.' -ForegroundColor Green
    }
} catch {}

# 5. Debloat Cirurgico de Bloatware Nativo (28 aplicativos)
Write-Host ''
Write-Host '[*] Aplicando debloat cirurgico (preservando Store, Calculadora, Notepad e Paint)...' -ForegroundColor Cyan

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

foreach ($pkg in $bloatwarePackages) {
    Get-AppxPackage -Name $pkg -ErrorAction SilentlyContinue | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $pkg } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
}
Write-Host '[+] Limpeza de bloatware concluida com sucesso.' -ForegroundColor Green

# 6. Execucao do WinUtil Oficial com Perfil
Write-Host ''
Write-Host '[*] Conectando ao WinUtil oficial...' -ForegroundColor Cyan

try {
    $winutilWorker = {
        param($profileToLoad, $isAuto)
        $ProgressPreference = 'SilentlyContinue'
        $winutilScript = Invoke-RestMethod -Uri 'https://christitus.com/win'
        $scriptBlock = [ScriptBlock]::Create($winutilScript)
        if ($isAuto -and $profileToLoad) {
            Write-Host '[*] Aplicando configuracoes, servicos e pacotes via WinUtil...' -ForegroundColor Green
            & $scriptBlock -Config $profileToLoad
        } else {
            & $scriptBlock
        }
    }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $winutilWorker -args $resolvedProfile, ($runMode -eq 'Auto')
} catch {
    Write-Host ('[AVISO] Falha ao executar WinUtil: ' + $_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Certifique-se de estar conectado a internet.' -ForegroundColor Yellow
} finally {
    if ($tempProfilePath -and (Test-Path -Path $tempProfilePath)) {
        Remove-Item -Path $tempProfilePath -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Green
Write-Host '               ETAPA POS-INSTALACAO FINALIZADA!                   ' -ForegroundColor Green
Write-Host '==================================================================' -ForegroundColor Green
Write-Host ''
Write-Host 'Recomenda-se reiniciar o computador para que todas as alteracoes' -ForegroundColor Cyan
Write-Host 'entrem completamente em vigor.' -ForegroundColor Cyan
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
