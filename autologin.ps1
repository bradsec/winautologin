using namespace System.Security.Principal
using namespace System.DirectoryServices.AccountManagement

function Write-CustomMessage {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success', 'Default')]
        [string]$Level = 'Default'
    )
    
    $colors = @{
        'Info'    = 'Cyan'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
        'Success' = 'Green'
        'Default' = 'White'
    }
    
    Write-Host $Message -ForegroundColor $colors[$Level]
}

function Test-AdminPrivileges {
    return ([WindowsPrincipal][WindowsIdentity]::GetCurrent()).IsInRole([WindowsBuiltInRole]::Administrator)
}

function Test-WindowsVersion {
    $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
    return @{
        IsSupported = $osInfo.Version -match '^10\.' -or $osInfo.Version -match '^11\.'
        Caption = $osInfo.Caption
    }
}

function Test-Credentials {
    param(
        [string]$Username,
        [securestring]$Password
    )
    
    try {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement
        $context = New-Object PrincipalContext('Machine', $env:COMPUTERNAME)
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        
        return $context.ValidateCredentials($Username, $plainPassword)
    }
    finally {
        if ($BSTR) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

function Set-AutoLogin {
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        [Parameter(Mandatory)]
        [securestring]$Password
    )
    
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    
    try {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        
        Set-ItemProperty -Path $registryPath -Name "AutoAdminLogon" -Value "1" -Force
        Set-ItemProperty -Path $registryPath -Name "DefaultUsername" -Value $Username -Force
        Set-ItemProperty -Path $registryPath -Name "DefaultPassword" -Value $plainPassword -Force
        Set-ItemProperty -Path $registryPath -Name "DefaultDomainName" -Value $env:COMPUTERNAME -Force
        
        # Enable password protection for automatic logon
        Set-ItemProperty -Path $registryPath -Name "ForceAutoLogon" -Value "1" -Force
        
        return $true
    }
    catch {
        Write-CustomMessage "Failed to set auto-login: $_" -Level Error
        return $false
    }
    finally {
        if ($BSTR) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

function Remove-AutoLogin {
    $registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    
    try {
        $currentUser = (Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue).DefaultUsername
        
        # Remove auto-login settings
        Set-ItemProperty -Path $registryPath -Name "AutoAdminLogon" -Value "0" -Force
        @('DefaultUsername', 'DefaultPassword', 'DefaultDomainName', 'ForceAutoLogon') | ForEach-Object {
            Remove-ItemProperty -Path $registryPath -Name $_ -ErrorAction SilentlyContinue
        }
        
        return $currentUser
    }
    catch {
        Write-CustomMessage "Failed to remove auto-login: $_" -Level Error
        return $null
    }
}

function Show-Menu {
    Write-CustomMessage "`nPlease select an option:" -Level Info
    Write-CustomMessage "1) Enable Auto-Login" -Level Info
    Write-CustomMessage "2) Disable Auto-Login" -Level Info
    Write-CustomMessage "3) Exit" -Level Info
    
    $choice = Read-Host "`nEnter your choice (1-3)"
    return $choice
}

# Main script
Clear-Host
Write-CustomMessage "Windows 10 11 AutoLogin Configuration" -Level Info
Write-CustomMessage "Created by bradsec @ github.com" -Level Info
Write-CustomMessage "----------------------------------------" -Level Info

Write-CustomMessage "`nThis script allows you to:" -Level Info
Write-CustomMessage "- Enable automatic login for a Windows user account" -Level Info
Write-CustomMessage "- Disable automatic login if previously configured" -Level Info
Write-CustomMessage "`nSecurity Notice:" -Level Warning
Write-CustomMessage "- Auto-login stores credentials in the registry" -Level Warning

# System checks
$osCheck = Test-WindowsVersion
if (-not $osCheck.IsSupported) {
    Write-CustomMessage "`n[ERROR] This script requires Windows 10 or Windows 11" -Level Error
    Write-CustomMessage "Current OS: $($osCheck.Caption)" -Level Error
    exit 1
}

if (-not (Test-AdminPrivileges)) {
    Write-CustomMessage "`n[ERROR] This script requires administrator privileges" -Level Error
    exit 1
}

Write-CustomMessage "`nSystem Check:" -Level Info
Write-CustomMessage "- Operating System: $($osCheck.Caption)" -Level Info
Write-CustomMessage "- Administrator privileges: Yes" -Level Info

do {
    $choice = Show-Menu
    
    switch ($choice) {
        "1" {
            Write-CustomMessage "`nEnabling Auto-Login..." -Level Info
            do {
                $Username = Read-Host "Enter the username for autologin"
                $Password = Read-Host "Enter the password" -AsSecureString
                
                Write-CustomMessage "`nValidating credentials..." -Level Warning
                if (Test-Credentials -Username $Username -Password $Password) {
                    Write-CustomMessage "Credentials validated successfully!" -Level Success
                    
                    if (Set-AutoLogin -Username $Username -Password $Password) {
                        Write-CustomMessage "`nConfiguration Complete!" -Level Success
                        Write-CustomMessage "Auto-login has been configured for: $Username" -Level Success
                        break
                    }
                }
                else {
                    Write-CustomMessage "`n[ERROR] Invalid username or password." -Level Error
                    $retry = Read-Host "Would you like to try again? (Y/N)"
                    if ($retry -notmatch '^[Yy]') { break }
                }
            } while ($true)
        }
        "2" {
            Write-CustomMessage "`nDisabling Auto-Login..." -Level Info
            $previousUser = Remove-AutoLogin
            if ($null -ne $previousUser) {
                Write-CustomMessage "`nConfiguration Complete!" -Level Success
                Write-CustomMessage "Auto-login has been disabled successfully" -Level Success
                Write-CustomMessage "Previous Username: $previousUser" -Level Success
            }
        }
        "3" {
            Write-CustomMessage "`nExiting script..." -Level Warning
            exit 0
        }
        default {
            Write-CustomMessage "`n[ERROR] Invalid option selected" -Level Error
        }
    }
} while ($true)