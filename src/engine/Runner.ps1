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
