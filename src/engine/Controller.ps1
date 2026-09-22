# ==============================================================================
# DEWIN Engine: Controlador da Interface Gráfica (WPF)
# ==============================================================================

function New-DewinSessionState {
    param([hashtable]$SyncHashtable)
    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

    $builtInFunctions = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($iss.Commands |
            Where-Object { $_ -is [System.Management.Automation.Runspaces.SessionStateFunctionEntry] } |
            ForEach-Object { $_.Name }),
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($func in (Get-ChildItem function:\)) {
        if (-not $builtInFunctions.Contains($func.Name)) {
            $iss.Commands.Add(
                (New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $func.Name, $func.Definition)
            )
        }
    }

    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'sync', $SyncHashtable, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinSync', $SyncHashtable, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinLogPath', $global:DewinLogPath, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinLatestLog', $global:DewinLatestLog, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinTimer', $global:DewinTimer, $null))
    $iss.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DewinStats', $global:DewinStats, $null))

    return $iss
}

function Start-DewinGui {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$XamlString,
        [PSCustomObject]$Hardware
    )

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

    if (-not $Hardware) {
        $Hardware = Get-DewinHardwareInfo
    }

    # Carregamento do XAML
    $reader = [System.Xml.XmlReader]::Create([System.IO.StringReader]::new($XamlString))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # Mapeamento dinâmico de elementos por Nome
    $global:DewinGui = @{}
    $xmlDoc = [xml]$XamlString
    $xmlDoc.SelectNodes('//*[@Name]') | ForEach-Object {
        $name = $_.GetAttribute('Name')
        $global:DewinGui[$name] = $window.FindName($name)
    }
    $gui = $global:DewinGui

    # 1. Preenchimento dos Dados de Hardware
    $gui['txtHardwareBanner'].Text = "Dispositivo: $($Hardware.Manufacturer) $($Hardware.Model) | CPU: $($Hardware.Processor) | RAM: $($Hardware.RamTotalGB) GB | GPU: $($Hardware.GpuNames)"
    $gui['txtDeviceType'].Text = "$($Hardware.DeviceTypeStr) Detectado"

    $recText = if ($Hardware.IsLaptop) {
        "💡 Notebook identificado! Recomendamos o Perfil [3] Notebook Dev (se for programador) ou [4] Notebook Geral (para máxima autonomia de bateria e jogos)."
    } else {
        "💡 Desktop identificado! Recomendamos o Perfil [1] Desktop Dev (se for programador) ou [2] Desktop Geral / Jogos (para máxima taxa de FPS e menor latência)."
    }
    $gui['txtRecommendation'].Text = $recText

    # 2. Listas de Controles
    $allTweakChecks = @(
        'chkHideSearch', 'chkHideTaskView', 'chkCenterTaskbar', 'chkTaskbarEndTask',
        'chkClassicContextMenu', 'chkLaunchToThisPC', 'chkShowExtensionsAndHidden', 'chkAlwaysShowScrollbars',
        'chkOptimizeNetworkLatency', 'chkDisableGameDVR', 'chkLinearMouse', 'chkDisableStickyKeys',
        'chkInstantMenuDelay', 'chkOptimizeSsdAccess', 'chkCleanTempFiles',
        'chkDisableTelemetry', 'chkDisableCeipTasks', 'chkDisableCopilotRecall', 'chkDisableBingSearch',
        'chkDebloatEdge', 'chkRemoveUwpBloat',
        'chkCalibrateGpu', 'chkSmartHibernation', 'chkDisableReservedStorage', 'chkOptimizeSvcHost',
        'chkEnableLongPaths', 'chkDisableLockScreen', 'chkIsDev'
    )

    $allAppChecks = @(
        'appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome',
        'appVsCode', 'appGit', 'appDiscord', 'appSteam', 'appVlc', 'appSpotify'
    )

    $allFeatChecks = @(
        'featNetFx3', 'featWsl', 'featVmPlatform', 'featHyperV', 'featSandbox'
    )

    $appMap = @{
        'appVcRedist64' = 'Microsoft.VCRedist.2015+.x64'
        'appVcRedist86' = 'Microsoft.VCRedist.2015+.x86'
        'app7zip'       = '7zip.7zip'
        'appChrome'     = 'Google.Chrome'
        'appVsCode'     = 'Microsoft.VisualStudioCode'
        'appGit'        = 'Git.Git'
        'appDiscord'    = 'Discord.Discord'
        'appSteam'      = 'Valve.Steam'
        'appVlc'        = 'VideoLAN.VLC'
        'appSpotify'    = 'Spotify.Spotify'
    }

    $featMap = @{
        'featNetFx3'      = 'NetFx3'
        'featWsl'         = 'Microsoft-Windows-Subsystem-Linux'
        'featVmPlatform'  = 'VirtualMachinePlatform'
        'featHyperV'      = 'Microsoft-Hyper-V-All'
        'featSandbox'     = 'Containers-DisposableClientVM'
    }

    # 3. Funcao de Aplicacao de Perfil
    $applyPresetToGui = {
        param([string]$PresetName)
        $preset = Get-DewinPreset -Name $PresetName

        foreach ($chkName in $allTweakChecks) {
            $tweakKey = $chkName.Substring(3)
            if ($preset.Tweaks.Contains($tweakKey) -and $gui[$chkName]) {
                $gui[$chkName].IsChecked = [bool]$preset.Tweaks[$tweakKey]
            }
        }

        foreach ($k in $appMap.Keys) {
            if ($gui[$k]) { $gui[$k].IsChecked = ($preset.Apps -contains $appMap[$k]) }
        }

        foreach ($k in $featMap.Keys) {
            if ($gui[$k]) { $gui[$k].IsChecked = ($preset.Features -contains $featMap[$k]) }
        }

        $gui['lblProgressStatus'].Text = "Perfil '$PresetName' selecionado nas abas de otimizações e softwares."
    }

    # 4. Vinculação dos Botões de Perfis Rápidos (Aba 2: Otimizações)
    $gui['btnPresetDesktopDev'].Add_Click({ & $applyPresetToGui 'DesktopDev' })
    $gui['btnPresetDesktopGeral'].Add_Click({ & $applyPresetToGui 'DesktopGeral' })
    $gui['btnPresetLaptopDev'].Add_Click({ & $applyPresetToGui 'LaptopDev' })
    $gui['btnPresetLaptopGeral'].Add_Click({ & $applyPresetToGui 'LaptopGeral' })

    # Botões de Seleção de Tweaks (Aba 2)
    $gui['btnSelectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
    })
    $gui['btnDeselectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    })
    $gui['btnResetRecommended'].Add_Click({
        & $applyPresetToGui $Hardware.RecommendedProfile
    })

    # Botões de Seleção de Softwares (Aba 1)
    $gui['btnSelectEssentialApps'].Add_Click({
        $essentialIds = @('appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome')
        foreach ($c in $allAppChecks) {
            if ($gui[$c]) { $gui[$c].IsChecked = ($essentialIds -contains $c) }
        }
        $gui['lblProgressStatus'].Text = "Softwares essenciais (VC++, 7-Zip, Chrome) selecionados."
    })
    $gui['btnSelectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
    })
    $gui['btnDeselectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    })

    # Botões de Utilidades de Log (Aba 4)
    $gui['btnOpenLogFolder'].Add_Click({
        $logDir = if ($global:DewinLogPath) {
            Split-Path -Path $global:DewinLogPath
        } elseif ($PSScriptRoot) {
            Join-Path $PSScriptRoot 'logs'
        } else {
            "$env:LOCALAPPDATA\dewin\logs"
        }
        if (-not (Test-Path $logDir)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        Start-Process explorer.exe $logDir
    })

    $gui['btnClearLogConsole'].Add_Click({
        $gui['txtConsoleLog'].Text = "[$(Get-Date -Format 'HH:mm:ss')] Console de logs limpo."
    })

    # Inicializa com o perfil recomendado pré-marcado
    & $applyPresetToGui $Hardware.RecommendedProfile

    # 5. Executador Assíncrono com UI Responsiva (Thread-Safe)
    $allActionButtons = @(
        'btnInstallSoftwares', 'btnApplyOptimizations', 'btnEnableFeatures',
        'btnSelectEssentialApps', 'btnSelectAllApps', 'btnDeselectAllApps',
        'btnSelectAll', 'btnDeselectAll', 'btnResetRecommended',
        'btnPresetDesktopDev', 'btnPresetDesktopGeral', 'btnPresetLaptopDev', 'btnPresetLaptopGeral'
    )

    $runDewinAsync = {
        param(
            [string]$ActionTitle,
            [scriptblock]$TaskScriptBlock,
            [array]$TaskArgs,
            [scriptblock]$OnCompleted
        )

        foreach ($btn in $allActionButtons) {
            if ($gui[$btn]) { $gui[$btn].IsEnabled = $false }
        }

        # Muda imediatamente para a aba de Log para visualização em tempo real
        if ($gui['mainTabControl'] -and $gui['tabItemLog']) {
            $gui['mainTabControl'].SelectedItem = $gui['tabItemLog']
        }
        $gui['txtConsoleLog'].AppendText("`r`n`r`n[$(Get-Date -Format 'HH:mm:ss')] Iniciando: $ActionTitle...")

        $global:DewinSync = [hashtable]::Synchronized(@{
            Percent  = 0
            Status   = "Iniciando $ActionTitle..."
            Messages = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            IsDone   = $false
            Error    = $null
        })

        $iss = New-DewinSessionState -SyncHashtable $global:DewinSync
        $runspace = [runspacefactory]::CreateRunspace($iss)
        $runspace.Open()

        $psAsync = [powershell]::Create()
        $psAsync.Runspace = $runspace
        $psAsync.AddScript($TaskScriptBlock) | Out-Null
        foreach ($arg in $TaskArgs) {
            $psAsync.AddArgument($arg) | Out-Null
        }

        $asyncResult = $psAsync.BeginInvoke()

        $uiTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $uiTimer.Interval = [TimeSpan]::FromMilliseconds(100)

        $tickAction = {
            $ui = if ($global:DewinGui) { $global:DewinGui } elseif ($gui) { $gui } else { $null }
            if (-not $ui) { return }

            $s = if ($global:DewinSync) { $global:DewinSync } elseif ($sync) { $sync } else { $null }
            if (-not $s) { return }

            $pct = [int]$s.Percent
            if ($pct -lt 0) { $pct = 0 }
            if ($pct -gt 100) { $pct = 100 }

            $ui['pbExecution'].Value = $pct
            $ui['lblProgressPercent'].Text = "${pct}%"
            if ($s.Status) { $ui['lblProgressStatus'].Text = [string]$s.Status }

            if ($s.Messages.Count -gt 0) {
                $batchBuilder = [System.Text.StringBuilder]::new()
                while ($s.Messages.Count -gt 0) {
                    $msg = $s.Messages[0]
                    $s.Messages.RemoveAt(0)
                    [void]$batchBuilder.AppendLine($msg)
                }
                $ui['txtConsoleLog'].AppendText($batchBuilder.ToString())
                $ui['txtConsoleLog'].ScrollToEnd()
            }

            if ($s.IsDone) {
                $uiTimer.Stop()
                try { $psAsync.EndInvoke($asyncResult) | Out-Null } catch {}
                $psAsync.Dispose()
                $runspace.Close()
                $runspace.Dispose()

                foreach ($btn in $allActionButtons) {
                    if ($ui[$btn]) { $ui[$btn].IsEnabled = $true }
                }

                if ($OnCompleted) {
                    try { & $OnCompleted $s } catch {}
                }
            }
        }.GetNewClosure()

        $uiTimer.Add_Tick($tickAction)
        $uiTimer.Start()
    }

    # 6. Evento de Instalação de Softwares (Aba 1: Botão Independente)
    $gui['btnInstallSoftwares'].Add_Click({
        $selectedApps = @()
        foreach ($k in $appMap.Keys) {
            if ($gui[$k] -and $gui[$k].IsChecked) { $selectedApps += $appMap[$k] }
        }

        if ($selectedApps.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                "Nenhum programa foi selecionado.`r`nPor favor, marque ao menos um software na lista para instalar.",
                "DEWIN Booster - Selecione Softwares",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnInstallSoftwares'].Content = "⏳ INSTALANDO PROGRAMAS..."

        & $runDewinAsync "Instalação de Softwares via Winget" {
            param($AppsArg)
            try {
                Invoke-DewinSoftwaresOnly -Apps $AppsArg
            } catch {
                $err = $_.Exception.Message
                if ($global:sync) { $global:sync.Error = $err }
                elseif ($sync) { $sync.Error = $err }
                Write-DewinLog -Level ERROR -Message "Erro na instalacao de softwares: $err"
            } finally {
                if ($global:sync) { $global:sync.IsDone = $true }
                elseif ($sync) { $sync.IsDone = $true }
            }
        } @(,$selectedApps) {
            param($s)
            $gui['btnInstallSoftwares'].Content = "$([char]::ConvertFromUtf32(0x1F4E5)) BAIXAR / INSTALAR PROGRAMAS SELECIONADOS"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "⚠️ Falha ao instalar softwares: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro ao instalar os softwares:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro & Log.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Softwares instalados/atualizados com sucesso!"
                [System.Windows.MessageBox]::Show(
                    "Os softwares selecionados foram instalados ou atualizados com sucesso via Winget!",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
        }
    })

    # 7. Evento de Aplicação de Otimizações (Aba 2: Botão Independente)
    $gui['btnApplyOptimizations'].Add_Click({
        $selectedTweaks = @{}
        foreach ($chkName in $allTweakChecks) {
            $tweakKey = $chkName.Substring(3)
            $selectedTweaks[$tweakKey] = [bool]($gui[$chkName].IsChecked)
        }
        $selectedTweaks['IsLaptop'] = [bool]$Hardware.IsLaptop

        $gui['btnApplyOptimizations'].Content = "⏳ APLICANDO OTIMIZAÇÕES..."

        & $runDewinAsync "Otimizações do Sistema" {
            param($TweaksArg, $HwArg)
            try {
                Invoke-DewinTweaksOnly -Tweaks $TweaksArg -Hardware $HwArg
            } catch {
                $err = $_.Exception.Message
                if ($global:sync) { $global:sync.Error = $err }
                elseif ($sync) { $sync.Error = $err }
                Write-DewinLog -Level ERROR -Message "Erro nas otimizacoes: $err"
            } finally {
                if ($global:sync) { $global:sync.IsDone = $true }
                elseif ($sync) { $sync.IsDone = $true }
            }
        } @($selectedTweaks, $Hardware) {
            param($s)
            $gui['btnApplyOptimizations'].Content = "⚡ APLICAR OTIMIZAÇÕES SELECIONADAS"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "⚠️ Falha nas otimizações: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro durante as otimizações:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro & Log.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Otimizações finalizadas com sucesso!"
                $res = [System.Windows.MessageBox]::Show(
                    "Otimizações aplicadas com sucesso!`r`n`r`nRecomenda-se reiniciar o computador para que todas as alterações de kernel e serviços entrem em vigor.`r`nDeseja reiniciar agora?",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Information
                )
                if ($res -eq [System.Windows.MessageBoxResult]::Yes) {
                    Restart-Computer
                }
            }
        }
    })

    # 8. Evento de Habilitação de Recursos do Windows (Aba 3: Botão Independente)
    $gui['btnEnableFeatures'].Add_Click({
        $selectedFeats = @()
        foreach ($k in $featMap.Keys) {
            if ($gui[$k] -and $gui[$k].IsChecked) { $selectedFeats += $featMap[$k] }
        }

        if ($selectedFeats.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                "Nenhum recurso opcional foi selecionado.`r`nPor favor, marque ao menos um recurso do Windows.",
                "DEWIN Booster - Selecione Recursos",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnEnableFeatures'].Content = "⏳ HABILITANDO RECURSOS..."

        & $runDewinAsync "Recursos Opcionais do Windows (DISM)" {
            param($FeatsArg)
            try {
                Invoke-DewinFeaturesOnly -Features $FeatsArg
            } catch {
                $err = $_.Exception.Message
                if ($global:sync) { $global:sync.Error = $err }
                elseif ($sync) { $sync.Error = $err }
                Write-DewinLog -Level ERROR -Message "Erro nos recursos DISM: $err"
            } finally {
                if ($global:sync) { $global:sync.IsDone = $true }
                elseif ($sync) { $sync.IsDone = $true }
            }
        } @(,$selectedFeats) {
            param($s)
            $gui['btnEnableFeatures'].Content = "⚙️ HABILITAR RECURSOS SELECIONADOS"
            if ($s.Error) {
                $gui['lblProgressStatus'].Text = "⚠️ Falha nos recursos DISM: $($s.Error)"
                [System.Windows.MessageBox]::Show(
                    "Ocorreu um erro ao configurar os recursos:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro & Log.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbExecution'].Value = 100
                $gui['lblProgressPercent'].Text = "100%"
                $gui['lblProgressStatus'].Text = "Recursos opcionais habilitados com sucesso!"
                [System.Windows.MessageBox]::Show(
                    "Recursos opcionais habilitados com sucesso via DISM!",
                    "DEWIN Booster - Concluído",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Information
                )
            }
        }
    })

    # 9. Exibição da Janela Modal
    $window.ShowDialog() | Out-Null
}
