#######################################
# Author: Electric Bluefish Productions Inc.  - James Applebaum
# Created: Jan 13 2016
# Project: CNC-control-pendent-Kiosk-Mode-for-Surface-Pro3
# File: edit-kiosk-config.ps1
# Description: Interactive helper to create or edit scripts/kiosk.config.json
#
#######################################

<#
    Purpose:
    - Provide an easy interactive way to create or edit a local `scripts/kiosk.config.json` from the included sample or defaults.
    - Avoid storing secrets in the repo; the script will recommend using `generate-kiosk-pwd.ps1` for password creation.

    Usage:
    pwsh -ExecutionPolicy Bypass -File .\scripts\edit-kiosk-config.ps1

    Non-interactive invocation (advanced):
    pwsh -ExecutionPolicy Bypass -File .\scripts\edit-kiosk-config.ps1 -OutFile .\scripts\kiosk.config.json -NonInteractive -KioskUserName MyKiosk -KioskUrl https://example.local -Browser Edge -EnableAutoLogin $true

#>

param(
    [string]$SampleFile = "$PSScriptRoot/kiosk.config.sample.json",
    [string]$OutFile = "$PSScriptRoot/kiosk.config.json",
    [switch]$NonInteractive,
    [string]$KioskUserName,
    [string]$KioskFullName,
    [string]$KioskUrl,
    [ValidateSet('Edge', 'Chrome')][string]$Browser,
    [object]$EnableAutoLogin = $null,
    [object]$DisableAutoLogin = $null,
    [int]$MinimumBuild = 0,
    [object]$InstallEdgeIfMissing = $null
)

function Read-Input([string]$prompt, [string]$default = '')
{
    if ($NonInteractive)
    {
        return $default
    }

    if ($default -ne '')
    {
        $p = "${prompt} [$default]: "
    }
    else
    {
        $p = "${prompt}: "
    }

    $val = Read-Host -Prompt $p
    if ( [string]::IsNullOrWhiteSpace($val))
    {
        return $default
    }
    else
    {
        return $val
    }
}

function Read-YesNo([string]$prompt, [bool]$default = $false)
{
    if ($NonInteractive)
    {
        return $default
    }

    if ($default)
    {
        $d = 'Y'
    }
    else
    {
        $d = 'N'
    }

    while ($true)
    {
        $val = Read-Host -Prompt "${prompt} (Y/N) [$d]"
        if ( [string]::IsNullOrWhiteSpace($val))
        {
            return $default
        }
        switch ( $val.ToUpper())
        {
            'Y' {
                return $true
            }
            'N' {
                return $false
            }
            default {
                Write-Host "Please answer Y or N." -ForegroundColor Yellow
            }
        }
    }
}

# Load sample or defaults
$config = @{
    KioskUserName = 'GuestKiosk'
    KioskFullName = 'Guest Kiosk Account'
    KioskUrl = 'https://example.local'
    Browser = 'Edge'
    EnableAutoLogin = $true
    DisableAutoLogin = $false
    MinimumBuild = 19041
    InstallEdgeIfMissing = $true
    EncryptedPasswordFile = 'kiosk.pwd'
}

if (Test-Path -Path $SampleFile)
{
    try
    {
        $sampleText = Get-Content -Raw -Path $SampleFile -ErrorAction Stop
        $loaded = $sampleText | ConvertFrom-Json -ErrorAction Stop
        foreach ($k in $loaded.PSObject.Properties.Name)
        {
            $config[$k] = $loaded.$k
        }
    }
    catch
    {
        Write-Warning "Failed to parse sample file at $SampleFile. Using defaults. Details: $_"
    }
}

# Interactive prompts (unless overridden by parameters or NonInteractive)
if (-not $NonInteractive)
{
    Write-Host "This helper will create or update: $OutFile" -ForegroundColor Cyan
    Write-Host "If you need to create an encrypted password file for AutoAdminLogon, use scripts/generate-kiosk-pwd.ps1 (recommended)." -ForegroundColor Yellow
}

# Gather values (preserve provided args)
if ($PSBoundParameters.ContainsKey('KioskUserName') -and $KioskUserName)
{
    $config.KioskUserName = $KioskUserName
}
else
{
    $config.KioskUserName = Read-Input 'Kiosk user name' $config.KioskUserName
}
if ($PSBoundParameters.ContainsKey('KioskFullName') -and $KioskFullName)
{
    $config.KioskFullName = $KioskFullName
}
else
{
    $config.KioskFullName = Read-Input 'Kiosk full name' $config.KioskFullName
}
if ($PSBoundParameters.ContainsKey('KioskUrl') -and $KioskUrl)
{
    $config.KioskUrl = $KioskUrl
}
else
{
    $config.KioskUrl = Read-Input 'Kiosk URL' $config.KioskUrl
}
if ($PSBoundParameters.ContainsKey('Browser') -and $Browser)
{
    $config.Browser = $Browser
}
else
{
    $config.Browser = Read-Input 'Browser (Edge/Chrome)' $config.Browser
}

# Booleans
if ( $PSBoundParameters.ContainsKey('EnableAutoLogin'))
{
    $config.EnableAutoLogin = [bool]$EnableAutoLogin
}
else
{
    $config.EnableAutoLogin = Read-YesNo 'Enable AutoLogin by default when EnableAutoLogin is true?' ([bool]$config.EnableAutoLogin)
}

if ( $PSBoundParameters.ContainsKey('DisableAutoLogin'))
{
    $config.DisableAutoLogin = [bool]$DisableAutoLogin
}
else
{
    $config.DisableAutoLogin = Read-YesNo "Disable AutoLogin (opt-out)?" ([bool]$config.DisableAutoLogin)
}

if ( $PSBoundParameters.ContainsKey('MinimumBuild'))
{
    $config.MinimumBuild = $MinimumBuild
}
else
{
    $m = Read-Input 'Minimum Windows build (e.g. 19041)' [string]$config.MinimumBuild; $config.MinimumBuild = [int]$m
}

if ( $PSBoundParameters.ContainsKey('InstallEdgeIfMissing'))
{
    $config.InstallEdgeIfMissing = [bool]$InstallEdgeIfMissing
}
else
{
    $config.InstallEdgeIfMissing = Read-YesNo 'Install Edge via winget if missing?' ([bool]$config.InstallEdgeIfMissing)
}

# Sanity checks
if ($config.Browser -notin @('Edge', 'Chrome'))
{
    Write-Warning "Browser must be 'Edge' or 'Chrome'. Falling back to Edge."
    $config.Browser = 'Edge'
}

# Final confirm
if (-not $NonInteractive)
{
    Write-Host "\nConfiguration to be written to: $OutFile" -ForegroundColor Green
    $config | ConvertTo-Json -Depth 5 | Write-Host
    $ok = Read-YesNo 'Write this configuration file now?' $true
    if (-not $ok)
    {
        Write-Host 'Aborted by user.' -ForegroundColor Yellow; exit 1
    }
}

# Write file
try
{
    $json = $config | ConvertTo-Json -Depth 10
    $json | Out-File -FilePath $OutFile -Encoding UTF8 -Force
    Write-Host "Wrote config to $OutFile" -ForegroundColor Green
    Write-Host "Important: Do NOT commit $OutFile to source control. Add it to .gitignore if necessary." -ForegroundColor Yellow
}
catch
{
    Write-Error "Failed to write config: $_"
    exit 2
}

# Offer to create an encrypted password via helper
if (-not $NonInteractive)
{
    $wantPwd = Read-YesNo "Would you like to run scripts/generate-kiosk-pwd.ps1 now to create an optional encrypted password file?" $false
    if ($wantPwd)
    {
        $gen = Join-Path -Path $PSScriptRoot -ChildPath 'generate-kiosk-pwd.ps1'
        if (Test-Path $gen)
        {
            Write-Host "Launching $gen ..." -ForegroundColor Cyan
            & pwsh -NoProfile -ExecutionPolicy Bypass -File $gen
        }
        else
        {
            Write-Warning "Helper script not found: $gen. Create kiosk.pwd manually with ConvertFrom-SecureString on the target account."
        }
    }
}

Write-Host 'Done.' -ForegroundColor Cyan
