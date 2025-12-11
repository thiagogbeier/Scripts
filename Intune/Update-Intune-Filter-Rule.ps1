<#
.SYNOPSIS
Synchronizes Microsoft Intune assignment filter rules with device lists from Entra ID security groups or text files using Microsoft Graph API.

.DESCRIPTION
This script automates the process of updating Intune assignment filter rules with validated device lists.
It supports two input methods: Entra ID security groups or text files containing device names.

The script creates a working directory (c:\temp\YYYY\MM\DD\) for logging and backups, then performs the following operations:

- Validates the existence of the specified Intune assignment filter
- Accepts device input from either an Entra ID security group OR a text file (mutually exclusive)
- When using a text file, validates each device exists in Intune before adding to the filter
- Offers interactive prompts to create missing filters and groups
- Generates filter rules in the correct format for Intune assignment filters
- Updates the assignment filter with the validated device list
- Creates backup copies of all filters before making changes
- Provides detailed console output with color-coded status messages and progress indicators

Requires Microsoft Graph PowerShell SDK with appropriate permissions:
- Group.Read.All or Group.ReadWrite.All (for security group operations)
- Device.Read.All (for Intune device validation)
- DeviceManagementConfiguration.ReadWrite.All (for filter management)

.PARAMETER filterName
The display name of the Intune assignment filter to update or create.
If the filter doesn't exist, you'll be prompted to create it.
Default: "Test-Filter-001"

.PARAMETER GroupName
The display name of the Entra ID security group containing the target devices.
The script will retrieve all members from this group to populate the filter.
Cannot be used together with GroupMembersFromFile parameter.
Default: "Test-Group-001"

.PARAMETER GroupMembersFromFile
Path to a text file containing device names (one device name per line).
Each device name will be validated against Intune's device inventory before being added to the filter.
Blank lines are ignored. Devices not found in Intune will be reported but skipped.
Cannot be used together with GroupName parameter.
Example file format:
  DESKTOP-ABC123
  LAPTOP-XYZ789
  WORKSTATION-001

.EXAMPLE
.\Update-Intune-Filter-Rule.ps1
Runs with default values (Test-Filter-001 and Test-Group-001).
Prompts for confirmation before proceeding with defaults.

.EXAMPLE
.\Update-Intune-Filter-Rule.ps1 -filterName "Exclude - Norton" -GroupName "McAfee Install Phase 2"
Updates the "Exclude - Norton" filter with all devices that are members of the "McAfee Install Phase 2" security group.

.EXAMPLE
.\Update-Intune-Filter-Rule.ps1 -filterName "Pilot-Exclusions" -GroupMembersFromFile "C:\temp\pilot-devices.txt"
Validates each device name in the text file exists in Intune, then updates the "Pilot-Exclusions" filter
with the validated device list. Shows validation results with checkmarks for found devices.

.EXAMPLE
.\Update-Intune-Filter-Rule.ps1 -filterName "Test-Filter-001" -GroupName "Test-Group-001"
If filter or group doesn't exist, prompts to create them interactively.
Provides direct Entra Portal links for adding members to newly created groups.

.EXAMPLE
Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "DeviceManagementConfiguration.ReadWrite.All"
.\Update-Intune-Filter-Rule.ps1 -filterName "Production-Exclusions" -GroupName "Production Devices"
Connects to Microsoft Graph with all required permissions before running the script with custom parameters.

.NOTES
Author: Thiago Beier
Email: thiago.beier@gmail.com
Blog: https://thebeier.com
LinkedIn: https://www.linkedin.com/in/tbeier/
Twitter: https://twitter.com/thiagobeier
GitHub: https://github.com/thiagogbeier
Created: 03/06/2023
Updated: 12/11/2025
Version: 2.1

Prerequisites:
- PowerShell 5.1 or PowerShell 7+
- Microsoft.Graph PowerShell module (Install-Module Microsoft.Graph -Scope CurrentUser)
- Appropriate Microsoft Graph API permissions (see DESCRIPTION)
- Valid Microsoft 365/Intune tenant with appropriate licenses
- Devices must be enrolled in Intune for validation to succeed

Script Behavior:
- Creates timestamped log files in c:\temp\YYYY\MM\DD\
- Backs up all existing filters before making changes
- Validates all inputs before applying changes
- Gracefully handles empty groups and missing devices
- Provides detailed error messages and remediation guidance
- Exits safely without making changes if validation fails

Change Log:
v2.1 (12/11/2025):
- Fixed null reference errors when processing empty groups
- Improved error handling in continuation blocks after resource creation
- Enhanced validation for file-based device lists
- Added better messaging for empty device lists
- Fixed group member retrieval in post-creation workflow

v2.0 (12/11/2025):
- Migrated from deprecated AzureAD module to Microsoft.Graph module
- Added interactive prompts for creating missing filters and groups
- Enhanced error handling and user feedback with color-coded output
- Improved logging and transcript functionality
- Added support for empty group detection
- Added direct Entra Portal links for group management
- Added GroupMembersFromFile parameter to load device list from text file
- Added Intune device validation for file-based device lists
- Added parameter confirmation when running with default values
- Implemented parameter sets to prevent conflicting input methods

v1.0 (03/06/2023):
- Initial release with AzureAD module
- updated Intune filter rules based on security group members, removed old powershell module references

#>

[CmdletBinding(DefaultParameterSetName = "FromGroup")]
param(
    [Parameter(Mandatory = $false)]
    [string]$filterName = "Test-Filter-001",
    
    [Parameter(Mandatory = $false, ParameterSetName = "FromGroup")]
    [string]$GroupName = "Test-Group-001",
    
    [Parameter(Mandatory = $false, ParameterSetName = "FromFile")]
    [string]$GroupMembersFromFile
)

# Validate parameter usage
if ($PSBoundParameters.ContainsKey('GroupName') -and $PSBoundParameters.ContainsKey('GroupMembersFromFile')) {
    Write-Host "ERROR: Cannot use both -GroupName and -GroupMembersFromFile parameters together." -ForegroundColor Red
    Write-Host "Please use only one method to specify devices." -ForegroundColor Yellow
    return
}


#Powershell Modules
# Check if Microsoft.Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
    Write-Host ""
    Write-Host "WARNING: Microsoft.Graph module is not installed." -ForegroundColor Yellow
    Write-Host "This script requires the Microsoft.Graph PowerShell module to function." -ForegroundColor Yellow
    Write-Host ""
    $installModule = Read-Host "Do you want to install Microsoft.Graph module now? (Y/N)"
    
    if ($installModule -eq 'Y' -or $installModule -eq 'y') {
        Write-Host "Installing Microsoft.Graph module..." -ForegroundColor Cyan
        try {
            Install-Module Microsoft.Graph -Scope CurrentUser -Force
            Write-Host "Microsoft.Graph module installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "ERROR: Failed to install Microsoft.Graph module: $_" -ForegroundColor Red
            Write-Host "Please install manually using: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Yellow
            return
        }
    }
    else {
        Write-Host ""
        Write-Host "Cannot proceed without Microsoft.Graph module." -ForegroundColor Red
        Write-Host "Please install manually using: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Yellow
        return
    }
}

# Check if connected to Microsoft Graph
try {
    $context = Get-MgContext
    if (-not $context) {
        Write-Host ""
        Write-Host "WARNING: Not connected to Microsoft Graph." -ForegroundColor Yellow
        Write-Host "Required permissions: Group.ReadWrite.All, Device.Read.All, DeviceManagementConfiguration.ReadWrite.All" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please connect using:" -ForegroundColor Cyan
        Write-Host 'Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "DeviceManagementConfiguration.ReadWrite.All"' -ForegroundColor Gray
        Write-Host ""
        return
    }
    else {
        Write-Host "Connected to Microsoft Graph as: $($context.Account)" -ForegroundColor Green
    }
}
catch {
    Write-Host ""
    Write-Host "WARNING: Microsoft.Graph module loaded but not connected." -ForegroundColor Yellow
    Write-Host "Please connect using:" -ForegroundColor Cyan
    Write-Host 'Connect-MgGraph -Scopes "Group.ReadWrite.All", "Device.Read.All", "DeviceManagementConfiguration.ReadWrite.All"' -ForegroundColor Gray
    Write-Host ""
    return
}

# Check if parameters were explicitly provided by comparing with bound parameters
$parametersProvided = $PSBoundParameters.Count -gt 0

#region 00 - defaults
$date = Get-Date -Format "yyyy-MM-dd"
$fulldate = $date
$fulldate.Split("-")
$dtyear = $fulldate.Split("-")[0]
$dtmonth = $fulldate.Split("-")[1]
$dtday = $fulldate.Split("-")[2]
$workdir = "c:\temp\$dtyear\$dtmonth\$dtday"

if (Test-Path -Path $workdir) {
    Write-Host "Working dir folder exists: $workdir" -ForegroundColor Green
}
else {
    Write-Host "Working dir folder doesn't exist. Creating: $workdir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $workdir
}
Set-Location $workdir
#endregion

#region 01 - code
#Date and time
$dt = Get-Date -Format "dd-MM-yyyy-HH-mm-ss"
$LogFolder = "$workdir"
$logfile = "$LogFolder\graphapi-update-filters-$dt.log"
Start-Transcript -Path $logfile

# If no parameters provided, confirm default values
if (-not $parametersProvided) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "    NO PARAMETERS PROVIDED - USING DEFAULTS" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Default Filter Name:  " -NoNewline -ForegroundColor Cyan
    Write-Host "$filterName" -ForegroundColor White
    Write-Host "Default Group Name:   " -NoNewline -ForegroundColor Cyan
    Write-Host "$GroupName" -ForegroundColor White
    Write-Host ""
    $confirm = Read-Host "Do you want to proceed with these default values? (Y/N)"
    
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host ""
        Write-Host "Operation cancelled by user." -ForegroundColor Yellow
        Write-Host "To run with custom values, use:" -ForegroundColor Cyan
        Write-Host '.\Update-Intune-Filter-Rule.ps1 -filterName "YourFilterName" -GroupName "YourGroupName"' -ForegroundColor Gray
        Stop-Transcript
        return
    }
    Write-Host ""
    Write-Host "Proceeding with default values..." -ForegroundColor Green
    Write-Host ""
}

#Display parameters being used
Write-Host "Using Filter Name: $filterName" -ForegroundColor Cyan
if ($GroupMembersFromFile) {
    Write-Host "Using Device List File: $GroupMembersFromFile" -ForegroundColor Cyan
}
else {
    Write-Host "Using Group Name: $GroupName" -ForegroundColor Cyan
}
Write-Host ""

#work on filters
Write-Host "Fetching Intune filters..." -ForegroundColor Yellow
$Filters = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters"
$thisfilter = $Filters.value | Where-Object { $_.displayname -eq "$($filterName)" }

# Handle device list from file or group
$aadgroupsarray = @()
$useFileMode = $false

if ($GroupMembersFromFile) {
    $useFileMode = $true
    Write-Host "Reading devices from file: $GroupMembersFromFile" -ForegroundColor Yellow
    
    # Check if file exists
    if (-not (Test-Path -Path $GroupMembersFromFile)) {
        Write-Host "ERROR: File not found: $GroupMembersFromFile" -ForegroundColor Red
        Stop-Transcript
        return
    }
    
    # Read device names from file
    $devicesFromFile = Get-Content -Path $GroupMembersFromFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }
    Write-Host "Found $($devicesFromFile.Count) device names in file" -ForegroundColor Cyan
    
    # Validate devices exist in Intune
    Write-Host "Validating devices exist in Intune..." -ForegroundColor Yellow
    $validatedDevices = @()
    $notFoundDevices = @()
    
    foreach ($deviceName in $devicesFromFile) {
        Write-Host "  Checking: $deviceName" -NoNewline
        try {
            $intuneDevice = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=deviceName eq '$deviceName'"
            if ($intuneDevice.value.Count -gt 0) {
                $validatedDevices += $deviceName
                Write-Host " ✓" -ForegroundColor Green
            }
            else {
                $notFoundDevices += $deviceName
                Write-Host " ✗ Not found in Intune" -ForegroundColor Red
            }
        }
        catch {
            $notFoundDevices += $deviceName
            Write-Host " ✗ Error: $_" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Validation Results:" -ForegroundColor Cyan
    Write-Host "  Valid devices: $($validatedDevices.Count)" -ForegroundColor Green
    Write-Host "  Not found: $($notFoundDevices.Count)" -ForegroundColor Red
    
    if ($notFoundDevices.Count -gt 0) {
        Write-Host ""
        Write-Host "Devices not found in Intune:" -ForegroundColor Yellow
        $notFoundDevices | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    }
    
    if ($validatedDevices.Count -eq 0) {
        Write-Host ""
        Write-Host "ERROR: No valid devices found. Cannot proceed." -ForegroundColor Red
        Stop-Transcript
        return
    }
    
    $aadgroupsarray = $validatedDevices
    Write-Host ""
    $aadgroup = $true # Set to true to pass the check below
}
else {
    # Original group-based logic
    Write-Host "Searching for group: $GroupName" -ForegroundColor Yellow
    $aadgroup = Get-MgGroup -Filter "startsWith(displayName,'$GroupName')" -ConsistencyLevel eventual
}

#clear arrays (only if not in file mode, as we already populated aadgroupsarray)
if (-not $useFileMode) {
    $aadgroupsarray = ""
}
$currentrulelist1 = ""

if ($thisfilter -and $aadgroup) {
    #export Backup - all existing filters
    if ($useFileMode) {
        Write-Host "Filter found. Proceeding..." -ForegroundColor Green
    }
    else {
        Write-Host "Filter and Group found. Proceeding..." -ForegroundColor Green
    }
    Write-Host "Backing up all filters..." -ForegroundColor Yellow
    Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters" | ConvertTo-Json | Out-File -FilePath .\Intune-Filters-$dt.json

    Write-Host "Processing filter rules..." -ForegroundColor Yellow
    #working o filter
    $thisfilter.rule | Out-File thisfilter-$dt.txt
    $dd = ($thisfilter.rule -split ' or ') -ne ''
    $ee = $dd.Replace('(device.deviceName -eq "', "")
    $ff = $ee.Replace('")', "")
    $thisfilterdvclist = $ff | ForEach-Object { $_.trim() } | Sort-Object
    $currentFilterCount = ($thisfilterdvclist | Sort-Object -Unique).count
    Write-Host "Current filter has $currentFilterCount unique devices" -ForegroundColor Cyan

    # Get device list based on mode (file or group)
    if (-not $useFileMode) {
        #device list from AAD device group
        Write-Host "Retrieving group members..." -ForegroundColor Yellow
        $aadgroupsarray = @()
        # Loop through each item in the array and write it to the console
        foreach ($item in $GroupName) {
            Write-Host $item
            $aadgroup = Get-MgGroup -Filter "startsWith(displayName,'$item')" -ConsistencyLevel eventual
            $aadgroupmembers = Get-MgGroupMember -GroupId $aadgroup.Id -All
            $aadgroupsarray += $aadgroupmembers.AdditionalProperties.displayName
        }
        $uniqueGroupMemberCount = ($aadgroupsarray | Sort-Object -Unique).count
        Write-Host "Found $uniqueGroupMemberCount unique devices in group" -ForegroundColor Cyan
    }
    else {
        # aadgroupsarray already populated from file validation
        $uniqueCount = ($aadgroupsarray | Sort-Object -Unique).count
        Write-Host "Using $uniqueCount validated devices from file" -ForegroundColor Cyan
    }
    
    # Check if we have any devices to process
    if ($aadgroupsarray.Count -eq 0 -or [string]::IsNullOrWhiteSpace($aadgroupsarray)) {
        Write-Host ""
        Write-Host "WARNING: No devices found to add to filter." -ForegroundColor Yellow
        if ($useFileMode) {
            Write-Host "The file contained no valid devices registered in Intune." -ForegroundColor Yellow
        }
        else {
            Write-Host "The security group is empty. Please add members to continue." -ForegroundColor Yellow
        }
        Write-Host "Filter was not updated." -ForegroundColor Red
        Stop-Transcript
        return
    }
    
    $filterrulelist = $aadgroupsarray | Sort-Object -Unique

    #create array from graph api list
    #json rule format for devices from text file
    $currentrulelist1 = @()
    ForEach ($item in $filterrulelist) { 
        if (-not [string]::IsNullOrWhiteSpace($item)) {
            $newdevicetoadd = '(device.deviceName -eq \"' + $item.Trim() + '\")'
            $currentrulelist1 += $newdevicetoadd
        }
    }
    #list on screen
    Write-Host ""
    if ($useFileMode) {
        Write-Host "NEW List from File has: $($currentrulelist1.count) Devices" -ForegroundColor Green
    }
    else {
        Write-Host "NEW List from Security Group has: $($currentrulelist1.count) Devices" -ForegroundColor Green
    }

    #Create rule list to be parsed in JSON
    Write-Host "Creating JSON rule list..." -ForegroundColor Yellow
    Write-Host ""
    $JsonRuleList = ""
    $or = "or "
    $or.Length
    $newList = $currentrulelist1
    # Loop through each item in the array
    foreach ($item in $newList) {

        # Check if the current item is not the last item in the array
        if ($item -ne $newList[-1]) {
            # Concatenate the current item with the $or variable and append it to the output string
            $JsonRuleList += "$item $or"
        }
        else {
            # If the current item is the last item in the array, append it to the output string without the $or variable
            $JsonRuleList += "$item"
        }
    }

    # Output the final concatenated string
    Write-Host "JSON Rule List created successfully" -ForegroundColor Green

    #PATCH - Update filter 
    Write-Host "Filter: $($thisfilter.displayname) has ID: $($thisfilter.id)" -ForegroundColor Cyan
    $uri2 = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($thisfilter.id)"

    #JSON rule and rolescopetags. Only update RULE (add , remove objects + OR)
    $JSON = @"
{
"rule":"$($JsonRuleList)","roleScopeTags":["0"]
}
"@
 
    Write-Host "Updating filter..." -ForegroundColor Yellow
 
    Invoke-MgGraphRequest -Method PATCH -Uri $uri2 -Body $JSON -ContentType "application/json" #update filter rule
    
    Write-Host "Filter updated successfully!" -ForegroundColor Green

}
else { 
    Write-Host ""
    Write-Host "===== MISSING RESOURCES =====" -ForegroundColor Red
    
    # Handle missing filter
    if (-not $thisfilter) { 
        Write-Host "Filter '$filterName' not found" -ForegroundColor Red 
        Write-Host ""
        $createFilter = Read-Host "Do you want to create a new filter? (Y/N)"
        
        if ($createFilter -eq 'Y' -or $createFilter -eq 'y') {
            $newFilterName = Read-Host "Enter the new filter name (press Enter to use '$filterName')"
            if ([string]::IsNullOrWhiteSpace($newFilterName)) {
                $newFilterName = $filterName
            }
            
            Write-Host "Creating new filter: $newFilterName" -ForegroundColor Yellow
            
            # Create empty filter with basic rule
            $newFilterBody = @{
                displayName   = $newFilterName
                description   = "Auto-created filter for device exclusions"
                platform      = "windows10AndLater"
                rule          = "(device.deviceName -eq `"placeholder`")"
                roleScopeTags = @("0")
            } | ConvertTo-Json
            
            try {
                $newFilter = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters" -Body $newFilterBody -ContentType "application/json"
                Write-Host "Filter created successfully with ID: $($newFilter.id)" -ForegroundColor Green
                $thisfilter = $newFilter
                $filterName = $newFilterName
            }
            catch {
                Write-Host "ERROR: Failed to create filter: $_" -ForegroundColor Red
            }
        }
    }
    
    # Handle missing group (only if not using file mode)
    if (-not $aadgroup -and -not $useFileMode) { 
        Write-Host "Group '$GroupName' not found" -ForegroundColor Red 
        Write-Host ""
        $createGroup = Read-Host "Do you want to create a new security group? (Y/N)"
        
        if ($createGroup -eq 'Y' -or $createGroup -eq 'y') {
            $newGroupName = Read-Host "Enter the new group name (press Enter to use '$GroupName')"
            if ([string]::IsNullOrWhiteSpace($newGroupName)) {
                $newGroupName = $GroupName
            }
            
            $groupDescription = Read-Host "Enter group description (optional)"
            if ([string]::IsNullOrWhiteSpace($groupDescription)) {
                $groupDescription = "Auto-created security group for device management"
            }
            
            Write-Host "Creating new security group: $newGroupName" -ForegroundColor Yellow
            
            try {
                $newGroup = New-MgGroup -DisplayName $newGroupName -Description $groupDescription -MailEnabled:$false -SecurityEnabled:$true -MailNickname ($newGroupName -replace '\s', '')
                Write-Host "Security group created successfully!" -ForegroundColor Green
                Write-Host "Group ID: $($newGroup.Id)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "IMPORTANT: Please go to Entra Portal and add members to this group manually:" -ForegroundColor Yellow
                Write-Host "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/$($newGroup.Id)" -ForegroundColor Cyan
                $aadgroup = $newGroup
            }
            catch {
                Write-Host "ERROR: Failed to create group: $_" -ForegroundColor Red
            }
        }
    }
    
    # If both resources now exist, ask if user wants to continue
    if ($thisfilter -and $aadgroup) {
        Write-Host ""
        Write-Host "Both filter and group now exist." -ForegroundColor Green
        $continue = Read-Host "Do you want to continue with the update? (Y/N)"
        
        if ($continue -ne 'Y' -and $continue -ne 'y') {
            Write-Host "Operation cancelled by user." -ForegroundColor Yellow
            Stop-Transcript
            return
        }
        
        # If continuing, we need to run the main logic
        Write-Host ""
        Write-Host "Proceeding with filter update..." -ForegroundColor Green
        
        # Get device list based on mode (file or group)
        if ($useFileMode) {
            # aadgroupsarray already populated from file validation earlier
            Write-Host "Using validated devices from file..." -ForegroundColor Yellow
        }
        else {
            # Note: The group might be empty, so we need to handle that
            Write-Host "Retrieving group members..." -ForegroundColor Yellow
            $aadgroupsarray = @()
            
            foreach ($item in $GroupName) {
                Write-Host $item
                $aadgroup = Get-MgGroup -Filter "startsWith(displayName,'$item')" -ConsistencyLevel eventual
                
                if ($aadgroup) {
                    $aadgroupmembers = Get-MgGroupMember -GroupId $aadgroup.Id -All
                    
                    if ($aadgroupmembers) {
                        $aadgroupsarray += $aadgroupmembers.AdditionalProperties.displayName
                    }
                }
            }
        }
        
        if ($aadgroupsarray.Count -eq 0) {
            Write-Host "WARNING: No members found to add to filter." -ForegroundColor Yellow
            if (-not $useFileMode) {
                Write-Host "Please add members to the group first before running this script again." -ForegroundColor Yellow
            }
        }
        else {
            $uniqueGroupMemberCount = ($aadgroupsarray | Sort-Object -Unique).count
            if ($useFileMode) {
                Write-Host "Found $uniqueGroupMemberCount unique devices from file" -ForegroundColor Cyan
            }
            else {
                Write-Host "Found $uniqueGroupMemberCount unique devices in group" -ForegroundColor Cyan
            }
            $filterrulelist = $aadgroupsarray | Sort-Object -Unique
            
            # Create rule list
            $currentrulelist1 = @()
            ForEach ($item in $filterrulelist.trim()) { 
                $newdevicetoadd = '(device.deviceName -eq \"' + $item + '\")'
                $currentrulelist1 += $newdevicetoadd
            }
            
            if ($useFileMode) {
                Write-Host "NEW List from File has: $($currentrulelist1.count) Devices" -ForegroundColor Green
            }
            else {
                Write-Host "NEW List from Security Group has: $($currentrulelist1.count) Devices" -ForegroundColor Green
            }
            
            # Create JSON rule list
            $JsonRuleList = ""
            $or = "or "
            $newList = $currentrulelist1
            
            foreach ($item in $newList) {
                if ($item -ne $newList[-1]) {
                    $JsonRuleList += "$item $or"
                }
                else {
                    $JsonRuleList += "$item"
                }
            }
            
            # Update filter
            Write-Host "Filter: $($thisfilter.displayname) has ID: $($thisfilter.id)" -ForegroundColor Cyan
            $uri2 = "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($thisfilter.id)"
            
            $JSON = @"
{
"rule":"$($JsonRuleList)","roleScopeTags":["0"]
}
"@
            
            Write-Host "Updating filter..." -ForegroundColor Yellow
            Invoke-MgGraphRequest -Method PATCH -Uri $uri2 -Body $JSON -ContentType "application/json"
            Write-Host "Filter updated successfully!" -ForegroundColor Green
        }
    }
    else {
        Write-Host ""
        Write-Host "Cannot proceed without both filter and group. Exiting." -ForegroundColor Red
    }
}


Stop-Transcript

#endregion