<# 
.SYNOPSIS
    Export VM .RDP files for a given Azure resource group. 
.DESCRIPTION
    The following script will export all VM .RDP connections to a provided path.  The folder must be created by hand before the script is run. 
.PARAMETER ServiceName
    Cloud Service the Azure VM is running under. 
.PARAMETER SubscriptionName 
    Name of the Azure subscription being selected. 
#> 
 
Param ( 
[parameter(Mandatory=$true)][String] $Path,
[parameter(Mandatory=$true)][String] $rgName
#[parameter(Mandatory=$false)][String] $SubscriptionId
) 
  
#Select-azuresubscription "$SubscriptionId" 
 
if (!(Test-Path $Path)){
    Write-Output "Path $Path does not exist"
} else {
    $VMset = (Get-AzureRMVM $rgName)
    Write-Verbose "Found $($VMset.count) VMs in $rgName"
    ForEach ($VM in $VMset) { 
        $filename = $vm.name + '.rdp' 
        $rdpexportfile = (Join-Path -Path $Path  -ChildPath $filename) 
        Get-AzureRMRemoteDesktopFile -ResourceGroupName $rgName -Name $vm.Name -LocalPath $rdpexportfile
        Write-Verbose "Saved RDP file for $($vm.name) as $rdpexportfile"
    }
}