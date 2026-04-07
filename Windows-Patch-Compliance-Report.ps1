<#
.SYNOPSIS
    Windows Patch Compliance Report

.DESCRIPTION
    Queries a list of Windows servers for installed and missing patches,
    generates a compliance report, and emails the results to the infrastructure
    team. Useful for audit, maintenance planning, and SLA reporting.

.AUTHOR
    Dayana Ann V M

.VERSION
    1.0

.NOTES
    Requirements:
    - WinRM enabled on target servers
    - Admin rights on target servers
    - SMTP access for email report
    - PowerShell 5.1 or later
#>

# -----------------------------------------------
# CONFIGURATION
# -----------------------------------------------
$Servers = @(
    "SERVER01",
    "SERVER02",
    "SERVER03"
    # Add more servers or import from file:
    # $Servers = Get-Content "C:\Scripts\serverlist.txt"
)

$LogDirectory  = "C:\Logs\PatchCompliance"
$SMTPServer    = "smtp.yourdomain.com"
$SMTPPort      = 25
$ReportFrom    = "patch-monitor@yourdomain.com"
$ReportTo      = "infra-team@yourdomain.com"
$ReportSubject = "Windows Patch Compliance Report - $(Get-Date -Format 'yyyy-MM-dd')"

# -----------------------------------------------
# INITIALISE
# -----------------------------------------------
$Timestamp = Get-Date -Format "yyyyMMdd_HHmm"
$LogFile   = "$LogDirectory\PatchCompliance_$Timestamp.csv"
$Results   = @()

if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory | Out-Null
}

# -----------------------------------------------
# QUERY EACH SERVER
# -----------------------------------------------
foreach ($Server in $Servers) {
    Write-Host "[INFO] Checking patches on: $Server" -ForegroundColor Cyan

    try {
        $PatchData = Invoke-Command -ComputerName $Server -ScriptBlock {
            $OS           = (Get-WmiObject Win32_OperatingSystem).Caption
            $LastBoot     = (Get-WmiObject Win32_OperatingSystem).LastBootUpTime
            $InstalledKBs = Get-HotFix | Sort-Object InstalledOn -Descending

            # Check for pending updates via Windows Update COM object
            $UpdateSession  = New-Object -ComObject Microsoft.Update.Session
            $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
            $PendingUpdates = ($UpdateSearcher.Search("IsInstalled=0 and Type='Software'")).Updates

            [PSCustomObject]@{
                OSVersion       = $OS
                LastBoot        = $LastBoot
                InstalledCount  = $InstalledKBs.Count
                LastPatchDate   = ($InstalledKBs | Select-Object -First 1).InstalledOn
                LastPatchKB     = ($InstalledKBs | Select-Object -First 1).HotFixID
                PendingCount    = $PendingUpdates.Count
            }
        } -ErrorAction Stop

        $ComplianceStatus = if ($PatchData.PendingCount -eq 0) { "Compliant" } else { "Non-Compliant" }
        $Colour = if ($ComplianceStatus -eq "Compliant") { "Green" } else { "Red" }

        Write-Host "[$ComplianceStatus] $Server | Pending: $($PatchData.PendingCount) | Last Patch: $($PatchData.LastPatchKB) on $($PatchData.LastPatchDate)" -ForegroundColor $Colour

        $Results += [PSCustomObject]@{
            ServerName       = $Server
            OSVersion        = $PatchData.OSVersion
            LastBoot         = $PatchData.LastBoot
            InstalledPatches = $PatchData.InstalledCount
            LastPatchDate    = $PatchData.LastPatchDate
            LastPatchKB      = $PatchData.LastPatchKB
            PendingPatches   = $PatchData.PendingCount
            ComplianceStatus = $ComplianceStatus
            CheckedAt        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

    } catch {
        Write-Warning "[WARNING] Could not reach $Server — $_"
        $Results += [PSCustomObject]@{
            ServerName       = $Server
            OSVersion        = "N/A"
            LastBoot         = "N/A"
            InstalledPatches = "N/A"
            LastPatchDate    = "N/A"
            LastPatchKB      = "N/A"
            PendingPatches   = "N/A"
            ComplianceStatus = "UNREACHABLE"
            CheckedAt        = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }
    }
}

# -----------------------------------------------
# EXPORT CSV
# -----------------------------------------------
$Results | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8
Write-Host "[INFO] Report exported: $LogFile"

# -----------------------------------------------
# SUMMARY
# -----------------------------------------------
$CompliantCount    = ($Results | Where-Object { $_.ComplianceStatus -eq "Compliant" }).Count
$NonCompliantCount = ($Results | Where-Object { $_.ComplianceStatus -eq "Non-Compliant" }).Count
$UnreachableCount  = ($Results | Where-Object { $_.ComplianceStatus -eq "UNREACHABLE" }).Count
$TotalServers      = $Results.Count

Write-Host ""
Write-Host "===== PATCH COMPLIANCE SUMMARY =====" -ForegroundColor Cyan
Write-Host "Total Servers   : $TotalServers"
Write-Host "Compliant       : $CompliantCount" -ForegroundColor Green
Write-Host "Non-Compliant   : $NonCompliantCount" -ForegroundColor Red
Write-Host "Unreachable     : $UnreachableCount" -ForegroundColor Yellow
Write-Host "====================================" -ForegroundColor Cyan

# -----------------------------------------------
# EMAIL REPORT
# -----------------------------------------------
$Body = @"
Windows Patch Compliance Report
=================================
Date/Time     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Total Servers : $TotalServers
Compliant     : $CompliantCount
Non-Compliant : $NonCompliantCount
Unreachable   : $UnreachableCount

Full report attached.
"@

try {
    Send-MailMessage `
        -From $ReportFrom `
        -To $ReportTo `
        -Subject $ReportSubject `
        -Body $Body `
        -SmtpServer $SMTPServer `
        -Port $SMTPPort `
        -Attachments $LogFile

    Write-Host "[INFO] Report sent to $ReportTo" -ForegroundColor Green
} catch {
    Write-Error "[ERROR] Failed to send email: $_"
}
