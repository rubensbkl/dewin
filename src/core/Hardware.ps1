# ==============================================================================
# DEWIN Core: Detecção Inteligente de Hardware
# ==============================================================================

function Get-DewinHardwareInfo {
    [CmdletBinding()]
    param()

    $info = [ordered]@{
        IsAdmin          = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Manufacturer     = 'Desconhecido'
        Model            = 'Desconhecido'
        Processor        = 'Processador'
        RamTotalGB       = 0
        GpuNames         = 'Não detectada'
        WinVersion       = 'Windows 11'
        WinBuild         = 0
        IsLaptop         = $false
        DeviceTypeStr    = 'Desktop'
        RecommendedProfile = 'DesktopGeral'
    }

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
        if ($cs.Manufacturer) { $info.Manufacturer = $cs.Manufacturer.Trim() }
        if ($cs.Model) { $info.Model = $cs.Model.Trim() }
    } catch {}

    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cpu.Name) { $info.Processor = $cpu.Name.Trim() }
    } catch {}

    try {
        $memSum = (Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object Capacity -Sum).Sum
        if ($memSum) { $info.RamTotalGB = [math]::Round($memSum / 1GB) }
    } catch {}

    try {
        $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue)
        $gpuList = ($gpus | ForEach-Object { $_.Name }) -join ' | '
        if ($gpuList) { $info.GpuNames = $gpuList }
    } catch {}

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $info.WinVersion = $os.Caption
            $info.WinBuild = [int]$os.BuildNumber
        }
    } catch {}

    try {
        $enclosure = Get-CimInstance Win32_SystemEnclosure -ErrorAction SilentlyContinue | Select-Object -First 1
        $chassisTypes = @($enclosure.ChassisTypes)
        $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        $info.IsLaptop = ($chassisTypes | Where-Object { $_ -in @(8, 9, 10, 11, 12, 14, 18, 21, 31, 32) }) -or $hasBattery
    } catch {
        $info.IsLaptop = $false
    }

    $info.DeviceTypeStr = if ($info.IsLaptop) { 'Notebook' } else { 'Desktop' }
    $info.RecommendedProfile = if ($info.IsLaptop) { 'LaptopGeral' } else { 'DesktopGeral' }

    return [PSCustomObject]$info
}
