# ==============================================================================
# DEWIN Packages: Recursos Opcionais do Windows (DISM)
# ==============================================================================

function Get-DewinFeaturesCatalog {
    [CmdletBinding()]
    param()

    return @(
        @{ Id = 'NetFx3';                          Name = '.NET Framework 3.5 (Compatibilidade Legada)'; Default = $true },
        @{ Id = 'VirtualMachinePlatform';          Name = 'Plataforma de Máquina Virtual (Base WSL2)'; Default = $false },
        @{ Id = 'Microsoft-Windows-Subsystem-Linux'; Name = 'Subsistema do Windows para Linux (WSL2)'; Default = $false },
        @{ Id = 'Microsoft-Hyper-V-All';            Name = 'Hyper-V (Virtualização Nativa)'; Default = $false },
        @{ Id = 'Containers-DisposableClientVM';   Name = 'Windows Sandbox (Área Restrita)'; Default = $false }
    )
}

function Enable-DewinFeatures {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string[]]$FeatureNames,
        [scriptblock]$OnProgress
    )

    if (-not $FeatureNames -or $FeatureNames.Count -eq 0) { return }

    Write-DewinLog -Level STEP -Message "[*] Configurando $($FeatureNames.Count) recursos opcionais do Windows via DISM..."

    $total = $FeatureNames.Count
    $current = 0

    foreach ($feat in $FeatureNames) {
        $current++
        if ($OnProgress) {
            $pct = 85 + [int](($current / $total) * 5)
            try { & $OnProgress $pct "Habilitando ($current/$total): recurso $feat..." } catch {}
        }
        Write-DewinLog -Level STEP -Message "  [*] Habilitando recurso: $feat..."
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName $feat -NoRestart -ErrorAction SilentlyContinue | Out-Null
            Write-DewinLog -Level SUCCESS -Message "  [+] Recurso $feat pronto."
        } catch {
            Write-DewinLog -Level WARN -Message "  [!] Não foi possível habilitar ${feat}: $($_.Exception.Message)"
        }
    }
}
