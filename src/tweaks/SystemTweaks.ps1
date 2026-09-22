# ==============================================================================
# DEWIN Tweaks: Sistema, GPU, Energia & Serviços
# ==============================================================================

function Invoke-DewinSystemTweaks {
    [CmdletBinding()]
    param(
        [bool]$IsLaptop = $false,
        [bool]$IsDev = $false,
        [int]$RamGB = 16,
        [switch]$CalibrateGpu = $true,
        [switch]$SmartHibernation = $true,
        [switch]$DisableReservedStorage = $true,
        [switch]$OptimizeSvcHost = $true,
        [switch]$EnableLongPaths = $true,
        [switch]$DisableLockScreen = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando calibrações de sistema, GPU e energia...'

    # Calibração de GPU (TdrDelay = 8s, TdrDdiDelay = 8s, HAGS = 2)
    if ($CalibrateGpu) {
        $gfxPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
        Set-DewinReg -Path $gfxPath -Name 'TdrDelay' -Value 8
        Set-DewinReg -Path $gfxPath -Name 'TdrDdiDelay' -Value 8
        Set-DewinReg -Path $gfxPath -Name 'HwSchMode' -Value 2
    }

    # Gerenciamento Inteligente de Hibernação e Energia
    if ($SmartHibernation) {
        if ($IsLaptop) {
            Write-DewinLog -Level STEP -Message '  [*] Configurando hibernação segura compacta para Notebook...'
            try {
                powercfg.exe /hibernate on 2>$null | Out-Null
                powercfg.exe /h /type reduced 2>$null | Out-Null
            } catch {}
        } else {
            Write-DewinLog -Level STEP -Message '  [*] Desativando hibernação para Desktop (recuperando espaço em disco SSD)...'
            try { powercfg.exe /hibernate off 2>$null | Out-Null } catch {}
        }
    }

    # Desativação de Armazenamento Reservado (~7 GB liberados de SSD)
    if ($DisableReservedStorage) {
        try { Set-WindowsReservedStorageState -State Disabled -ErrorAction SilentlyContinue | Out-Null } catch {}
    }

    # Calibração de SvcHost de acordo com a memória RAM
    if ($OptimizeSvcHost -and $RamGB -gt 0) {
        $svcThreshold = if ($RamGB -ge 32) { 33554432 } elseif ($RamGB -ge 16) { 16777216 } else { 8388608 }
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Value $svcThreshold
    }

    # Habilitação de Caminhos Longos no Sistema de Arquivos (MAX_PATH)
    if ($EnableLongPaths) {
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1
    }

    # Pular Tela de Bloqueio Estática e SCOOBE
    if ($DisableLockScreen) {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization' -Name 'NoLockScreen' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' -Name 'DisablePrivacyExperience' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\UserProfileEngagement' -Name 'ScoobeSystemSettingEnabled' -Value 0
    }

    # Tweaks Exclusivos para Perfil Desenvolvedor
    if ($IsDev) {
        # Relógio da Placa-Mãe em UTC (sincronização perfeita com Dual-Boot Linux)
        Set-DewinReg -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation' -Name 'RealTimeIsUniversal' -Value 1
        # Mensagens detalhadas de inicialização e desligamento
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'verbosestatus' -Value 1
        # Desativação de aviso repetitivo de RDP não assinado
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client' -Name 'RedirectionWarningDialogVersion' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Terminal Server Client' -Name 'RdpLaunchConsentAccepted' -Value 1
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Calibrações de sistema, GPU e energia aplicadas com sucesso.'
}
