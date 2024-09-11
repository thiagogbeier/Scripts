<#PSScriptInfo
.VERSION 1.0.1
.GUID
.AUTHOR Thiago Beier forked authentication method from Andrew S Taylor Microsoft MVP
.COMPANYNAME
.COPYRIGHT GPL
.TAGS intune endpoint MEM autopilot
.LICENSEURI
.PROJECTURI
.ICONURI
.EXTERNALMODULEDEPENDENCIES
.REQUIREDSCRIPTS
.EXTERNALSCRIPTDEPENDENCIES
.RELEASENOTES
v1.0.1 - Added prerequisites check, added devicecode and interactive logon parameters
#>

<#
.SYNOPSIS
    This script connects to Microsoft Graph using different authentication methods, including Interactive, Device Code, App Secret, Certificate Thumbprint, and specific scopes.

.DESCRIPTION
    This PowerShell script provides three modes of authentication with Microsoft Graph:
    - Scopes only: Connect using a specific set of read-only scopes.
    - App Secret: Authenticate using client credentials (AppId, AppSecret, and Tenant).
    - SSL Certificate: Authenticate using an SSL certificate.

.PARAMETER devicecode
    Executes the script using device code to authenticate. Opens Browser (Default) asks user to authenticate.

.PARAMETER interactive
    Executes the script using interactive only to authenticate. Opens Browser (Default) asks user to authenticate.

.PARAMETER scopesonly
    Executes the script using scopes only to authenticate.

.PARAMETER scopesonly
    Executes the script using scopes only to authenticate.

.PARAMETER entraapp
    Executes the script using App-based authentication with AppId, AppSecret, and Tenant.

.PARAMETER usessl
    Executes the script using certificate-based authentication with AppId, TenantId, and CertificateThumbprint.

.PARAMETER AppId
    The Azure AD Application (client) ID.

.PARAMETER AppSecret
    The client secret for the Azure AD application (required for -entraapp).

.PARAMETER Tenant
    The tenant domain or ID (required for -entraapp).

.PARAMETER TenantId
    The Azure AD Tenant ID (required for -usessl).

.PARAMETER CertificateThumbprint
    The SSL certificate thumbprint (required for -usessl).

.EXAMPLE
    .\script.ps1 -devicecode
    Connects using authenticated user consented scopes/permissions.

.EXAMPLE
    .\script.ps1 -interactive
    Connects using authenticated user consented scopes/permissions.
        
.EXAMPLE
    .\script.ps1 -scopesonly
    Connects using read-only scopes.

.EXAMPLE
    .\script.ps1 -entraapp -AppId "client-id-or-entra-app-id-here" -AppSecret "password-here" -Tenant "your-tenant-domain-here"
    Connects using App-based authentication with client credentials.

.EXAMPLE
    .\script.ps1 -usessl -AppId "client-id-or-entra-app-id-here" -TenantId "your-tenant-id-here" -CertificateThumbprint "your-ssl-certificate-thumbprint-here"
    Connects using certificate-based authentication.

.NOTES
    Author: Thiago Beier (thiago.beier@gmail.com)
	Social: https://x.com/thiagobeier https://thebeier.com/ https://www.linkedin.com/in/tbeier/
    Date: September 11, 2024
#>


param (
    [string]$AppId,
    [string]$TenantId,
    [string]$AppSecret,
    [string]$CertificateThumbprint,
    [string]$Tenant,
    [switch]$scopesonly,    # If true, execute the scopes only block
    [switch]$entraapp,  # If true, execute the entra app block
    [switch]$usessl,    # If true, execute the SSL certificate block
    [switch]$interactive,    # If true, execute the interactive block
    [switch]$devicecode    # If true, execute the device code block
)

#region PowerShell modules and NuGet

function Install-GraphModules {
    #region PowerShell modules and NuGet

    # Get NuGet
    $provider = Get-PackageProvider NuGet -ErrorAction Ignore
    if (-not $provider) {
        Write-Host "Installing provider NuGet"
        Find-PackageProvider -Name NuGet -ForceBootstrap -IncludeDependencies
    }

    # Get Graph Authentication module (and dependencies)
    $module = Import-Module microsoft.graph.authentication -PassThru -ErrorAction Ignore
    if (-not $module) {
        Write-Host "Installing module microsoft.graph.authentication"
        Install-Module microsoft.graph.authentication -Force -ErrorAction Ignore -MaximumVersion 2.9.1
    }

    $module2 = Import-Module Microsoft.Graph.Identity.DirectoryManagement -PassThru -ErrorAction Ignore
    if (-not $module2) {
        Write-Host "Installing module MS Graph Identity Management"
        Install-Module Microsoft.Graph.Identity.DirectoryManagement -Force -ErrorAction Ignore
    }
    Import-Module microsoft.graph.Identity.DirectoryManagement -Scope Global

    $module3 = Import-Module Microsoft.Graph.Groups -PassThru -ErrorAction Ignore
    if (-not $module3) {
        Write-Host "Installing module MS Graph Groups"
        Install-Module Microsoft.Graph.Groups -Force -ErrorAction Ignore
    }
    Import-Module Microsoft.Graph.Groups -Scope Global

    $module4 = Import-Module Microsoft.Graph.Users -PassThru -ErrorAction Ignore
    if (-not $module4) {
        Write-Host "Installing module MS Graph Users"
        Install-Module Microsoft.Graph.Users -Force -ErrorAction Ignore
        Import-Module Microsoft.Graph.Users -Scope Global
    }

    #endregion
}

       

#engregion

# If -entraapp is provided, enforce that AppId, AppSecret, and Tenant are required
if ($entraapp) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules


    if (-not $AppId) {
        throw "Error: The -AppId parameter is required when using -entraapp."
    }
    if (-not $AppSecret) {
        throw "Error: The -AppSecret parameter is required when using -entraapp."
    }
    if (-not $Tenant) {
        throw "Error: The -Tenant parameter is required when using -entraapp."
    }
}


# If -entraapp is provided, enforce that AppId, AppSecret, and Tenant are required
if ($usessl) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules


    if (-not $AppId) {
        throw "Error: The -AppId parameter is required when using -usessl."
    }
    if (-not $TenantId) {
        throw "Error: The -TenantId parameter is required when using -usessl."
    }
    if (-not $CertificateThumbprint) {
        throw "Error: The -CertificateThumbprint parameter is required when using -usessl."
    }
}

# Check for -scopesonly parameter
if ($scopesonly) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules


    #region scopesReadOnly ask for authentication
    $scopesReadOnly = @(
        "Chat.ReadWrite.All"
        "Directory.Read.All"
        "Group.Read.All"
    )
 
    Import-Module Microsoft.Graph.Authentication
    Connect-MgGraph -Scopes $scopesReadOnly
    Write-Host "This session current permissions `n" -foregroundcolor cyan
	Get-MgContext | Select-Object -ExpandProperty Scopes
	write-host "`n"
    #(Get-MgContext).scopes
	Write-Host "Please run Disconnect-mggraph to disconnect `n" -foregroundcolor darkyellow
    #disconnect-MgGraph
    #endregion
}

# Check for -entraapp parameter
if ($entraapp) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules

	#region app secret
	# Populate with the App Registration details and Tenant ID to validate manually
	#$appid = ''
	#$tenantid = ''
	#$appsecret = ''
	Import-Module Microsoft.Graph.Authentication
	$version = (Get-Module microsoft.graph.authentication | Select-Object -ExpandProperty Version).Major
	$body = @{
	grant_type    = "client_credentials"
	client_id     = $AppId
	client_secret = $AppSecret
	scope         = "https://graph.microsoft.com/.default"
	}

	$response = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $body
	$accessToken = $response.access_token
	if ($version -eq 2) {
	Write-Host "Version 2 module detected"
	$accesstokenfinal = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
	}
	else {
	Write-Host "Version 1 Module Detected"
	Select-MgProfile -Name Beta
	$accesstokenfinal = $accessToken
	}
	$graph = Connect-MgGraph -AccessToken $accesstokenfinal 
	Write-Host "Connected to tenant $Tenant using app-based authentication"

	#Get-MgContext
	Write-Host "This session current permissions `n" -foregroundcolor cyan
	Get-MgContext | Select-Object -ExpandProperty Scopes
	write-host "`n"
	Write-Host "Please run Disconnect-mggraph to disconnect `n" -foregroundcolor darkyellow
	#disconnect-MgGraph
	#endregion
}

# Check for -usessl parameter
if ($usessl) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules


    #region ssl certificate authentication
    Connect-MgGraph -ClientId $AppId -TenantId $TenantId -CertificateThumbprint $CertificateThumbprint
    #Get-MgContext
    Write-Host "This session current permissions `n" -foregroundcolor cyan
	Get-MgContext | Select-Object -ExpandProperty Scopes
	write-host "`n"
    #(Get-MgContext).scopes
	Write-Host "Please run Disconnect-mggraph to disconnect `n" -foregroundcolor darkyellow
    #disconnect-MgGraph
    #endregion
}


# Check for -interactive parameter
if ($interactive) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules

    Connect-MgGraph
    Write-Host "This session current permissions `n" -foregroundcolor cyan
	Get-MgContext | Select-Object -ExpandProperty Scopes
	write-host "`n"
    #(Get-MgContext).scopes
	Write-Host "Please run Disconnect-mggraph to disconnect `n" -foregroundcolor darkyellow
    }


# Check for -devicecode parameter
if ($devicecode) {

# Call the function
Write-Host "Checking NuGet and PowerShell dependencies `n" -foregroundcolor cyan
Install-GraphModules


    #Start Browser
    start-process https://microsoft.com/devicelogin

    #Wait for the user to enter the code provided on Screen to authenticate on opened Browser (Default)
    Connect-MgGraph -UseDeviceCode
    
    Write-Host "This session current permissions `n" -foregroundcolor cyan
	Get-MgContext | Select-Object -ExpandProperty Scopes
	write-host "`n"
    #(Get-MgContext).scopes
	Write-Host "Please run Disconnect-mggraph to disconnect `n" -foregroundcolor darkyellow
    }