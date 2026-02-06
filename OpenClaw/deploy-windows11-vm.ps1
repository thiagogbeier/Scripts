<#
.SYNOPSIS
Deploys a Windows 11 Virtual Machine on Azure with Node.js and OpenClaw pre-installed.

.DESCRIPTION
This script automates the end-to-end deployment of a Windows 11 Pro VM in Microsoft Azure,
including the installation of development tools required to run OpenClaw.

The deployment process includes:
- Creating an Azure resource group (if it doesn't exist)
- Provisioning a Windows 11 Pro 24H2 VM (Standard_B2s - 4GB memory)
- Configuring RDP access via a public IP with NSG rules
- Installing Chocolatey package manager on the VM
- Installing Git, CMake, and Visual Studio 2022 Build Tools
- Installing Node.js LTS via Chocolatey
- Installing OpenClaw globally via npm
- Configuring system PATH environment variables for Node.js and npm

The script supports a -WhatIf mode that previews all commands without executing them,
allowing you to review the deployment plan before committing.

Prerequisites:
- Azure CLI (az) installed and available in PATH
- Authenticated Azure session (run 'az login' before executing)
- An active Azure subscription with permissions to create resources
- PowerShell 5.1 or PowerShell 7+

.PARAMETER WhatIf
When specified, the script previews all commands without executing them.
Use this to review the deployment plan before making any changes.

.EXAMPLE
.\deploy-windows11-vm.ps1
Deploys the Windows 11 VM with all default settings (Standard_B2s in Canada Central)
and installs Node.js and OpenClaw.

.EXAMPLE
.\deploy-windows11-vm.ps1 -WhatIf
Previews all deployment steps without creating any Azure resources.
Useful for reviewing the deployment plan before execution.

.EXAMPLE
az login
.\deploy-windows11-vm.ps1
Logs in to Azure first, then deploys the VM with default configuration.

.EXAMPLE
az account set --subscription "your-subscription-id"
.\deploy-windows11-vm.ps1
Sets a specific Azure subscription before deploying the VM.

.NOTES
Author: Thiago Beier
Email: thiago.beier@gmail.com
Blog: https://thebeier.com
LinkedIn: https://www.linkedin.com/in/tbeier/
Twitter: https://twitter.com/thiagobeier
GitHub: https://github.com/thiagogbeier
Created: 02/06/2026
Updated: 02/06/2026
Version: 1.0

Default Configuration:
- Resource Group: openclaw-rg
- VM Name: win11-oclaw
- Location: canadacentral
- VM Size: Standard_B2s (2 vCPUs, 4GB RAM)
- Image: Windows 11 Pro 24H2
- Admin User: thiago
- Software: Chocolatey, Git, CMake, VS Build Tools, Node.js LTS, OpenClaw

Post-Deployment:
- Connect via RDP using the public IP displayed at the end
- OpenClaw is available globally via the 'openclaw' command
- To resize the VM, see the commented section at the end of the script

Change Log:
v1.0 (02/06/2026):
- Initial release
- Automated VM provisioning with Windows 11 Pro 24H2
- Chocolatey-based software installation pipeline
- WhatIf support for dry-run previews
- Invoke-AzCommand helper for consistent command execution
#>

# ============================================
# WhatIf Parameter - Set to $true to preview commands without executing
# ============================================
param(
    [switch]$WhatIf
)

# ============================================
# Disclaimer - User must accept before proceeding
# ============================================

Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Yellow
Write-Host "                              DISCLAIMER" -ForegroundColor Yellow
Write-Host "=========================================================================" -ForegroundColor Yellow
Write-Host ""

Write-Host "This sample script is NOT SUPPORTED under any Microsoft standard support" -ForegroundColor Cyan
Write-Host "program or service." -ForegroundColor Cyan
Write-Host ""
Write-Host "The sample script is provided AS IS without warranty of any kind." -ForegroundColor Cyan
Write-Host "Microsoft further disclaims all implied warranties including, without" -ForegroundColor Cyan
Write-Host "limitation, any implied warranties of merchantability or fitness for a" -ForegroundColor Cyan
Write-Host "particular purpose." -ForegroundColor Cyan
Write-Host ""
Write-Host "The entire risk arising out of the use or performance of this sample" -ForegroundColor Cyan
Write-Host "script and documentation remains with the user." -ForegroundColor Cyan
Write-Host ""
Write-Host "In no event shall Microsoft, its authors, employees, or any contributors" -ForegroundColor Cyan
Write-Host "be liable for any damages whatsoever (including, without limitation," -ForegroundColor Cyan
Write-Host "damages for loss of business profits, business interruption, loss of" -ForegroundColor Cyan
Write-Host "business information, or other pecuniary loss) arising out of the use" -ForegroundColor Cyan
Write-Host "of or inability to use this sample script or documentation, even if" -ForegroundColor Cyan
Write-Host "Microsoft has been advised of the possibility of such damages." -ForegroundColor Cyan
Write-Host ""
Write-Host "This script is provided by a Microsoft employee IN A PERSONAL CAPACITY" -ForegroundColor Cyan
Write-Host "and does not represent official guidance, support, or endorsement from" -ForegroundColor Cyan
Write-Host "Microsoft." -ForegroundColor Cyan
Write-Host ""
Write-Host "=========================================================================" -ForegroundColor Yellow
Write-Host ""

$acceptDisclaimer = Read-Host "Do you accept this disclaimer and wish to proceed? (Y/N)"
if ($acceptDisclaimer -ne 'Y' -and $acceptDisclaimer -ne 'y') {
    Write-Host ""
    Write-Host "Disclaimer not accepted. Script execution cancelled." -ForegroundColor Red
    return
}
Write-Host ""
Write-Host "Disclaimer accepted. Proceeding..." -ForegroundColor Green
Write-Host ""

# ============================================
# Prerequisite Check - Azure CLI
# ============================================
$azCmd = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCmd) {
    Write-Host ""
    Write-Host "ERROR: Azure CLI (az) is not installed or not found in PATH." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install Azure CLI from:" -ForegroundColor Yellow
    Write-Host "  https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Or install via winget:" -ForegroundColor Yellow
    Write-Host "  winget install Microsoft.AzureCLI" -ForegroundColor Gray
    Write-Host ""
    return
}

# Verify logged-in session
$azAccount = az account show 2>$null | ConvertFrom-Json
if (-not $azAccount) {
    Write-Host ""
    Write-Host "WARNING: Not logged in to Azure CLI." -ForegroundColor Yellow
    Write-Host "Please log in using:" -ForegroundColor Yellow
    Write-Host "  az login" -ForegroundColor Gray
    Write-Host ""
    return
}
Write-Host "Azure CLI authenticated as: $($azAccount.user.name)" -ForegroundColor Green
Write-Host "Subscription: $($azAccount.name) ($($azAccount.id))" -ForegroundColor Green
Write-Host ""

# Helper function to run or preview commands
function Invoke-AzCommand {
    param(
        [string]$Description,
        [scriptblock]$Command
    )
    
    if ($WhatIf) {
        Write-Host "[WhatIf] Would execute: $Description" -ForegroundColor Yellow
        Write-Host "[WhatIf] Command: $($Command.ToString())" -ForegroundColor DarkYellow
        return $null
    }
    else {
        Write-Host "Executing: $Description" -ForegroundColor Green
        return & $Command
    }
}

# ============================================
# Configuration Variables - Modify as needed
# ============================================
$RESOURCE_GROUP = "openclaw-rg"
$VM_NAME = "win11-oclaw"  # Max 15 chars for Windows computer name
$LOCATION = "canadacentral"  # e.g., eastus, westus2
$ADMIN_USERNAME = "thiago"
$ADMIN_PASSWORD = "P@ssw0rd1234!"  # Use a strong password in production
$VM_SIZE = "Standard_B2s"  # 4GB memory

# ============================================
# Check if resource group exists, create if not
# ============================================
Write-Host "Checking resource group $RESOURCE_GROUP..."
if (-not $WhatIf) {
    $rgExists = az group show --name $RESOURCE_GROUP 2>$null
}
else {
    $rgExists = $null
}
if (-not $rgExists) {
    Invoke-AzCommand -Description "Create resource group $RESOURCE_GROUP in $LOCATION" -Command {
        az group create --name $RESOURCE_GROUP --location $LOCATION
    }
}

# ============================================
# Create Windows 11 Virtual Machine
# ============================================
Invoke-AzCommand -Description "Create Windows 11 VM '$VM_NAME' with size $VM_SIZE" -Command {
    az vm create `
        --resource-group $RESOURCE_GROUP `
        --name $VM_NAME `
        --image MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest `
        --size $VM_SIZE `
        --admin-username $ADMIN_USERNAME `
        --admin-password $ADMIN_PASSWORD `
        --public-ip-sku Standard `
        --nsg-rule RDP
}

Write-Host "VM created successfully!"

# ============================================
# Get VM Public IP
# ============================================
Write-Host "Getting VM public IP..."
if (-not $WhatIf) {
    $PUBLIC_IP = az vm show -d -g $RESOURCE_GROUP -n $VM_NAME --query publicIps -o tsv
    Write-Host "VM Public IP: $PUBLIC_IP"
}
else {
    $PUBLIC_IP = "<WhatIf: IP will be assigned after VM creation>"
    Write-Host "[WhatIf] Would retrieve VM public IP after creation" -ForegroundColor Yellow
}

# ============================================
# Install Node.js and openclaw using az vm run-command
# ============================================
Write-Host "Installing software using az vm run-command..."

# Step 1: Install Chocolatey
Invoke-AzCommand -Description "Step 1/5: Install Chocolatey on VM" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
}

# Step 2: Install Git (required by npm for some packages)
Invoke-AzCommand -Description "Step 2/5: Install Git on VM" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts "C:\ProgramData\chocolatey\bin\choco.exe install git -y"
}

# Step 3: Install CMake and Visual Studio Build Tools (required for native modules)
Invoke-AzCommand -Description "Step 3/5: Install CMake and Visual Studio Build Tools on VM" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts "C:\ProgramData\chocolatey\bin\choco.exe install cmake visualstudio2022buildtools visualstudio2022-workload-vctools -y"
}

# Step 4: Install Node.js LTS
Invoke-AzCommand -Description "Step 4/5: Install Node.js LTS on VM" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts "`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User'); C:\ProgramData\chocolatey\bin\choco.exe install nodejs-lts -y"
}

# Step 5: Install openclaw globally
Invoke-AzCommand -Description "Step 5/5: Install openclaw globally via npm" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts "`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User'); npm install -g openclaw"
}

# Step 6: Add npm global packages to system PATH
Invoke-AzCommand -Description "Step 6: Add npm global path to system environment variables" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts @"
`$npmGlobalPath = 'C:\Program Files\nodejs';
`$npmUserPath = [System.Environment]::GetFolderPath('ApplicationData') + '\npm';
`$currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine');
if (`$currentPath -notlike "*`$npmGlobalPath*") {
    `$newPath = `$currentPath + ';' + `$npmGlobalPath;
    [System.Environment]::SetEnvironmentVariable('Path', `$newPath, 'Machine');
    Write-Host 'Added Node.js path to system PATH';
}
if (`$currentPath -notlike "*`$npmUserPath*") {
    `$newPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + `$npmUserPath;
    [System.Environment]::SetEnvironmentVariable('Path', `$newPath, 'Machine');
    Write-Host 'Added npm global path to system PATH';
}
Write-Host 'Environment variables updated successfully!';
"@
}

# Verify installation
Invoke-AzCommand -Description "Verify Node.js, npm, and openclaw installation" -Command {
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME --command-id RunPowerShellScript `
        --scripts "`$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User'); Write-Host 'Node.js version:'; node --version; Write-Host 'npm version:'; npm --version; Write-Host 'openclaw:'; npm list -g openclaw"
}

Write-Host "============================================"
Write-Host "Deployment completed!"
Write-Host "============================================"
Write-Host "Resource Group: $RESOURCE_GROUP"
Write-Host "VM Name: $VM_NAME"
Write-Host "Public IP: $PUBLIC_IP"
Write-Host "Admin Username: $ADMIN_USERNAME"
Write-Host "VM Size: $VM_SIZE (4GB memory)"
Write-Host ""
Write-Host "Connect via RDP: mstsc /v:$PUBLIC_IP"
Write-Host "============================================"
