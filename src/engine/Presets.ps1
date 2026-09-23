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
        DualBootUtc             = [bool]$isAggressive
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
