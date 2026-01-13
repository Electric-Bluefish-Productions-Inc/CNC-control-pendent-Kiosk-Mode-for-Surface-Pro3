<#
PowerShell kiosk setup helper (configurable)
- Reads configuration from a JSON file (optional)
- Checks Windows build (compares BuildNumber to $MinimumBuild)
- Creates a local kiosk user (password optional)
- Optionally enables AutoAdminLogon for that user
- Optionally installs Edge using winget (if requested and available)
- Registers a scheduled task to launch Edge/Chrome with kiosk flags at user logon

USAGE example:
  pwsh -ExecutionPolicy Bypass -File .\scripts\setup-kiosk.ps1 -KioskUserName GuestKiosk -KioskUrl "https://yourwebsite.local" -Browser Edge -EnableAutoLogin $true -InstallEdgeIfMissing

Notes / caveats:
- This script must be run as Administrator.
- Auto-login with an account that has a stored plaintext password reduces security; only enable on physically secured devices.
- Assigned Access (Windows native kiosk) is the recommended hardened approach.
#>

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\kiosk.config.json'),
    [string]$KioskUserName = 'laser',
    [string]$KioskFullName = 'Kiosk user',
    [string]$KioskUrl = 'https://example.local/',
    [ValidateSet('Edge', 'Chrome')][string]$Browser = 'Edge',
    [bool]$EnableAutoLogin = $true,
    [int]$MinimumBuild = 19045,
    [switch]$InstallEdgeIfMissing,
    [switch]$WhatIf,
    [switch]$DisableAutoLogin,
    [switch]$Yes
)

# Load JSON config if present and override parameters
if (Test-Path $ConfigPath)
{
    try
    {
        $cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
        if ($null -ne $cfg.KioskUserName)
        {
            $KioskUserName = $cfg.KioskUserName
        }
        if ($null -ne $cfg.KioskFullName)
        {
            $KioskFullName = $cfg.KioskFullName
        }
        if ($null -ne $cfg.KioskUrl)
        {
            $KioskUrl = $cfg.KioskUrl
        }
        if ($null -ne $cfg.Browser)
        {
            $Browser = $cfg.Browser
        }
        if ($null -ne $cfg.EnableAutoLogin)
        {
            $EnableAutoLogin = [bool]$cfg.EnableAutoLogin
        }
        if ($null -ne $cfg.MinimumBuild)
        {
            $MinimumBuild = [int]$cfg.MinimumBuild
        }
        if ($null -ne $cfg.InstallEdgeIfMissing)
        {
            if ($cfg.InstallEdgeIfMissing)
            {
                $InstallEdgeIfMissing = $true
            }
        }
        # Backwards-compatible handling: new opt-out flag is DisableAutoLogin. Older configs might include ConfirmAutoLogin (bool)
        if ($null -ne $cfg.DisableAutoLogin)
        {
            $DisableAutoLogin = [bool]$cfg.DisableAutoLogin
        }
        elseif ($null -ne $cfg.ConfirmAutoLogin)
        {
            $DisableAutoLogin = -not [bool]$cfg.ConfirmAutoLogin
        }
    }
    catch
    {
        Write-Warning "Failed to parse config at '$ConfigPath': $_"
    }
}

# If a password file exists next to the config, try to load it (DPAPI-encrypted string produced by ConvertFrom-SecureString)
$pwdPath = Join-Path (Split-Path $ConfigPath) 'kiosk.pwd'
$KioskCredential = $null
if (Test-Path $pwdPath)
{
    try
    {
        $enc = Get-Content -Raw -Path $pwdPath
        $securePwd = ConvertTo-SecureString -String $enc
        $KioskCredential = New-Object System.Management.Automation.PSCredential($KioskUserName, $securePwd)
    }
    catch
    {
        Write-Warning "Could not load encrypted password from '$pwdPath'. Proceeding without a credential: $_"
        $KioskCredential = $null
    }
}

function Assert-Admin
{
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin)
    {
        Write-Error "This script must be run as Administrator. Exiting."
        exit 1
    }
}

function Get-WindowsBuildNumber
{
    try
    {
        $cv = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        return [int]$cv.CurrentBuildNumber
    }
    catch
    {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        return [int]$os.BuildNumber
    }
}

function Check-WindowsBuild
{
    param([int]$Minimum)
    $build = Get-WindowsBuildNumber
    Write-Host "Detected Windows build: $build"
    if ($build -lt $Minimum)
    {
        Write-Warning "Detected build ($build) is older than required minimum ($Minimum)."
        return $false
    }
    Write-Host "Build meets minimum requirement ($Minimum)."
    return $true
}

function Ensure-Edge
{
    param([switch]$InstallIfMissing)
    $paths = @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
    )

    foreach ($p in $paths)
    {
        if (Test-Path $p)
        {
            return $p
        }
    }

    if ($InstallIfMissing)
    {
        if (Get-Command winget -ErrorAction SilentlyContinue)
        {
            Write-Host "Edge not found. Attempting to install via winget..."
            if ($WhatIf)
            {
                Write-Host "WhatIf: winget install Microsoft.Edge --silent"
                return $null
            }
            $output = winget install --silent --accept-package-agreements --accept-source-agreements Microsoft.Edge 2>&1
            Write-Host $output
            foreach ($p in $paths)
            {
                if (Test-Path $p)
                {
                    return $p
                }
            }
            Write-Warning "Edge install attempted but executable not found in expected location."
            return $null
        }
        else
        {
            Write-Warning "winget not available. Please install Edge manually or enable winget."
            return $null
        }
    }

    Write-Warning "Edge not found on system."
    return $null
}

function Get-BrowserPath
{
    param([string]$browser)
    switch ($browser)
    {
        'Edge' {
            return Ensure-Edge -InstallIfMissing:$InstallEdgeIfMissing
        }
        'Chrome' {
            $paths = @(
                "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
            )
            foreach ($p in $paths)
            {
                if (Test-Path $p)
                {
                    return $p
                }
            }
            Write-Warning "Chrome not found in Program Files. Install Chrome or provide path manually."
            return $null
        }
        default {
            Write-Warning "Unknown browser: $browser"; return $null
        }
    }
}

function Create-KioskUser
{
    param([string]$UserName, [string]$FullName)

    $existing = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue
    if ($existing)
    {
        Write-Host "User '$UserName' already exists. Skipping creation."
        return $true
    }

    try
    {
        if ($WhatIf)
        {
            if ($null -ne $KioskCredential)
            {
                Write-Host "WhatIf: New-LocalUser -Name $UserName -Password <secure> -FullName '$FullName' -AccountNeverExpires"
            }
            else
            {
                Write-Host "WhatIf: New-LocalUser -Name $UserName -NoPassword -FullName '$FullName'"
            }
            return $true
        }

        if ($null -ne $KioskCredential)
        {
            New-LocalUser -Name $UserName -Password $KioskCredential.Password -FullName $FullName -Description 'Kiosk account for assigned kiosk' -AccountNeverExpires -ErrorAction Stop
        }
        else
        {
            New-LocalUser -Name $UserName -NoPassword -FullName $FullName -Description 'Kiosk account for assigned kiosk' -ErrorAction Stop
        }

        Add-LocalGroupMember -Group 'Users' -Member $UserName -ErrorAction Stop
        Write-Host "Created local user: $UserName"
        return $true
    }
    catch
    {
        Write-Error "Failed to create local user: $_"
        return $false
    }
}

function Enable-AutoLogin
{
    param([string]$UserName)
    $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    try
    {
        if ($WhatIf)
        {
            Write-Host "WhatIf: Set AutoAdminLogon=1, DefaultUserName=$UserName, DefaultPassword=(hidden) in $regPath"
            return $true
        }

        Set-ItemProperty -Path $regPath -Name 'AutoAdminLogon' -Value '1' -Type String -Force
        Set-ItemProperty -Path $regPath -Name 'DefaultUserName' -Value $UserName -Type String -Force
        Set-ItemProperty -Path $regPath -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Type String -Force

        if ($null -ne $KioskCredential)
        {
            # Convert SecureString to plaintext temporarily for registry write
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($KioskCredential.Password)
            try
            {
                $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
                Set-ItemProperty -Path $regPath -Name 'DefaultPassword' -Value $plain -Type String -Force
            }
            finally
            {
                [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
            }
        }
        else
        {
            New-ItemProperty -Path $regPath -Name 'DefaultPassword' -PropertyType String -Value '' -Force | Out-Null
        }

        Write-Host "Auto-login enabled for user $UserName (stored in registry)."
        return $true
    }
    catch
    {
        Write-Error "Failed to set auto-login registry keys: $_"
        return $false
    }
}

function Create-KioskLaunchTask
{
    param([string]$UserName, [string]$ExePath, [string]$Url, [string]$Browser)

    $taskName = "KioskLaunch_$UserName"

    if ($Browser -eq 'Edge')
    {
        $args = "--kiosk $Url --kiosk-type=fullscreen --no-first-run"
    }
    else
    {
        $args = "--kiosk $Url --no-first-run --disable-translate --disable-infobars"
    }

    # Remove existing task if present
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing)
    {
        try
        {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        }
        catch
        {
        }
    }

    $action = New-ScheduledTaskAction -Execute $ExePath -Argument $args
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $UserName

    try
    {
        if ($WhatIf)
        {
            Write-Host "WhatIf: Register-ScheduledTask -TaskName $taskName -Trigger <AtLogOn $UserName> -Action <launch> -RunLevel Limited"
            return $true
        }

        Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -Description "Launch browser kiosk for $UserName" -User $UserName -RunLevel Limited -ErrorAction Stop
        Write-Host "Scheduled task '$taskName' created to launch $Browser at $Url for user $UserName."
        return $true
    }
    catch [System.Exception]
    {
        $err = $_
        Write-Warning ("Failed to register scheduled task for user {0}: {1}" -f $UserName, $err)
        return $false
    }
}

function Should-EnableAutoLogin
{
    param(
        [bool]$EnableAutoLoginParam,
        [bool]$DisableAutoLoginParam,
        [bool]$DisableFromCli,
        [bool]$YesFlag
    )

    # If auto-login is disabled globally, don't enable
    if (-not $EnableAutoLoginParam)
    {
        return $false
    }

    # If opt-out requested
    if ($DisableAutoLoginParam)
    {
        # If it was passed from CLI, require explicit Yes confirmation
        if ($DisableFromCli -and -not $YesFlag)
        {
            throw "Disabling auto-login from CLI requires explicit confirmation: pass -DisableAutoLogin and -Yes (or --yes)."
        }
        # Otherwise, respected (either from config or confirmed)
        return $false
    }

    return $true
}

# ----------------- Script body (moved into callable function) -----------------
function Invoke-SetupKiosk
{
    Assert-Admin

    Write-Host "Starting kiosk setup with parameters:`n  UserName: $KioskUserName`n  URL: $KioskUrl`n  Browser: $Browser`n  EnableAutoLogin: $EnableAutoLogin`n  MinimumBuild: $MinimumBuild`n"

    $ok = Check-WindowsBuild -Minimum $MinimumBuild
    if (-not $ok)
    {
        $resp = Read-Host "Windows build is older than required. Continue anyway? (Y/N)"
        if ($resp -notin @('Y', 'y'))
        {
            Write-Host "Aborting as requested."
            exit 2
        }
    }

    # Create user
    if (-not (Create-KioskUser -UserName $KioskUserName -FullName $KioskFullName))
    {
        Write-Error "Could not create or find the kiosk user. Aborting."
        exit 3
    }

    # Decide whether to enable auto-login. Treat CLI-provided disable differently (require -Yes)
    $disableFromCli = $PSBoundParameters.ContainsKey('DisableAutoLogin')
    try
    {
        $shouldEnable = Should-EnableAutoLogin -EnableAutoLoginParam $EnableAutoLogin -DisableAutoLoginParam $DisableAutoLogin -DisableFromCli $disableFromCli -YesFlag $Yes
    }
    catch
    {
        Write-Error $_
        Write-Host "To opt out of auto-login from the CLI, rerun with: -DisableAutoLogin -Yes"
        exit 4
    }

    if ($shouldEnable)
    {
        if (-not (Enable-AutoLogin -UserName $KioskUserName))
        {
            Write-Warning "Auto-login failed to configure. You can set it manually via netplwiz or registry."
        }
    }
    else
    {
        Write-Host "Auto-login will NOT be configured (DisableAutoLogin requested or EnableAutoLogin=false)."
    }

    # Locate browser executable
    $exe = Get-BrowserPath -browser $Browser
    if (-not $exe)
    {
        Write-Warning "Browser executable not found. The script will continue but kiosk launch task cannot be created."
        Write-Host "Manual next steps: install the desired browser and create an Assigned Access or a startup launch for the kiosk user."
        exit 0
    }

    # Create scheduled task to launch kiosk
    if (-not (Create-KioskLaunchTask -UserName $KioskUserName -ExePath $exe -Url $KioskUrl -Browser $Browser))
    {
        Write-Warning "Failed to create the kiosk launch task. You may need to create a startup shortcut manually for the kiosk user."
    }

    Write-Host "Done. Next recommended manual steps:"
    Write-Host "  1) Use Settings -> Accounts -> Family & other users -> Set up a kiosk -> Assign the kiosk user and app (Assigned Access) for a hardened kiosk."
    Write-Host "  2) Test by rebooting the device."
    Write-Host "  3) If touch keyboard is required, prefer Edge (Chromium) for better integration."
}

# If the script is being run directly (not dot-sourced for tests), invoke the main function
if (($MyInvocation.InvocationName -ne '.') -and ($PSCommandPath -and $MyInvocation.MyCommand.Path -eq $PSCommandPath))
{
    Invoke-SetupKiosk
}
