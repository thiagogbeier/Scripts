<#PSScriptInfo
.VERSION 1.0.0
.GUID
.AUTHOR Thiago Beier
.COMPANYNAME
.COPYRIGHT GPL
.TAGS PowerShell Execution Time To Run
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
v1.0.0 - initial version to measure how log it takes to execute a powershell and its functions, parameters and dependencies
#>


<#
.SYNOPSIS
    This script provides time spent to execute a command or ps1 file with its contents, dependencies and functions.

.DESCRIPTION
    This PowerShell script provides time spent to execute a command or ps1 file with its contents, dependencies and functions.
    
.PARAMETER command
    Executes the script using App-based authentication with AppId, AppSecret, and Tenant.

      
.EXAMPLE
    .\measure-time-to-run.ps1 -command  "& '.\connect-to-mggraph.ps1' -entraapp -AppId 'YOUR-APP-ID-HERE' -Tenant 'YOUR-ENTRAID-TENANT-DOMAIN-HERE.com' -AppSecret 'YOUR-APP-SECRET-HERE'"
    MAKE SURE the ps1 file is between '' before parsing its own parameters where applicable
    
.EXAMPLE
    .\measure-time-to-run.ps1 -command "& '.\Connect-ToMgGraph.ps1' -usessl -AppId 'YOUR-APP-ID-HERE' -TenantId 'YOUR-ENTRA-ID-TENANT-ID' -CertificateThumbprint 'SSL-CERT-THUMBPRINT'"
    MAKE SURE the ps1 file is between '' before parsing its own parameters where applicable

.NOTES
    Author: Thiago Beier (thiago.beier@gmail.com)
	Social: https://github.com/thiagogbeier/ https://thebeier.com/ https://www.linkedin.com/in/tbeier/ https://x.com/thiagobeier
    Date: September 11, 2024
#>

param (
    [string]$command
)

# Record the start time
$startTime = Get-Date

# Invoke the command
Invoke-Expression $command

# Record the end time
$endTime = Get-Date

# Calculate the total time taken
$timeTaken = $endTime - $startTime

# Output the total time taken
Write-Output "Total time taken (seconds): $($timeTaken.TotalSeconds)" #seconds
$minutesTaken = [math]::Round($timeTaken.TotalSeconds / 60, 2)  # Round to 2 decimal places
Write-Output "Total time taken (minutes): $minutesTaken" #minutes
