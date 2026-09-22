# ==============================================================================
# DEWIN Core: Sistema de Auditoria e Logs
# ==============================================================================

function Initialize-DewinLogging {
    [CmdletBinding()]
    param([string]$CustomDir)

    $global:DewinTimer = [System.Diagnostics.Stopwatch]::StartNew()
    $global:DewinStats = @{
        Success  = 0
        Warnings = 0
        Errors   = 0
    }

    if (-not $CustomDir) {
        if ($PSScriptRoot) {
            $rootCandidate = if ((Split-Path $PSScriptRoot -Leaf) -eq 'core') {
                Join-Path $PSScriptRoot '..\..\logs'
            } else {
                Join-Path $PSScriptRoot 'logs'
            }
            $CustomDir = [System.IO.Path]::GetFullPath($rootCandidate)
        } else {
            $CustomDir = Join-Path -Path "$env:LOCALAPPDATA\dewin" -ChildPath 'logs'
        }
    }

    try {
        if (-not (Test-Path $CustomDir)) {
            New-Item -Path $CustomDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        $CustomDir = Join-Path -Path $env:TEMP -ChildPath 'dewin-logs'
        if (-not (Test-Path $CustomDir)) { New-Item -Path $CustomDir -ItemType Directory -Force | Out-Null }
    }

    $timestampStr = Get-Date -Format 'yyyyMMdd_HHmmss'
    $global:DewinLogPath = Join-Path -Path $CustomDir -ChildPath "dewin_${timestampStr}.log"
    $global:DewinLatestLog = Join-Path -Path $CustomDir -ChildPath 'dewin-latest.log'
}

function Write-DewinLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO', 'SUCCESS', 'WARN', 'ERROR', 'STEP', 'RAW')]
        [string]$Level = 'INFO',
        [switch]$NoConsole,
        [scriptblock]$OnUiLog
    )

    $timeNow = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logPrefix = "[$timeNow] [$Level]"

    if (-not $NoConsole -and $Level -ne 'RAW') {
        switch ($Level) {
            'SUCCESS' { Write-Host $Message -ForegroundColor Green; if ($global:DewinStats) { $global:DewinStats.Success++ } }
            'WARN'    { Write-Host $Message -ForegroundColor Yellow; if ($global:DewinStats) { $global:DewinStats.Warnings++ } }
            'ERROR'   { Write-Host $Message -ForegroundColor Red; if ($global:DewinStats) { $global:DewinStats.Errors++ } }
            'STEP'    { Write-Host $Message -ForegroundColor Cyan }
            Default   { Write-Host $Message -ForegroundColor Gray }
        }
    }

    $logTarget = if ($global:DewinLogPath) { $global:DewinLogPath } else { $DewinLogPath }

    # Notificacao para interface grafica via fila sincronizada thread-safe
    $s = if ($global:sync) { $global:sync }
         elseif ($global:DewinSync) { $global:DewinSync }
         elseif ($sync) { $sync }
         elseif ($DewinSync) { $DewinSync }
         else { $null }

    if ($s -and ($null -ne $s.Messages)) {
        try {
            $uiEntry = if ($Level -eq 'RAW') { $Message } else { "$logPrefix $Message" }
            [void]$s.Messages.Add($uiEntry)
        } catch {}
    } elseif ($OnUiLog) {
        try { & $OnUiLog $Message $Level } catch {}
    }

    if ($logTarget) {
        $entry = if ($Level -eq 'RAW') { $Message } else { "$logPrefix $Message" }
        try {
            Add-Content -LiteralPath $logTarget -Value $entry -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
}
