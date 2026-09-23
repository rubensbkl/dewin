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
    $global:DewinWindow = $window

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
        "Notebook identificado ($($Hardware.Manufacturer) $($Hardware.Model)). O gerenciamento inteligente ativará hibernação compacta para preservar energia e autonomia ao fechar a tampa."
    } else {
        "Desktop identificado ($($Hardware.Manufacturer) $($Hardware.Model)). O gerenciamento inteligente desativará a hibernação para liberar espaço em disco SSD equivalente à memória RAM."
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
        'chkEnableLongPaths', 'chkDisableLockScreen', 'chkIsDev', 'chkDualBootUtc'
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

    # 3. Funções de Aplicação de Perfis Separadas por Aba
    $applyTweakPresetToGui = {
        param([string]$Level)
        $preset = Get-DewinTweakPreset -Level $Level

        foreach ($chkName in $allTweakChecks) {
            $tweakKey = $chkName.Substring(3)
            if ($preset.Tweaks.Contains($tweakKey) -and $gui[$chkName]) {
                $gui[$chkName].IsChecked = [bool]$preset.Tweaks[$tweakKey]
            }
        }

        $friendlyLevel = switch ($preset.Level) {
            'Light'      { 'Pouco Otimizado' }
            'Medium'     { 'Médio (Recomendado)' }
            'Aggressive' { '100% Otimizado' }
            default      { $preset.Level }
        }

        if ($gui['lblStatusTweaks']) {
            $gui['lblStatusTweaks'].Text = "Perfil '$friendlyLevel' selecionado. Clique ao lado para aplicar."
        }
    }

    $applyFeaturePresetToGui = {
        param([string]$ProfileName)
        $featPreset = Get-DewinFeaturePreset -Profile $ProfileName

        foreach ($k in $featMap.Keys) {
            if ($gui[$k]) {
                $gui[$k].IsChecked = ($featPreset.Features -contains $featMap[$k])
            }
        }

        $friendlyProfile = switch ($featPreset.Profile) {
            'General' { 'Geral (.NET apenas)' }
            'Dev'     { 'Desenvolvedor (Tudo)' }
            default   { $featPreset.Profile }
        }

        if ($gui['lblStatusFeatures']) {
            $gui['lblStatusFeatures'].Text = "Perfil '$friendlyProfile' selecionado. Clique ao lado para habilitar."
        }
    }

    # 4. Vinculação dos Botões de Níveis Rápidos (Aba 2: Otimizações)
    $gui['btnPresetTweakLight'].Add_Click({ & $applyTweakPresetToGui 'Light' })
    $gui['btnPresetTweakMedium'].Add_Click({ & $applyTweakPresetToGui 'Medium' })
    $gui['btnPresetTweakAggressive'].Add_Click({ & $applyTweakPresetToGui 'Aggressive' })

    # Botões de Seleção de Tweaks (Aba 2)
    $gui['btnSelectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
        if ($gui['lblStatusTweaks']) { $gui['lblStatusTweaks'].Text = "Todas as 29 otimizações foram marcadas." }
    })
    $gui['btnDeselectAll'].Add_Click({
        foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
        if ($gui['lblStatusTweaks']) { $gui['lblStatusTweaks'].Text = "Todas as otimizações foram desmarcadas." }
    })

    # Botões de Perfis Rápidos e Seleção de Recursos (Aba 3: Extras / DISM)
    $gui['btnPresetFeatGeneral'].Add_Click({ & $applyFeaturePresetToGui 'General' })
    $gui['btnPresetFeatDev'].Add_Click({ & $applyFeaturePresetToGui 'Dev' })
    $gui['btnSelectAllFeat'].Add_Click({
        foreach ($c in $allFeatChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
        if ($gui['lblStatusFeatures']) { $gui['lblStatusFeatures'].Text = "Todos os recursos opcionais foram marcados." }
    })
    $gui['btnDeselectAllFeat'].Add_Click({
        foreach ($c in $allFeatChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
        if ($gui['lblStatusFeatures']) { $gui['lblStatusFeatures'].Text = "Todos os recursos opcionais foram desmarcados." }
    })

    # Botões de Seleção de Softwares (Aba 1: Aplicativos - 100% Manual)
    $gui['btnSelectEssentialApps'].Add_Click({
        $essentialIds = @('appVcRedist64', 'appVcRedist86', 'app7zip', 'appChrome')
        foreach ($c in $allAppChecks) {
            if ($gui[$c]) { $gui[$c].IsChecked = ($essentialIds -contains $c) }
        }
        if ($gui['lblStatusSoftwares']) { $gui['lblStatusSoftwares'].Text = "Softwares essenciais (VC++, 7-Zip, Chrome) selecionados manualmente." }
    })
    $gui['btnSelectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $true } }
        if ($gui['lblStatusSoftwares']) { $gui['lblStatusSoftwares'].Text = "Todos os programas foram marcados." }
    })
    $gui['btnDeselectAllApps'].Add_Click({
        foreach ($c in $allAppChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
        if ($gui['lblStatusSoftwares']) { $gui['lblStatusSoftwares'].Text = "Todos os programas foram desmarcados." }
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

    $lastOriginTab = if ($gui['tabItemSoftwares']) { $gui['tabItemSoftwares'] } else { $null }
    if ($gui['mainTabControl']) {
        $gui['mainTabControl'].Add_SelectionChanged({
            if ($gui['mainTabControl'].SelectedItem -and $gui['tabItemLog'] -and $gui['mainTabControl'].SelectedItem -ne $gui['tabItemLog']) {
                $lastOriginTab = $gui['mainTabControl'].SelectedItem
            }
        })
    }

    if ($gui['btnBackToOptions']) {
        $gui['btnBackToOptions'].Add_Click({
            $target = if ($lastOriginTab) { $lastOriginTab } else { $gui['tabItemTweaks'] }
            if ($target -and $gui['mainTabControl']) {
                $gui['mainTabControl'].SelectedItem = $target
            }
        })
    }

    # Inicialização da interface: todas as opções iniciam desmarcadas por padrão
    foreach ($c in $allAppChecks)   { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    foreach ($c in $allTweakChecks) { if ($gui[$c]) { $gui[$c].IsChecked = $false } }
    foreach ($c in $allFeatChecks)  { if ($gui[$c]) { $gui[$c].IsChecked = $false } }

    # 5. Executador Assíncrono com UI Responsiva (Thread-Safe e Auto-Reativação)
    $global:DewinActionButtons = @(
        'btnInstallSoftwares', 'btnApplyOptimizations', 'btnEnableFeatures',
        'btnSelectEssentialApps', 'btnSelectAllApps', 'btnDeselectAllApps',
        'btnSelectAll', 'btnDeselectAll',
        'btnPresetTweakLight', 'btnPresetTweakMedium', 'btnPresetTweakAggressive',
        'btnPresetFeatGeneral', 'btnPresetFeatDev', 'btnSelectAllFeat', 'btnDeselectAllFeat',
        'btnBackToOptions', 'btnOpenLogFolder', 'btnClearLogConsole'
    )

    $setDewinActionButtonsState = {
        param([bool]$Enabled)
        $ui = if ($global:DewinGui) { $global:DewinGui } else { $null }
        if (-not $ui) { return }

        $btns = if ($global:DewinActionButtons) { $global:DewinActionButtons } else { @() }
        foreach ($b in $btns) {
            if ($ui[$b] -and ($ui[$b] -is [System.Windows.Controls.Button])) {
                $ui[$b].IsEnabled = $Enabled
            }
        }

        if ($Enabled) {
            foreach ($k in $ui.Keys) {
                if ($ui[$k] -is [System.Windows.Controls.Button]) {
                    $ui[$k].IsEnabled = $true
                }
            }
        }
    }

    $runDewinAsync = {
        param(
            [string]$ActionTitle,
            [string]$TabKey, # 'Softwares', 'Tweaks', 'Features'
            [scriptblock]$TaskScriptBlock,
            [array]$TaskArgs,
            [scriptblock]$OnCompleted
        )

        $pbName = "pb$TabKey"
        $lblStatusName = "lblStatus$TabKey"
        $lblPercentName = "lblPercent$TabKey"

        # Inicializa o progresso na aba ativa
        if ($gui[$pbName]) { $gui[$pbName].Value = 0 }
        if ($gui[$lblPercentName]) { $gui[$lblPercentName].Text = "0%" }
        if ($gui[$lblStatusName]) { $gui[$lblStatusName].Text = "Iniciando $ActionTitle..." }

        & $setDewinActionButtonsState $false

        # Loga no console da aba de Log em segundo plano (sem forçar troca de aba)
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

        $global:DewinUiTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $global:DewinUiTimer.Interval = [TimeSpan]::FromMilliseconds(100)

        # Variáveis locais capturadas pelo GetNewClosure()
        $localSetButtonState = $setDewinActionButtonsState
        $localPbName = $pbName
        $localStatusName = $lblStatusName
        $localPercentName = $lblPercentName

        $tickAction = {
            try {
                $ui = if ($global:DewinGui) { $global:DewinGui } elseif ($gui) { $gui } else { $null }
                if (-not $ui) { return }

                $s = if ($global:DewinSync) { $global:DewinSync } elseif ($sync) { $sync } else { $null }
                if (-not $s) { return }

                $pct = [int]$s.Percent
                if ($pct -lt 0) { $pct = 0 }
                if ($pct -gt 100) { $pct = 100 }

                if ($ui[$localPbName]) { $ui[$localPbName].Value = $pct }
                if ($ui[$localPercentName]) { $ui[$localPercentName].Text = "${pct}%" }
                if ($ui[$localStatusName] -and $s.Status) { $ui[$localStatusName].Text = [string]$s.Status }

                $msgList = @()
                if ($s.Messages -and $s.Messages.Count -gt 0) {
                    [System.Threading.Monitor]::Enter($s.Messages.SyncRoot)
                    try {
                        $msgList = @($s.Messages)
                        $s.Messages.Clear()
                    } finally {
                        [System.Threading.Monitor]::Exit($s.Messages.SyncRoot)
                    }
                }

                if ($msgList.Count -gt 0) {
                    $batchBuilder = [System.Text.StringBuilder]::new()
                    foreach ($m in $msgList) {
                        [void]$batchBuilder.AppendLine($m)
                    }
                    $ui['txtConsoleLog'].AppendText($batchBuilder.ToString())
                    $ui['txtConsoleLog'].ScrollToEnd()
                }

                if ($s.IsDone -or ($asyncResult -and $asyncResult.IsCompleted)) {
                    if ($global:DewinUiTimer) {
                        try { $global:DewinUiTimer.Stop() } catch {}
                    }

                    # 1. Reabilita TODOS os botões da interface IMEDIATAMENTE (primeira ação ao finalizar)
                    if ($localSetButtonState) {
                        try { & $localSetButtonState $true } catch {}
                    }
                    if ($global:DewinActionButtons) {
                        foreach ($btn in $global:DewinActionButtons) {
                            if ($ui[$btn] -and ($ui[$btn] -is [System.Windows.Controls.Button])) {
                                $ui[$btn].IsEnabled = $true
                            }
                        }
                    }
                    foreach ($k in $ui.Keys) {
                        if ($ui[$k] -is [System.Windows.Controls.Button]) {
                            $ui[$k].IsEnabled = $true
                        }
                    }

                    # 2. Restaura os títulos padrão dos botões principais
                    if ($ui['btnApplyOptimizations']) { $ui['btnApplyOptimizations'].Content = "Aplicar Otimizações Selecionadas" }
                    if ($ui['btnInstallSoftwares'])   { $ui['btnInstallSoftwares'].Content   = "Instalar Programas Selecionados" }
                    if ($ui['btnEnableFeatures'])     { $ui['btnEnableFeatures'].Content     = "Habilitar Recursos Selecionados" }

                    # 3. Restaura foco na janela do aplicativo (vital após reinício de Explorer)
                    $w = if ($global:DewinWindow) { $global:DewinWindow } elseif ($window) { $window } else { $null }
                    if ($w) {
                        try {
                            $w.Activate()
                            $w.Focus()
                        } catch {}
                    }

                    # 4. Limpeza segura de runspace
                    try { $psAsync.EndInvoke($asyncResult) | Out-Null } catch {}
                    try { $psAsync.Dispose() } catch {}
                    try { $runspace.Close() } catch {}
                    try { $runspace.Dispose() } catch {}

                    # 5. Executa callback de conclusão (ex: MessageBox de confirmação)
                    if ($OnCompleted) {
                        try { & $OnCompleted $s } catch {}
                    }

                    # 6. Garantia final: reabilita novamente após o fechamento de eventuais caixas de diálogo
                    if ($localSetButtonState) {
                        try { & $localSetButtonState $true } catch {}
                    }
                    foreach ($k in $ui.Keys) {
                        if ($ui[$k] -is [System.Windows.Controls.Button]) {
                            $ui[$k].IsEnabled = $true
                        }
                    }
                }
            } catch {}
        }.GetNewClosure()

        $global:DewinUiTimer.Add_Tick($tickAction)
        $global:DewinUiTimer.Start()
    }

    # 6. Evento de Instalação de Softwares (Aba 1: Botão Independente)
    $gui['btnInstallSoftwares'].Add_Click({
        $selectedApps = @()
        foreach ($k in $appMap.Keys) {
            if ($gui[$k] -and $gui[$k].IsChecked) { $selectedApps += $appMap[$k] }
        }

        if ($selectedApps.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                $window,
                "Nenhum programa foi selecionado.`r`nPor favor, marque ao menos um software na lista para instalar.",
                "DEWIN Booster - Selecione Softwares",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnInstallSoftwares'].Content = "Instalando programas..."

        & $runDewinAsync "Instalação de Softwares via Winget" 'Softwares' {
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
            $gui['btnInstallSoftwares'].Content = "Instalar Programas Selecionados"
            if ($s.Error) {
                $gui['lblStatusSoftwares'].Text = "Falha na instalação de programas: $($s.Error)"
                $gui['lblPercentSoftwares'].Text = "Erro"
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Ocorreu um erro ao instalar os programas selecionados:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbSoftwares'].Value = 100
                $gui['lblPercentSoftwares'].Text = "100%"
                $gui['lblStatusSoftwares'].Text = "Programas instalados e atualizados com sucesso via Winget."
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Os programas selecionados foram instalados ou atualizados com sucesso via Winget.",
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

        $gui['btnApplyOptimizations'].Content = "Aplicando otimizações..."

        & $runDewinAsync "Otimizações do Sistema" 'Tweaks' {
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
            $gui['btnApplyOptimizations'].Content = "Aplicar Otimizações Selecionadas"
            if ($s.Error) {
                $gui['lblStatusTweaks'].Text = "Falha na aplicação de otimizações: $($s.Error)"
                $gui['lblPercentTweaks'].Text = "Erro"
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Ocorreu um erro durante as otimizações:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbTweaks'].Value = 100
                $gui['lblPercentTweaks'].Text = "100%"
                $gui['lblStatusTweaks'].Text = "Otimizações aplicadas com sucesso no sistema."
                $res = [System.Windows.MessageBox]::Show(
                    $window,
                    "Otimizações aplicadas com sucesso.`r`n`r`nRecomenda-se reiniciar o computador para que todas as alterações entrem em vigor.`r`nDeseja reiniciar agora?",
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
                $window,
                "Nenhum recurso opcional foi selecionado.`r`nPor favor, marque ao menos um recurso do Windows.",
                "DEWIN Booster - Selecione Recursos",
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning
            )
            return
        }

        $gui['btnEnableFeatures'].Content = "Habilitando recursos..."

        & $runDewinAsync "Recursos Opcionais do Windows (DISM)" 'Features' {
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
            $gui['btnEnableFeatures'].Content = "Habilitar Recursos Selecionados"
            if ($s.Error) {
                $gui['lblStatusFeatures'].Text = "Falha na habilitação de recursos DISM: $($s.Error)"
                $gui['lblPercentFeatures'].Text = "Erro"
                [System.Windows.MessageBox]::Show(
                    $window,
                    "Ocorreu um erro ao configurar os recursos:`r`n$($s.Error)`r`n`r`nConsulte a aba de Registro e Logs para detalhes.",
                    "DEWIN Booster - Erro",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error
                )
            } else {
                $gui['pbFeatures'].Value = 100
                $gui['lblPercentFeatures'].Text = "100%"
                $gui['lblStatusFeatures'].Text = "Recursos opcionais do Windows habilitados com sucesso."
                $res = [System.Windows.MessageBox]::Show(
                    $window,
                    "Recursos opcionais habilitados com sucesso via DISM.`r`n`r`nÉ necessário reiniciar o computador para finalizar a instalação dos recursos.`r`nDeseja reiniciar agora?",
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

    # 9. Exibição da Janela Modal
    $window.ShowDialog() | Out-Null
}
