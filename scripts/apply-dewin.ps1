<#
.SYNOPSIS
    DEWIN Post-Install Runner & System Booster (Universal Edition)
.DESCRIPTION
    Script orquestrador pós-instalação e booster do projeto DEWIN.
    Suporte unificado para Desktops e Notebooks através da matriz 2x2:
    - [1] Desktop Dev & Workstation (WSL2, Hyper-V, sem hibernação, foco em SSD e CPU)
    - [2] Desktop Geral, Jogos & Produtividade (Criador / Gamer, sem virtualização, sem hibernação)
    - [3] Notebook Dev & Workstation (Compatível com Nitro V 15, VivoBook e outros / hibernação segura)
    - [4] Notebook Geral, Jogos & Produtividade (Compatível com Nitro V 15, VivoBook e outros / bateria e hibernação segura)
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

# 2. Deteccao de Hardware e Perfil de Uso
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

$gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
$gpuNames = ($gpus | ForEach-Object { $_.Name }) -join ' | '
if (-not $gpuNames) { $gpuNames = 'Nao detectada' }

$hasNvidia = ($gpuNames -like '*NVIDIA*')
$isAcerNitro = ($model -like '*Nitro*' -or $model -like '*AN515*' -or $model -like '*ANV15*')
$isAsusVivoBook = ($model -like '*VivoBook*' -or $model -like '*X14*' -or $model -like '*X15*' -or $model -like '*K15*')
$isAsusLaptop = ($isDetectedLaptop -and ($manufacturer -like '*ASUS*' -or $model -like '*ASUS*'))

Write-Host '[*] Dispositivo Detectado: ' -NoNewline -ForegroundColor Cyan
Write-Host "$manufacturer $model " -NoNewline -ForegroundColor White
if ($isDetectedLaptop) {
    Write-Host '(Notebook / Portatil)' -ForegroundColor Green
} else {
    Write-Host '(Desktop / Estacao)' -ForegroundColor Green
}
Write-Host ('[*] GPU(s): ' + $gpuNames) -ForegroundColor Gray
Write-Host ''

$isLaptop = $isDetectedLaptop

if ($Profile -eq 'Prompt') {
    Write-Host 'Escolha o perfil desejado para esta maquina:' -ForegroundColor Yellow
    if ($isDetectedLaptop) {
        Write-Host '  [i] Hardware movel identificado! Recomendado: [3] para perfil Dev ou [4] para uso Geral/Jogos.' -ForegroundColor Magenta
    } else {
        Write-Host '  [i] Desktop identificado! Recomendado: [1] para perfil Dev ou [2] para uso Geral/Jogos.' -ForegroundColor Magenta
    }
    Write-Host ''
    Write-Host '  --- DESKTOPS ---' -ForegroundColor DarkGray
    Write-Host '  [1] Desktop — Dev & Workstation' -ForegroundColor Green
    Write-Host '      -> WSL2, Hyper-V, Sandbox, VC++, Chrome, 7-Zip, .NET, sem hibernacao (libera SSD).' -ForegroundColor Gray
    Write-Host '  [2] Desktop — Geral, Jogos & Produtividade' -ForegroundColor Cyan
    Write-Host '      -> Maxima leveza e FPS, sem virtualizacao, sem hibernacao (libera SSD).' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  --- NOTEBOOKS (Acer Nitro V 15, ASUS VivoBook, etc.) ---' -ForegroundColor DarkGray
    Write-Host '  [3] Notebook — Dev & Workstation' -ForegroundColor Green
    Write-Host '      -> WSL2, Hyper-V, Sandbox, ferramentas Dev, hibernacao segura compacta.' -ForegroundColor Gray
    Write-Host '  [4] Notebook — Geral, Jogos & Produtividade' -ForegroundColor Cyan
    Write-Host '      -> Maxima autonomia de bateria e FPS, sem virtualizacao, hibernacao segura compacta.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [5] Abrir Interface Visual do WinUtil (Ajuste Manual)' -ForegroundColor Magenta
    Write-Host '      -> Abre a tela grafica do WinUtil para inspecionar ou marcar manualmente.' -ForegroundColor Gray
    Write-Host ''
    
    $defaultOpt = if ($isDetectedLaptop) { '3' } else { '1' }
    $selection = Read-Host "Digite a opcao desejada [1 a 5] (Padrao: $defaultOpt)"
    if ([string]::IsNullOrWhiteSpace($selection)) { $selection = $defaultOpt }

    switch ($selection) {
        '2' {
            $chosenProfile = 'dewin-desktop-geral.json'
            $profileName = 'Desktop — Geral, Jogos & Produtividade'
            $runMode = 'Auto'
            $isLaptop = $false
        }
        '3' {
            $chosenProfile = 'dewin-laptop-dev.json'
            $profileName = 'Notebook — Dev & Workstation'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        '4' {
            $chosenProfile = 'dewin-laptop-geral.json'
            $profileName = 'Notebook — Geral, Jogos & Produtividade'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        '5' {
            $chosenProfile = $null
            $profileName = 'Interface Grafica Manual'
            $runMode = 'GUI'
            $isLaptop = $isDetectedLaptop
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
            $profileName = 'Desktop — Geral, Jogos & Produtividade'
            $runMode = 'Auto'
            $isLaptop = $false
        }
        'LaptopDev' {
            $chosenProfile = 'dewin-laptop-dev.json'
            $profileName = 'Notebook — Dev & Workstation'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        'LaptopGeral' {
            $chosenProfile = 'dewin-laptop-geral.json'
            $profileName = 'Notebook — Geral, Jogos & Produtividade'
            $runMode = 'Auto'
            $isLaptop = $true
        }
        'GUI' {
            $chosenProfile = $null
            $profileName = 'Interface Grafica Manual'
            $runMode = 'GUI'
            $isLaptop = $isDetectedLaptop
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

# 4. Calibracao Modular de Hardware, Energia & Compatibilidade
Write-Host ''
Write-Host '[*] Aplicando calibracao de hardware e compatibilidade...' -ForegroundColor Cyan

# 4.1. Calibracao GPU para DaVinci Resolve, Unreal Engine e Jogos
try {
    $gpuPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    if (-not (Test-Path $gpuPath)) { New-Item -Path $gpuPath -Force | Out-Null }
    Set-ItemProperty -Path $gpuPath -Name 'TdrDelay' -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $gpuPath -Name 'TdrDdiDelay' -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $gpuPath -Name 'HwSchMode' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host '  [+] GPU & Render: TdrDelay=8s, TdrDdiDelay=8s e HAGS calibrados.' -ForegroundColor Green
} catch {}

# 4.2. Gerenciamento de Energia e Bateria (Desktop vs. Notebook)
try {
    if ($isLaptop -or $isDetectedLaptop) {
        # Notebook: Garante hibernacao compacta para seguranca de bateria critica (< 3%) e sono na mochila
        powercfg /h on 2>$null
        powercfg /h /type reduced 2>$null
        Write-Host '  [+] Notebook: Hibernacao segura configurada em modo reduzido (type reduced ~3GB).' -ForegroundColor Green

        # Ativa porcentagem de bateria na barra de tarefas do Windows 11
        $taskbarPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Control Center'
        if (-not (Test-Path $taskbarPath)) { New-Item -Path $taskbarPath -Force | Out-Null }
        Set-ItemProperty -Path $taskbarPath -Name 'IsBatteryPercentageEnabled' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    } else {
        # Desktop: Desativa hibernacao para liberar 16 a 24 GB de SSD
        powercfg /h off 2>$null
        Write-Host '  [+] Desktop: Hibernacao desativada para recuperar espaco em SSD.' -ForegroundColor Green
    }
} catch {}

# 4.3. Compatibilidade para Hardwares Especificos (Acer Nitro, ASUS VivoBook, etc.)
try {
    # Suporte para Acer Nitro V 15 / Laptops Acer (preserva NitroSense e perfis dGPU)
    if ($isAcerNitro -or ($manufacturer -like '*Acer*' -and ($isLaptop -or $isDetectedLaptop))) {
        Write-Host '  [+] Acer Nitro / Laptop detectado: Preservando servicos termicos (NitroSense / Acer Care Center).' -ForegroundColor Green
        Get-Service -Name '*Acer*', '*Nitro*' -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic -ErrorAction SilentlyContinue
    }

    # Suporte para ASUS VivoBook / Laptops ASUS (preserva teclas Fn de atalho e protecao de bateria 80%)
    if ($isAsusVivoBook -or $isAsusLaptop) {
        Write-Host '  [+] ASUS VivoBook / Laptop detectado: Preservando ASUS System Control Interface (teclas Fn e protecao de bateria 80%).' -ForegroundColor Green
        Get-Service -Name 'AsusSysCap', 'ASUSLinkNear', 'ASUSOptimization', 'ASUSSoftwareManager' -ErrorAction SilentlyContinue | Set-Service -StartupType Automatic -ErrorAction SilentlyContinue
    }

    # Suporte para Desktop ASUS (ex: TUF B550M-PLUS)
    if (-not ($isLaptop -or $isDetectedLaptop) -and ($manufacturer -like '*ASUS*' -or $model -like '*TUF*')) {
        $smPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
        Set-ItemProperty -Path $smPath -Name 'DisableWpbtExecution' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
        Write-Host '  [+] ASUS Desktop: Bloqueio de injecao WPBT da BIOS (Armoury Crate) ativo.' -ForegroundColor Green
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
