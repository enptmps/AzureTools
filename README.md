AzureTools
======
A collection of scripts and tools for Azure discovery, build out and management ultimatly become part of a larger module

<br />

# Download-AzureRDPFiles.ps1
Tool to grab all the RDP connection files for all VMs in a given resource groups

Saves them to a provided path that must exist already (or the script will halt and say so)

## Usage:
```powershell
./Download-AzureRDPFiles.ps1 -Path <Destination> -rgName <ResourceGroup>
```
Expect further output with the -Verbose flag
```
VERBOSE: Found x VMs in <RGName>
VERBOSE: Saved RDP file for <VMName> as <PATH\VMNAME.rdp>
```

<br />

# New-AzureLabVMGroup.ps1
Script that reads the accompanying azurelab.csv to generate Azure IaaS VMs in the defined resource groups

Populate some static values within the script with your tenant and subscription details, or pass them from the pipeline

```powershell
$AzureUserID    = "..."
$AzureTenantID  = "..."
$azSubId        = "..."
$StorageAcct    = "..."
$Location       = "..."
$subnetName     = "..."
$vnetName       = "..."
```
## Usage:
```powershell
./New-AzureVMLabGroup.ps1
```
Runs the script in test mode, does not create the infrastructure but outputs the configuration to the shell

```powershell
./New-AzureVMLabGroup.ps1 -ForceRun
```
Runs the script in deploy mode, deploying the configured systems to the azure tenant and subscription stipulated

<br />

# Test-NetworkTurnup.ps1
Script that creates initial infrastructure for new Azure deployments

Remember to populate the variables in the file with your tenant parameters and requirements

## Usage:
```powershell
./Test-NetworkTurnup.ps1
```