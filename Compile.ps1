<#
.SYNOPSIS
    Compilador do DEWIN Booster (Universal Single-Script Builder)
.DESCRIPTION
    Combina os módulos modulares de src/ (Core, Tweaks, Packages, Engine e GUI XAML)
    em um único artefato distribuível e autônomo: dewin.ps1.
.PARAMETER Run
    Executa a interface gráfica recém-compilada imediatamente para teste local.
#>

[CmdletBinding()]
param(
    [switch]$Run
)

$ErrorActionPreference = 'Stop'
$rootDir = $PSScriptRoot
if (-not $rootDir) { $rootDir = (Get-Location).Path }

Write-Host '[*] Compilando DEWIN Booster...' -ForegroundColor Cyan

# 1. Cabeçalho e Auto-Elevação UAC
$header = @'
<#
.SYNOPSIS
    DEWIN Booster - Universal Windows Optimizer & Debloater (Single-Script Edition)
.DESCRIPTION
    Script autônomo, 100% nativo em PowerShell com interface gráfica moderna em WPF.
    Pode ser executado com 1 comando via terminal:
    irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex
.NOTES
    Projeto: DEWIN (Universal Open-Source Edition)
#>

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
    Write-Host '[!] Privilegios de Administrador necessarios. Elevando via UAC...' -ForegroundColor Yellow
    $argsToPass = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($PSCommandPath) {
        $argsToPass += @('-File', $PSCommandPath, '-Profile', $Profile)
        if ($Silent) { $argsToPass += '-Silent' }
        if ($NoRestart) { $argsToPass += '-NoRestart' }
    } else {
        $rawUrl = 'https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1'
        $argsToPass += @('-Command', "irm $rawUrl | iex")
    }
    try {
        Start-Process powershell.exe -ArgumentList $argsToPass -Verb RunAs
        exit 0
    } catch {
        Write-Host "Falha ao elevar privilegios: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

'@

# 2. Leitura dos Módulos em src/
$modulesOrder = @(
    'src\core\Logger.ps1',
    'src\core\Registry.ps1',
    'src\core\Hardware.ps1',
    'src\tweaks\InterfaceTweaks.ps1',
    'src\tweaks\PerformanceTweaks.ps1',
    'src\tweaks\PrivacyTweaks.ps1',
    'src\tweaks\SystemTweaks.ps1',
    'src\packages\SoftwareInstaller.ps1',
    'src\packages\WindowsFeatures.ps1',
    'src\engine\Presets.ps1',
    'src\engine\Runner.ps1',
    'src\engine\Controller.ps1'
)

$body = [System.Text.StringBuilder]::new()
[void]$body.AppendLine($header)

foreach ($relPath in $modulesOrder) {
    $fullPath = Join-Path -Path $rootDir -ChildPath $relPath
    if (Test-Path $fullPath) {
        Write-Host "  [+] Adicionando modulo: $relPath" -ForegroundColor Gray
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        [void]$body.AppendLine("# --- Modulo: $relPath ---")
        [void]$body.AppendLine($content)
        [void]$body.AppendLine()
    } else {
        Write-Warning "Modulo nao encontrado: $fullPath"
    }
}

# 3. Embutir o XAML da Interface Gráfica
$xamlPath = Join-Path -Path $rootDir -ChildPath 'src\gui\MainWindow.xaml'
if (Test-Path $xamlPath) {
    Write-Host "  [+] Embutindo Interface Grafica XAML..." -ForegroundColor Gray
    $xamlContent = Get-Content -LiteralPath $xamlPath -Raw -Encoding UTF8
    [void]$body.AppendLine("# --- Interface Grafica XAML ---")
    [void]$body.AppendLine('$global:DewinXaml = @''')
    [void]$body.AppendLine($xamlContent)
    [void]$body.AppendLine('''@')
    [void]$body.AppendLine()
} else {
    Write-Warning "XAML nao encontrado: $xamlPath"
}

# 4. Entrypoint Principal
$entrypoint = @'
# ==============================================================================
# DEWIN Entrypoint Principal
# ==============================================================================
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
'@

[void]$body.AppendLine($entrypoint)

# 5. Gravacao do Arquivo Final dewin.ps1
$outputFile = Join-Path -Path $rootDir -ChildPath 'dewin.ps1'
[System.IO.File]::WriteAllText($outputFile, $body.ToString(), [System.Text.Encoding]::UTF8)

$fileSizeKB = [math]::Round((Get-Item $outputFile).Length / 1KB, 1)
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " [OK] dewin.ps1 compilado com sucesso! ($fileSizeKB KB)" -ForegroundColor Green
Write-Host " Localizacao: $outputFile" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Green

if ($Run) {
    Write-Host "[*] Iniciando interface grafica de teste..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$outputFile`""
}
