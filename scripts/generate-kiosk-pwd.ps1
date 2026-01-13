# #######################################
# Author: Electric Bluefish Productions Inc.  - James Applebaum
# Created: Jan 13 2016
# Project: CNC-control-pendent-Kiosk-Mode-for-Surface-Pro3
# File: generate-kiosk-pwd.ps1
# Description: Helper to create a DPAPI-encrypted password file for kiosk setup (kiosk.pwd). Defaults to not creating a password.
#
# #######################################

<#
Generate an encrypted password file for kiosk setup (scripts/kiosk.pwd)

Guidance & safety:
- Default recommendation: do NOT set a password (use a no-password local kiosk account) because AutoAdminLogon requires storing plaintext in the registry and that reduces security.
- If you still want a passworded account, create an encrypted password file that the installer script can decrypt using DPAPI.
- IMPORTANT: DPAPI ties the encrypted blob to the Windows user account that ran this command. Create this file using the same Windows user account that will run `setup-kiosk.ps1` on the target machine.

Usage:
- Interactive (recommended): run the script and answer prompts.
- Non-interactive: pass -Force and -PasswordSecureString to provide a SecureString programmatically (advanced usage).
#>

param(
    [string]$OutFile = (Join-Path $PSScriptRoot 'kiosk.pwd'),
    [switch]$Force,
    [System.Security.SecureString]$PasswordSecureString
)

function Write-Info($m)
{
    Write-Host "[INFO] $m"
}
function Write-WarnMsg($m)
{
    Write-Warning $m
}

# Detect if running elevated
try
{
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
catch
{
    $isAdmin = $false
}

Write-Host "This helper creates an encrypted password file for use with setup-kiosk.ps1 (DPAPI)."
Write-Info "Recommended default: do NOT use a password and use a no-password kiosk account."
if ($isAdmin)
{
    Write-WarnMsg "You are running this script elevated (Administrator). DPAPI will encrypt to the current account. If you intend the non-elevated installer user to decrypt this file, run this helper as that user (not elevated)."
}

if (Test-Path $OutFile -PathType Leaf)
{
    if (-not $Force)
    {
        $resp = Read-Host "An existing file was found at '$OutFile'. Overwrite? (y/N)"
        if ($resp -notin @('y', 'Y'))
        {
            Write-Info 'Aborting without creating or modifying password file.'
            exit 0
        }
    }
}

# Default behaviour: ask whether to create a password file.
if ($null -eq $PasswordSecureString)
{
    $resp = Read-Host "Do you want to create an encrypted password file? This is NOT recommended (Default: N). Type Y to provide a password."
    if ($resp -notin @('Y', 'y'))
    {
        Write-Info 'No password file created. The kiosk setup will default to creating a no-password account.'
        exit 0
    }

    # Prompt for password twice to confirm
    $p1 = Read-Host -AsSecureString "Enter password for kiosk account"
    $p2 = Read-Host -AsSecureString "Confirm password"

    # Helper to convert SecureString to plaintext for comparison (temporary)
    function SecureStringToPlain([Security.SecureString]$s)
    {
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        try
        {
            return [Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
        }
        finally
        {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b)
        }
    }

    $plain1 = SecureStringToPlain $p1
    $plain2 = SecureStringToPlain $p2

    if ($plain1 -ne $plain2)
    {
        Write-WarnMsg 'Passwords do not match. Aborting without writing a password file.'
        # zero variables
        Remove-Variable plain1, plain2 -ErrorAction SilentlyContinue
        exit 2
    }

    # use $p1 as the secure password
    $PasswordSecureString = $p1
    Remove-Variable plain1, plain2 -ErrorAction SilentlyContinue
}

# At this point $PasswordSecureString is set
if ($null -eq $PasswordSecureString)
{
    Write-WarnMsg 'No secure password provided; nothing to write.'
    exit 0
}

try
{
    $enc = $PasswordSecureString | ConvertFrom-SecureString
    # Ensure parent dir exists
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir))
    {
        New-Item -ItemType Directory -Path $dir | Out-Null
    }
    # Write the encrypted string
    $enc | Out-File -FilePath $OutFile -Encoding ASCII
    Write-Info "Encrypted password written to: $OutFile"
    Write-WarnMsg "Keep this file private and DO NOT commit it to git. .gitignore should already contain 'scripts/kiosk.pwd'."
}
catch
{
    Write-Error "Failed to write encrypted password file: $_"
    exit 3
}

# End
