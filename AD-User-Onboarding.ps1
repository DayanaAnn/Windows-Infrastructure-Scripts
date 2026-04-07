<#
.SYNOPSIS
    Active Directory User Onboarding Automation

.DESCRIPTION
    Automates the creation of new AD user accounts including group assignment,
    home drive mapping, and email notification. Reduces manual onboarding effort
    and ensures consistency across user provisioning.

.AUTHOR
    Dayana Ann V M

.VERSION
    1.0

.NOTES
    Requirements:
    - Active Directory PowerShell module (RSAT)
    - Appropriate AD admin permissions
    - SMTP access for notifications
#>

# -----------------------------------------------
# CONFIGURATION
# -----------------------------------------------
$Domain         = "yourdomain.com"
$OUPath         = "OU=Users,OU=Accounts,DC=yourdomain,DC=com"
$HomeDriveRoot  = "\\fileserver\homes"
$HomeDriveLetter = "H"
$DefaultGroups  = @("VPN-Users", "Citrix-Users", "Domain-Users-Standard")
$SMTPServer     = "smtp.yourdomain.com"
$SMTPPort       = 25
$NotifyFrom     = "it-onboarding@yourdomain.com"
$LogDirectory   = "C:\Logs\ADOnboarding"

# -----------------------------------------------
# INITIALISE
# -----------------------------------------------
Import-Module ActiveDirectory -ErrorAction Stop

$Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile   = "$LogDirectory\Onboarding_$Timestamp.csv"
$Results   = @()

if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory | Out-Null
}

# -----------------------------------------------
# USER INPUT — Replace with CSV import for bulk onboarding
# -----------------------------------------------
$NewUsers = @(
    [PSCustomObject]@{
        FirstName   = "John"
        LastName    = "Smith"
        Department  = "Finance"
        JobTitle    = "Financial Analyst"
        Manager     = "jane.doe"
        NotifyEmail = "john.smith@yourdomain.com"
    }
    # Add more users or import from CSV:
    # $NewUsers = Import-Csv "C:\Onboarding\new-users.csv"
)

# -----------------------------------------------
# ONBOARDING LOOP
# -----------------------------------------------
foreach ($User in $NewUsers) {

    $FirstName   = $User.FirstName
    $LastName    = $User.LastName
    $FullName    = "$FirstName $LastName"
    $SamAccount  = ($FirstName.Substring(0,1) + $LastName).ToLower() -replace "\s", ""
    $UPN         = "$SamAccount@$Domain"
    $HomePath    = "$HomeDriveRoot\$SamAccount"
    $TempPassword = ConvertTo-SecureString "Welcome@2024!" -AsPlainText -Force
    $Status      = "Success"
    $Notes       = ""

    Write-Host "[INFO] Creating user: $FullName ($SamAccount)" -ForegroundColor Cyan

    try {
        # Create AD user
        New-ADUser `
            -Name $FullName `
            -GivenName $FirstName `
            -Surname $LastName `
            -SamAccountName $SamAccount `
            -UserPrincipalName $UPN `
            -Path $OUPath `
            -Department $User.Department `
            -Title $User.JobTitle `
            -Manager $User.Manager `
            -AccountPassword $TempPassword `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -HomeDirectory $HomePath `
            -HomeDrive $HomeDriveLetter `
            -ErrorAction Stop

        Write-Host "[OK] User created: $SamAccount" -ForegroundColor Green

        # Assign default groups
        foreach ($Group in $DefaultGroups) {
            try {
                Add-ADGroupMember -Identity $Group -Members $SamAccount
                Write-Host "[OK] Added to group: $Group" -ForegroundColor Green
            } catch {
                Write-Warning "[WARNING] Could not add to group $Group — $_"
                $Notes += "Group assignment failed: $Group. "
            }
        }

        # Create home drive folder
        if (-not (Test-Path $HomePath)) {
            New-Item -ItemType Directory -Path $HomePath | Out-Null
            Write-Host "[OK] Home folder created: $HomePath" -ForegroundColor Green
        }

        # Send welcome notification
        $Body = @"
Hi $FirstName,

Your IT account has been created. Below are your details:

Username  : $SamAccount
Email     : $UPN
Home Drive: $HomeDriveLetter: ($HomePath)
Password  : Welcome@2024! (you will be prompted to change this on first login)

Please contact the IT helpdesk if you have any issues.

Regards,
IT Infrastructure Team
"@
        Send-MailMessage `
            -From $NotifyFrom `
            -To $User.NotifyEmail `
            -Subject "Your IT Account Has Been Created" `
            -Body $Body `
            -SmtpServer $SMTPServer `
            -Port $SMTPPort

    } catch {
        $Status = "Failed"
        $Notes  = $_.Exception.Message
        Write-Error "[ERROR] Failed to create user $SamAccount — $_"
    }

    $Results += [PSCustomObject]@{
        FullName    = $FullName
        SamAccount  = $SamAccount
        UPN         = $UPN
        Department  = $User.Department
        HomePath    = $HomePath
        Status      = $Status
        Notes       = $Notes
        CreatedAt   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# -----------------------------------------------
# EXPORT LOG
# -----------------------------------------------
$Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8
Write-Host "[INFO] Onboarding log exported: $LogFile"
