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
            'DesktopDev'   { 'Desktop Dev & Workstation: WSL2, Hyper-V, Sandbox, ferramentas Dev, sem hibernacao (recupera SSD).' }
            'DesktopGeral' { 'Desktop Geral & Jogos: Maxima leveza, menor latencia de rede e entrada, SSD liberado, sem virtualizacao.' }
            'LaptopDev'    { 'Notebook Dev & Workstation: WSL2, Hyper-V, Sandbox, ferramentas Dev, hibernacao segura compacta.' }
            'LaptopGeral'  { 'Notebook Geral & Jogos: Maxima autonomia de bateria e FPS, sem virtualizacao, hibernacao compacta.' }
        }
    }
}
