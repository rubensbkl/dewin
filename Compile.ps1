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
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}
$rootDir = $PSScriptRoot
if (-not $rootDir) { $rootDir = (Get-Location).Path }

Write-Host '[*] Compilando DEWIN Booster...' -ForegroundColor Cyan

$header = @'
# ==============================================================================
# DEWIN Booster - Universal Windows Optimizer & Debloater (Single-Script Edition)
# Execução via terminal:
# irm https://raw.githubusercontent.com/rubensbkl/dewin/main/dewin.ps1 | iex
# ==============================================================================

[CmdletBinding()]
param(
    [ValidateSet('Light', 'Medium', 'Aggressive', 'Dev', 'DesktopDev', 'DesktopGeral', 'LaptopDev', 'LaptopGeral', 'GUI')]
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
        Write-Host "  [+] Adicionando módulo: $relPath" -ForegroundColor Gray
        $content = Get-Content -LiteralPath $fullPath -Raw -Encoding UTF8
        [void]$body.AppendLine("# --- Módulo: $relPath ---")
        [void]$body.AppendLine($content)
        [void]$body.AppendLine()
    } else {
        Write-Warning "Módulo não encontrado: $fullPath"
    }
}

# 3. Embutir o XAML da Interface Gráfica (Base64 UTF-8 seguro contra distorções de codificação)
$xamlPath = Join-Path -Path $rootDir -ChildPath 'src\gui\MainWindow.xaml'
if (Test-Path $xamlPath) {
    Write-Host "  [+] Embutindo Interface Gráfica XAML (Base64 UTF-8)..." -ForegroundColor Gray
    $xamlBytes = [System.IO.File]::ReadAllBytes($xamlPath)
    $xamlBase64 = [System.Convert]::ToBase64String($xamlBytes)
    [void]$body.AppendLine("# --- Interface Gráfica XAML ---")
    [void]$body.AppendLine('$global:DewinXaml = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String(@''')
    [void]$body.AppendLine($xamlBase64)
    [void]$body.AppendLine('''@))')
    [void]$body.AppendLine()
} else {
    Write-Warning "XAML não encontrado: $xamlPath"
}

# 4. Entrypoint Principal
$entrypoint = @'
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
'@

[void]$body.AppendLine($entrypoint)

# 5. Gravação do Arquivo Final dewin.ps1 (UTF-8 SEM BOM para compatibilidade com irm | iex)
$outputFile = Join-Path -Path $rootDir -ChildPath 'dewin.ps1'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outputFile, $body.ToString(), $utf8NoBom)

$fileSizeKB = [math]::Round((Get-Item $outputFile).Length / 1KB, 1)
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " [OK] dewin.ps1 compilado com sucesso! ($fileSizeKB KB)" -ForegroundColor Green
Write-Host " Localização: $outputFile" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Green

if ($Run) {
    Write-Host "[*] Iniciando interface gráfica de teste..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$outputFile`""
}
