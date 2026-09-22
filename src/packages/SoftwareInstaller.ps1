# ==============================================================================
# DEWIN Packages: Instalador de Softwares via Winget
# ==============================================================================

function Get-DewinSoftwareCatalog {
    [CmdletBinding()]
    param()

    return @(
        @{ Id = 'Microsoft.VCRedist.2015+.x64'; Name = 'Visual C++ 2015-2022 (x64)'; Category = 'Essenciais'; Default = $true },
        @{ Id = 'Microsoft.VCRedist.2015+.x86'; Name = 'Visual C++ 2015-2022 (x86)'; Category = 'Essenciais'; Default = $true },
        @{ Id = '7zip.7zip';                   Name = '7-Zip (Compactador de Arquivos)'; Category = 'Essenciais'; Default = $true },
        @{ Id = 'Google.Chrome';               Name = 'Google Chrome'; Category = 'Navegadores'; Default = $true },
        @{ Id = 'Microsoft.VisualStudioCode';  Name = 'Visual Studio Code'; Category = 'Desenvolvimento'; Default = $false },
        @{ Id = 'Git.Git';                     Name = 'Git for Windows'; Category = 'Desenvolvimento'; Default = $false },
        @{ Id = 'Discord.Discord';             Name = 'Discord'; Category = 'Comunicação'; Default = $false },
        @{ Id = 'Valve.Steam';                 Name = 'Steam'; Category = 'Jogos'; Default = $false },
        @{ Id = 'VideoLAN.VLC';                Name = 'VLC Media Player'; Category = 'Multimídia'; Default = $false },
        @{ Id = 'Spotify.Spotify';             Name = 'Spotify'; Category = 'Multimídia'; Default = $false }
    )
}

function Install-DewinSoftware {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$AppIds,
        [scriptblock]$OnProgress
    )

    if (-not $AppIds -or $AppIds.Count -eq 0) { return }

    Write-DewinLog -Level STEP -Message "[*] Iniciando instalação de $($AppIds.Count) pacotes via Winget..."

    $hasInternet = $false
    try {
        $hasInternet = [bool](Test-Connection -ComputerName '1.1.1.1' -Count 1 -Quiet -ErrorAction SilentlyContinue)
    } catch {}

    if (-not $hasInternet) {
        Write-DewinLog -Level WARN -Message '  [!] Sem conexão com a internet. Instalação de pacotes ignorada.'
        return
    }

    $catalog = Get-DewinSoftwareCatalog
    $total = $AppIds.Count
    $current = 0

    foreach ($id in $AppIds) {
        $current++
        $appInfo = $catalog | Where-Object { $_.Id -eq $id }
        $appName = if ($appInfo) { $appInfo.Name } else { $id }

        if ($OnProgress) {
            $pct = 90 + [int](($current / $total) * 7)
            try { & $OnProgress $pct "Instalando ($current/$total): $appName..." } catch {}
        }

        Write-DewinLog -Level STEP -Message "  [*] Instalando $appName ($id)..."
        try {
            $wingetProc = Start-Process -FilePath 'winget.exe' -ArgumentList "install --id `"$id`" --exact --silent --accept-package-agreements --accept-source-agreements --force" -NoNewWindow -PassThru -Wait
            if ($wingetProc.ExitCode -eq 0) {
                Write-DewinLog -Level SUCCESS -Message "  [+] $appName instalado com sucesso."
            } else {
                Write-DewinLog -Level INFO -Message "  [i] Winget $appName finalizou com código $($wingetProc.ExitCode)" -NoConsole
            }
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Falha ao instalar ${appName}: $($_.Exception.Message)"
        }
    }
}
