<#
.SYNOPSIS
    New-AzureVmLabGroup.ps1
    create an Azure RM virtual machine lab using a CSV file for input

.DESCRIPTION
    This script is intended to ruin a perfectly good Azure tenant environment
 
.PARAMETER AzureUserID
    Show a progressbar displaying the current operation.
 
.PARAMETER InputFIle
    Path and filename to CSV parameters input file

.PARAMETER TestMode
    If TestMode is True, no actions are performed, only debug print-out

.PARAMETER Revert
    Removes all Azure RM Resource Groups specified in the CSV input file

.EXAMPLE
     
 
.NOTES
    FileName:    New-AzureVmLabGroup.ps1
    Author:      David Stein
    Created:     2016-08-11
    Updated:     2016-10-04
    Version:     1.1.0

    referenced: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-ps-create/
#>

param (
    [parameter(Mandatory=$False)] [string] $AzureUserID   = "ds0934@hotmail.com",
    [parameter(Mandatory=$False)] [string] $AzureTenantID = "03b55dea-ce59-4531-b1ef-a590e7dbd162",
    [parameter(Mandatory=$False)] [string] $azSubId     = "af15d920-86d8-4062-8801-d11eee853114",
    [parameter(Mandatory=$False)] [string] $InputFile   = "azurelab.csv",
    [parameter(Mandatory=$False)] [string] $LocalAdmin  = "admin123",
    [parameter(Mandatory=$False)] [bool] $TestMode = $True,
    [parameter(Mandatory=$False)] [switch] $Revert
)
Import-Module ".\AzureVMLab.psm1"

if (!($Revert)) {

    if ($azCred -eq $null) {
        $azCred = Login-AzureRmAccount -EnvironmentName "AzureCloud" -AccountId $AzureUserID -SubscriptionId $azSubId -TenantId $AzureTenantID
        if ($azCred -eq $null) {
            Write-Error "authentication was not processed"
            break
        }
    }

    $csvData = Request-EP-CsvData -InputFile $InputFile

    if ($csvData -ne $null) {
        Write-Host "input data loaded successfully." -ForegroundColor Cyan

        if ($locAdmin -eq $null) {
        if (!($lulist.Contains($lu))) {
            Write-Output "setting credentials for local administrator account..."
            $LocalUser = Get-Credential -UserName $lu -Message "Enter the Password for this account"
            $lulist += $lu
        }

        foreach ($row in $csvData) {
            if (!(Test-EP-CommentLine $row)) {
                Write-Host "----------- virtual machine $($row.Name) ------------" -ForegroundColor Green
                $rg = $(Request-EP-AzureResourceGroup $row $TestMode)

                if ($rg -ne $null) {
                    $stAcct = Request-EP-AzureStorageAccount $row $TestMode
                    $stURI  = Request-EP-AzureBlobURI $stAcct $TestMode
                    $vnet   = Request-EP-AzureVmNetwork $row $TestMode
                    $nic    = Request-EP-AzureVMNIC $row $vnet $TestMode
                    $osDiskUri = Request-EP-AzureDiskURI -CsvRow $row -BlobURI $stURI -Testing $TestMode
                    $vm     = Provision-EP-VM -CsvRow $row -Nic $nic -DiskURI $osDiskUri -Testing $TestMode
                }
                elseif ($TestMode -ne $True) {
                    Write-Host "error: failed to create resource group" -ForegroundColor Red
                }
            }
        }
    }

    Write-Output "unloading module..."
    Remove-Module "AzureVMLab"
}
else {
    $csvData = Request-EP-CsvData -InputFile $InputFile
    Revert-EP-Resources -CsvDataSet $csvData
}
Write-Output "Finished!!!"
