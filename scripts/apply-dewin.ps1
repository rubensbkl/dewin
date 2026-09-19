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
    [ValidateSet('Full', 'Creator', 'Prompt')]
    [string]$Profile = 'Prompt',
    [switch]$NoRestart
)

# 1. Elevacao Administrativa
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '[!] Elevando permissoes para Administrador...' -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Profile $Profile" -Verb RunAs
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
    Write-Host '  [1] DEWIN Full (Dev + Criador + Jogos)' -ForegroundColor Green
    Write-Host '      -> Inclui WSL2, Hyper-V, Sandbox, Runtimes VC++, Chrome, 7-Zip e Tweaks.' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [2] DEWIN Creator & Gamer (Edicao 3D + Video + Jogos)' -ForegroundColor Cyan
    Write-Host '      -> Focado em Edicao (Premiere/DaVinci), 3D e Jogos (Sem WSL/Virtualizacao).' -ForegroundColor Gray
    Write-Host ''
    
    $selection = Read-Host 'Digite a opcao desejada [1 ou 2] (Padrao: 1)'
    if ($selection -eq '2') {
        $chosenProfile = 'dewin-creator.json'
        $profileName = 'Creator & Gamer'
    } else {
        $chosenProfile = 'dewin-full.json'
        $profileName = 'Full (Dev + Criador + Jogos)'
    }
} elseif ($Profile -eq 'Creator') {
    $chosenProfile = 'dewin-creator.json'
    $profileName = 'Creator & Gamer'
} else {
    $chosenProfile = 'dewin-full.json'
    $profileName = 'Full (Dev + Criador + Jogos)'
}

# 3. Localizar Arquivo de Perfil Selecionado
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
Write-Host ''

# 4. Invocacao do WinUtil Oficial com Perfil
Write-Host '[*] Conectando ao WinUtil oficial e aplicando configuracoes...' -ForegroundColor Yellow
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -Command "
        `$ProgressPreference = 'SilentlyContinue';
        `$winutilScript = Invoke-RestMethod -Uri 'https://christitus.com/win';
        [ScriptBlock]::Create(`$winutilScript).Invoke();
    "
} catch {
    Write-Host ('[AVISO] Falha ao carregar WinUtil via web: ' + $_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Certifique-se de estar conectado a internet.' -ForegroundColor Yellow
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
    }
}
