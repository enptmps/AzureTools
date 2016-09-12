AzureTools
======
A collection of scripts and tools for Azure discovery, build out and management ultimatly become part of a larger module

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