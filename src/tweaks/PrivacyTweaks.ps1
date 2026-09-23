# ==============================================================================
# DEWIN Tweaks: Privacidade, Telemetria & Debloat
# ==============================================================================

function Invoke-DewinPrivacyTweaks {
    [CmdletBinding()]
    param(
        [switch]$DisableTelemetry = $true,
        [switch]$DisableCeipTasks = $true,
        [switch]$DisableCopilotRecall = $true,
        [switch]$DisableBingSearch = $true,
        [switch]$DebloatEdge = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando ajustes de privacidade e desativando telemetria...'

    # Telemetria do Windows e Serviços de Diagnóstico
    if ($DisableTelemetry) {
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0

        @('DiagTrack', 'dmwappushservice') | ForEach-Object {
            try {
                Stop-Service -Name $_ -Force -ErrorAction SilentlyContinue | Out-Null
                Set-Service -Name $_ -StartupType Disabled -ErrorAction SilentlyContinue | Out-Null
            } catch {}
        }

        # Telemetria de Aplicativos e Coletor de Inventário
        $appCompatPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat'
        Set-DewinReg -Path $appCompatPol -Name 'AITEnable' -Value 0
        Set-DewinReg -Path $appCompatPol -Name 'DisableInventory' -Value 1

        # Conteúdo de Nuvem, Dicas do Windows e Bloqueio de Apps Patrocinados
        $cloudPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
        Set-DewinReg -Path $cloudPol -Name 'DisableCloudOptimizedContent' -Value 1
        Set-DewinReg -Path $cloudPol -Name 'DisableConsumerAccountStateContent' -Value 1
        Set-DewinReg -Path $cloudPol -Name 'DisableSoftLanding' -Value 1
        Set-DewinReg -Path $cloudPol -Name 'DisableWindowsConsumerFeatures' -Value 1

        $cdmPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        Set-DewinReg -Path $cdmPath -Name 'SubscribedContent-338389Enabled' -Value 0
        Set-DewinReg -Path $cdmPath -Name 'SubscribedContent-310093Enabled' -Value 0
        Set-DewinReg -Path $cdmPath -Name 'SystemPaneSuggestionsEnabled' -Value 0

        # Coleta de Dados de Fala e Escrita na Nuvem
        $speechPol = 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization'
        Set-DewinReg -Path $speechPol -Name 'AllowSpeechModelUpdate' -Value 0
        Set-DewinReg -Path $speechPol -Name 'RestrictImplicitInkCollection' -Value 1
        Set-DewinReg -Path $speechPol -Name 'RestrictImplicitTextCollection' -Value 1

        # Relatório de Erros do Windows (WER) e Despejo de Logs de Falhas
        $werPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
        Set-DewinReg -Path $werPol -Name 'Disabled' -Value 1
        Set-DewinReg -Path $werPol -Name 'LoggingDisabled' -Value 1
        Set-DewinReg -Path $werPol -Name 'DoReport' -Value 0

        # Sincronização de Configurações na Nuvem
        $syncPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\SettingSync'
        Set-DewinReg -Path $syncPol -Name 'DisableSettingSync' -Value 1
        Set-DewinReg -Path $syncPol -Name 'DisableSettingSyncUserOverride' -Value 1
    }

    # Desativação de Tarefas Agendadas Ociosas de Telemetria (CEIP)
    if ($DisableCeipTasks) {
        $tasksToDisable = @(
            '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
            '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
            '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
            '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
            '\Microsoft\Windows\Autochk\Proxy'
        )
        foreach ($task in $tasksToDisable) {
            try { Disable-ScheduledTask -TaskPath ($task | Split-Path) -TaskName ($task | Split-Path -Leaf) -ErrorAction SilentlyContinue | Out-Null } catch {}
        }
    }

    # Desativação de Copilot, IA Recall e Cortana
    if ($DisableCopilotRecall) {
        Set-DewinReg -Path 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' -Name 'TurnOffWindowsCopilot' -Value 1
        Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'ShowCopilotButton' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' -Name 'DisableAIDataAnalysis' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0
    }

    # Desativação do Bing e Sugestões na Pesquisa do Iniciar
    if ($DisableBingSearch) {
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Value 1
        Set-DewinReg -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0
    }

    # Debloat do Microsoft Edge (Mantém o WebView2 100% funcional)
    if ($DebloatEdge) {
        $edgePol = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
        Set-DewinReg -Path $edgePol -Name 'MetricsReportingEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'PersonalizationReportingEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'ShowHomeButton' -Value 0
        Set-DewinReg -Path $edgePol -Name 'HideFirstRunExperience' -Value 1
        Set-DewinReg -Path $edgePol -Name 'StartupBoostEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'BackgroundModeEnabled' -Value 0
        Set-DewinReg -Path $edgePol -Name 'PreventPreheating' -Value 1
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\Main' -Name 'AllowPrelaunch' -Value 0
        Set-DewinReg -Path 'HKLM:\SOFTWARE\Policies\Microsoft\MicrosoftEdge\TabPreloader' -Name 'AllowTabPreloading' -Value 0
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Telemetria, CEIP, Copilot, Bing e Edge otimizados.'
}

function Invoke-DewinDebloat {
    [CmdletBinding()]
    param()

    Write-DewinLog -Level STEP -Message '[*] Removendo 28 bloatwares UWP de terceiros e publicidade...'

    $bloatwareList = @(
        'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp',
        'Microsoft.Getstarted', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.MicrosoftSolitaireCollection',
        'Microsoft.People', 'Microsoft.Todos', 'Microsoft.WindowsFeedbackHub',
        'Microsoft.YourPhone', 'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo',
        'MicrosoftTeams', 'Clipchamp.Clipchamp', 'Microsoft.549981C3F5F10',
        'Microsoft.Microsoft3DViewer', 'Microsoft.MixedReality.Portal', 'Microsoft.SkypeApp',
        'Microsoft.GamingApp', 'Microsoft.Xbox.TCUI', 'Microsoft.XboxSpeechToTextOverlay',
        'SpotifyAB.SpotifyMusic', 'Disney.37853FC22B2CE', 'ByteDancePte.Ltd.TikTok',
        'Facebook.InstagramBeta', 'Amazon.com.AmazonPrimeVideo', 'Netflix.Netflix',
        'Microsoft.BingFinance'
    )

    $removedCount = 0
    $provisioned = @(try { Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue } catch { @() })
    $provLookup = @{}
    foreach ($p in $provisioned) {
        if ($p.DisplayName) { $provLookup[$p.DisplayName] = $p.PackageName }
    }

    foreach ($app in $bloatwareList) {
        try {
            $pkg = Get-AppxPackage -Name $app -AllUsers -ErrorAction SilentlyContinue
            if ($pkg) {
                $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Out-Null
                $removedCount++
            }
            if ($provLookup.ContainsKey($app)) {
                Remove-AppxProvisionedPackage -Online -PackageName $provLookup[$app] -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {}
    }

    Write-DewinLog -Level SUCCESS -Message "  [+] Limpeza de $removedCount bloatwares concluída."
}
