<#
.SYNOPSIS
    DEWIN Post-Install Runner (Universal Open-Source Edition)
.DESCRIPTION
    Script orquestrador pós-instalação da Camada 2 do projeto DEWIN.
    Oferece perfis modulares para diferentes perfis de usuário:
    - [1] Full: Dev + Criador de Conteúdo + Jogos (WSL2, Hyper-V, Sandbox, Tweaks, Apps)
    - [2] Creator & Gamer: Edição de Vídeo + 3D Design + Jogos (Sem subsistema Linux)
.NOTES
    Projeto: DEWIN (Windows 11 Pro 25H2)
    Compatível com: AMD Ryzen (Zen 2/3/4/5), Intel Core (10ª-15ª Geração),
                    NVIDIA GeForce (GTX 10xx+, RTX), AMD Radeon (RX 5000+).
#>

[CmdletBinding()]
param(
    [ValidateSet('Full', 'Creator', 'GUI', 'Prompt')]
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
Write-Host '               DEWIN - OTIMIZADOR POS-INSTALACAO                  ' -ForegroundColor Cyan
Write-Host '         Universal Open-Source Edition | Windows 11 Pro           ' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host ''

# 2. Selecao de Perfil de Uso
if ($Profile -eq 'Prompt') {
    Write-Host 'Escolha o perfil desejado para esta maquina:' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  [1] DEWIN Full (Dev + Criador + Jogos) [Recomendado]' -ForegroundColor Green
    Write-Host '      -> Aplica automaticamente: WSL2, Hyper-V, Sandbox, VC++, Chrome, 7-Zip e Tweaks.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [2] DEWIN Creator & Gamer (Edicao 3D + Video + Jogos)' -ForegroundColor Cyan
    Write-Host '      -> Aplica automaticamente: Edicao (Premiere/DaVinci), 3D e Jogos (Sem virtualizacao).' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [3] Abrir interface visual do WinUtil (Ajuste Manual)' -ForegroundColor Magenta
    Write-Host '      -> Abre a tela grafica do WinUtil para inspecionar ou marcar manualmente.' -ForegroundColor Gray
    Write-Host ''
    
    $selection = Read-Host 'Digite a opcao desejada [1, 2 ou 3] (Padrao: 1)'
    if ($selection -eq '2') {
        $chosenProfile = 'dewin-creator.json'
        $profileName = 'Creator & Gamer'
        $runMode = 'Auto'
    } elseif ($selection -eq '3') {
        $chosenProfile = $null
        $profileName = 'Interface Grafica Manual'
        $runMode = 'GUI'
    } else {
        $chosenProfile = 'dewin-full.json'
        $profileName = 'Full (Dev + Criador + Jogos)'
        $runMode = 'Auto'
    }
} elseif ($Profile -eq 'Creator') {
    $chosenProfile = 'dewin-creator.json'
    $profileName = 'Creator & Gamer'
    $runMode = 'Auto'
} elseif ($Profile -eq 'GUI') {
    $chosenProfile = $null
    $profileName = 'Interface Grafica Manual'
    $runMode = 'GUI'
} else {
    $chosenProfile = 'dewin-full.json'
    $profileName = 'Full (Dev + Criador + Jogos)'
    $runMode = 'Auto'
}

# 3. Localizar Arquivo de Perfil Selecionado
$tempProfilePath = $null
if ($runMode -eq 'Auto') {
    $profilePath = Join-Path -Path $PSScriptRoot -ChildPath ("..\winutil\" + $chosenProfile)
    if (-not (Test-Path -Path $profilePath)) {
        # Fallback para dewin.json
        $profilePath = Join-Path -Path $PSScriptRoot -ChildPath '..\winutil\dewin.json'
    }

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

    # Gera arquivo de perfil temporario filtrado para o WinUtil
    $tempProfilePath = Join-Path -Path $env:TEMP -ChildPath ("dewin-run-" + [System.Guid]::NewGuid().ToString().Substring(0,8) + ".json")
    $profileData | ConvertTo-Json | Set-Content -Path $tempProfilePath
    $resolvedProfile = $tempProfilePath

    Write-Host '[*] O WinUtil aplicara todas as configuracoes do perfil automaticamente.' -ForegroundColor Cyan
    Write-Host ''
} else {
    $resolvedProfile = $null
    Write-Host ''
    Write-Host '[OK] Modo selecionado: Interface Grafica (Manual)' -ForegroundColor Green
    Write-Host 'Dica: Para carregar o perfil visualmente na janela, clique na engrenagem no canto superior direito e selecione Import Configuration.' -ForegroundColor Yellow
    Write-Host ''
}

# 4. Invocacao do WinUtil Oficial com Perfil
Write-Host '[*] Conectando ao WinUtil oficial...' -ForegroundColor Yellow
try {
    $winutilWorker = {
        param($profileToLoad, $isAuto)
        $ProgressPreference = 'SilentlyContinue'
        $winutilScript = Invoke-RestMethod -Uri 'https://christitus.com/win'
        $scriptBlock = [ScriptBlock]::Create($winutilScript)
        if ($isAuto -and $profileToLoad) {
            Write-Host '[*] Aplicando configuracoes e pacotes via WinUtil...' -ForegroundColor Green
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
