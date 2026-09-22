# ==============================================================================
# DEWIN Tweaks: Desempenho, Latência, Jogos e SSD
# ==============================================================================

function Invoke-DewinPerformanceTweaks {
    [CmdletBinding()]
    param(
        [switch]$OptimizeNetworkLatency = $true,
        [switch]$DisableGameDVR = $true,
        [switch]$LinearMouse = $true,
        [switch]$DisableStickyKeys = $true,
        [switch]$InstantMenuDelay = $true,
        [switch]$OptimizeSsdAccess = $true,
        [switch]$CleanTempFiles = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando otimizações de desempenho, latência e SSD...'

    # Latência de Rede e Priorização Multimídia/Jogos
    if ($OptimizeNetworkLatency) {
        $mmPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
        Set-DewinReg -Path $mmPath -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type 'DWord'
        Set-DewinReg -Path $mmPath -Name 'SystemResponsiveness' -Value 0 -Type 'DWord'
    }

    # Desativação de GameDVR e Captura em Segundo Plano
    if ($DisableGameDVR) {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' -Name 'AllowGameDVR' -Value 0
        Set-DewinReg -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -Value 0
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'HistoricalCaptureEnabled' -Value 0
    }

    # Resposta Linear do Mouse (1:1 sem aceleração)
    if ($LinearMouse) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -Value '0' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold1' -Value '0' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseThreshold2' -Value '0' -Type 'String'
    }

    # Desativação do popup irritante de Teclas de Aderência (Shift 5x)
    if ($DisableStickyKeys) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value '506' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value '122' -Type 'String'
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value '58' -Type 'String'
    }

    # Eliminação do atraso artificial de menus suspensos (MenuShowDelay = 0ms)
    if ($InstantMenuDelay) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value '0' -Type 'String'
    }

    # Otimização de SSD (Desativar timestamp de último acesso desnecessário)
    if ($OptimizeSsdAccess) {
        try { fsutil.exe behavior set disablelastaccess 1 2>$null | Out-Null } catch {}
    }

    # Limpeza de Pastas Temporárias
    if ($CleanTempFiles) {
        Remove-Item -Path "$Env:Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$Env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Desempenho, latência de rede, GameDVR e SSD calibrados.'
}
