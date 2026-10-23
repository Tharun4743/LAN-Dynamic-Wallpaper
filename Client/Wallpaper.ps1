# ==============================================================================
# Client/Wallpaper.ps1
# LAN Dynamic Wallpaper - Win32 Desktop Slideshow Engine
# Pure Windows PowerShell 5.1+ / P-Invoke SystemParametersInfoW
# ==============================================================================

[CmdletBinding()]
param()

Set-StrictMode -Version Latest

# Compile C# Win32 P/Invoke definition if not already present in AppDomain
if (-not ([System.Management.Automation.PSTypeName]'Win32WallpaperEngine').Type) {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;

    public class Win32WallpaperEngine {
        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int SystemParametersInfoW(
            int uAction,
            int uParam,
            string lpvParam,
            int fuWinIni
        );

        public const int SPI_SETDESKWALLPAPER = 0x0014;
        public const int SPIF_UPDATEINIFILE = 0x01;
        public const int SPIF_SENDCHANGE = 0x02;

        public static bool ApplyWallpaper(string path) {
            if (string.IsNullOrEmpty(path)) return false;
            int flags = SPIF_UPDATEINIFILE | SPIF_SENDCHANGE;
            int result = SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, path, flags);
            return result != 0;
        }
    }
"@ -ErrorAction Stop
}

function Set-WallpaperStyleConfiguration {
    <#
    .SYNOPSIS
    Configures user desktop registry settings for modern Fill style (style 10, no tile).
    #>
    param(
        [int]$Style = 10,
        [int]$Tile = 0
    )

    try {
        $desktopPath = "HKCU:\Control Panel\Desktop"
        if (Test-Path -LiteralPath $desktopPath) {
            Set-ItemProperty -Path $desktopPath -Name "WallpaperStyle" -Value "$Style" -Force | Out-Null
            Set-ItemProperty -Path $desktopPath -Name "TileWallpaper" -Value "$Tile" -Force | Out-Null
        }
    }
    catch {
        Write-Verbose "Could not configure registry wallpaper style: $($_.Exception.Message)"
    }
}

function Set-DesktopWallpaper {
    <#
    .SYNOPSIS
    Applies the specified image as the active Windows desktop wallpaper for the current user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath
    )

    if (-not (Test-Path -LiteralPath $ImagePath)) {
        Write-Error "Wallpaper image path does not exist: $ImagePath"
        return $false
    }

    $fullPath = [System.IO.Path]::GetFullPath($ImagePath)

    # Validate image extension
    $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($ext -notin @(".jpg", ".jpeg", ".png", ".bmp")) {
        Write-Error "Unsupported wallpaper image format: $ext"
        return $false
    }

    # Ensure desktop registry is configured to Fill
    Set-WallpaperStyleConfiguration -Style 10 -Tile 0

    try {
        $success = [Win32WallpaperEngine]::ApplyWallpaper($fullPath)
        if ($success) {
            Write-Verbose "Win32 SystemParametersInfoW successfully set wallpaper to: $fullPath"
            return $true
        }
        else {
            $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Error "SystemParametersInfoW failed with Win32 error code: $errorCode"
            return $false
        }
    }
    catch {
        Write-Error "Exception applying wallpaper: $($_.Exception.Message)"
        return $false
    }
}

function Get-CurrentWallpaperPath {
    <#
    .SYNOPSIS
    Retrieves the currently configured Windows wallpaper path from HKCU registry.
    #>
    try {
        $regVal = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name 'Wallpaper' -ErrorAction SilentlyContinue).Wallpaper
        return $regVal
    }
    catch {
        return ""
    }
}

function Step-WallpaperRotation {
    <#
    .SYNOPSIS
    Advances the slideshow deterministically to the next image in the collection.
    Handles deletions, additions, and single-image boundary conditions safely.
    Supports both [ref] and integer index passing to avoid argument transformation errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$ImageFiles,

        [Parameter(Mandatory = $true)]
        $CurrentIndex
    )

    if ($null -eq $ImageFiles -or $ImageFiles.Count -eq 0) {
        Write-Verbose "No valid wallpaper images available for rotation."
        return $null
    }

    $count = $ImageFiles.Count
    $isRef = ($CurrentIndex -is [System.Management.Automation.PSReference])
    $indexVal = if ($isRef) { [int]$CurrentIndex.Value } else { [int]$CurrentIndex }

    # Boundary check for index
    if ($indexVal -lt 0 -or $indexVal -ge $count) {
        $indexVal = 0
    }
    else {
        $indexVal = ($indexVal + 1) % $count
    }

    if ($isRef) {
        $CurrentIndex.Value = $indexVal
    }

    $selectedPath = $ImageFiles[$indexVal]
    if (Test-Path -LiteralPath $selectedPath) {
        $applied = Set-DesktopWallpaper -ImagePath $selectedPath
        if ($applied) {
            return $selectedPath
        }
    }
    else {
        Write-Warning "Selected image file not found on disk: $selectedPath. Advancing to next available."
        # If the file disappeared, remove and retry next
        $ImageFiles.RemoveAt($indexVal)
        if ($ImageFiles.Count -gt 0) {
            $indexVal = $indexVal % $ImageFiles.Count
            if ($isRef) {
                $CurrentIndex.Value = $indexVal
            }
            $nextPath = $ImageFiles[$indexVal]
            if (Test-Path -LiteralPath $nextPath) {
                Set-DesktopWallpaper -ImagePath $nextPath | Out-Null
                return $nextPath
            }
        }
    }

    return $null
}

function Get-SynchronizedWallpaper {
    <#
    .SYNOPSIS
    Calculates the exact synchronized wallpaper across the entire fleet
    based on epoch time so all client workstations rotate at the exact same second.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$ImageFiles,

        [Parameter(Mandatory = $false)]
        [int]$IntervalSeconds = 5
    )

    if ($null -eq $ImageFiles -or $ImageFiles.Count -eq 0) {
        return $null
    }

    if ($IntervalSeconds -le 0) { $IntervalSeconds = 5 }

    # Unix epoch timestamp in UTC seconds
    $epochSeconds = [int64]([DateTime]::UtcNow - [DateTime]::new(1970, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)).TotalSeconds

    # Deterministic synchronized index across every PC in the lab
    $syncIndex = [int]([Math]::Floor($epochSeconds / $IntervalSeconds) % $ImageFiles.Count)
    $selectedPath = $ImageFiles[$syncIndex]

    return [PSCustomObject]@{
        Index            = $syncIndex
        Path             = $selectedPath
        SecondsRemaining = $IntervalSeconds - ($epochSeconds % $IntervalSeconds)
    }
}


