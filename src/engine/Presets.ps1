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
            'DesktopDev'   { 'Desktop - Desenvolvimento: WSL2, Hyper-V, Sandbox, ferramentas essenciais, sem hibernação (liberação de espaço em SSD).' }
            'DesktopGeral' { 'Desktop - Geral e Jogos: Otimização de desempenho, menor latência de rede e entrada, espaço em SSD liberado, sem virtualização ativa.' }
            'LaptopDev'    { 'Notebook - Desenvolvimento: WSL2, Hyper-V, Sandbox, ferramentas essenciais, hibernação compacta com preservação de energia.' }
            'LaptopGeral'  { 'Notebook - Geral e Autonomia: Eficiência energética aprimorada, maior autonomia de bateria, sem virtualização ativa, hibernação compacta.' }
        }
    }
}
