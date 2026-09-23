# ==============================================================================
# DEWIN Tweaks: Interface, Barra de Tarefas & Explorer
# ==============================================================================

function Restart-DewinExplorer {
    [CmdletBinding()]
    param()
    Write-DewinLog -Level STEP -Message '[*] Atualizando Windows Explorer...'
    Stop-Process -Name 'explorer' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 600
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Start-Process "$env:SystemRoot\explorer.exe"
    }
    Write-DewinLog -Level INFO -Message 'Windows Explorer reiniciado com sucesso.' -NoConsole
}

function Invoke-DewinInterfaceTweaks {
    [CmdletBinding()]
    param(
        [switch]$HideSearch = $true,
        [switch]$HideTaskView = $true,
        [switch]$CenterTaskbar = $true,
        [switch]$TaskbarEndTask = $true,
        [switch]$ClassicContextMenu = $true,
        [switch]$LaunchToThisPC = $true,
        [switch]$ShowExtensionsAndHidden = $true,
        [switch]$AlwaysShowScrollbars = $true
    )

    Write-DewinLog -Level STEP -Message '[*] Aplicando otimizações de interface e barra de tarefas...'
    $advExplorer = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

    # Barra de tarefas: Ocultar caixa de pesquisa
    if ($HideSearch) {
        Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'SearchboxTaskbarMode' -Value 0
    }

    # Desativação de Destaques de Pesquisa (desenhos/notícias do Bing), Pesquisa na Nuvem e Localização na Busca
    $searchPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-DewinReg -Path $searchPol -Name 'EnableDynamicContentInWSB' -Value 0
    Set-DewinReg -Path $searchPol -Name 'AllowCloudSearch' -Value 0
    Set-DewinReg -Path $searchPol -Name 'AllowSearchToUseLocation' -Value 0
    Set-DewinReg -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings' -Name 'IsDynamicSearchBoxEnabled' -Value 0

    # Barra de tarefas: Ocultar botão de multitarefa (Task View)
    if ($HideTaskView) {
        Set-DewinReg -Path $advExplorer -Name 'ShowTaskViewButton' -Value 0
    }

    # Barra de tarefas: Alinhamento centralizado (Padrão Windows 11)
    if ($CenterTaskbar) {
        Set-DewinReg -Path $advExplorer -Name 'TaskbarAl' -Value 1
    }

    # Barra de tarefas: Opção "Finalizar Tarefa" no botão direito
    if ($TaskbarEndTask) {
        Set-DewinReg -Path "$advExplorer\TaskbarDeveloperSettings" -Name 'TaskbarEndTask' -Value 1
    }

    # Menu de contexto clássico (estilo Windows 10 direto no botão direito)
    if ($ClassicContextMenu) {
        $clsidPath = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
        if (-not (Test-Path $clsidPath)) { New-Item -Path $clsidPath -Force -ErrorAction SilentlyContinue | Out-Null }
        Set-ItemProperty -Path $clsidPath -Name '(Default)' -Value '' -Force -ErrorAction SilentlyContinue | Out-Null
    }

    # Abrir Explorer em "Este Computador" & Remover Início e Galeria
    if ($LaunchToThisPC) {
        Set-DewinReg -Path $advExplorer -Name 'LaunchTo' -Value 1
        Set-DewinReg -Path 'HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0
        Set-DewinReg -Path 'HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' -Name 'System.IsPinnedToNameSpaceTree' -Value 0
    }

    # Exibir extensões de arquivos conhecidas e pastas ocultas
    if ($ShowExtensionsAndHidden) {
        Set-DewinReg -Path $advExplorer -Name 'HideFileExt' -Value 0
        Set-DewinReg -Path $advExplorer -Name 'Hidden' -Value 1
    }

    # Manter barras de rolagem sempre visíveis
    if ($AlwaysShowScrollbars) {
        Set-DewinReg -Path 'HKCU:\Control Panel\Accessibility' -Name 'DynamicScrollbars' -Value 0
    }

    Write-DewinLog -Level SUCCESS -Message '  [+] Interface, barra de tarefas e Explorer otimizados.'
}
