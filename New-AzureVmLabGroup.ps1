<#
.SYNOPSIS
 
 
.DESCRIPTION
 
 
.PARAMETER AzureUserID
    Show a progressbar displaying the current operation.
 
.PARAMETER InputFIle
    Path and filename to CSV parameters input file

.PARAMETER StorageAcct
.PARAMETER Location
.PARAMETER SubnetName
.PARAMETER VnetName

.EXAMPLE
     
 
.NOTES
    FileName:    New-AzureVmLabGroup.ps1
    Author:      David Stein
    Created:     2016-08-11
    Updated:     2016-08-17
    Version:     1.0.3

    referenced: https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-windows-ps-create/
#>

param (
    [parameter(Mandatory=$False)] [string] $AzureUserID   = "...",
    [parameter(Mandatory=$False)] [string] $AzureTenantID = "...",
    [parameter(Mandatory=$False)] [string] $azSubId     = "...",
    [parameter(Mandatory=$False)] [string] $InputFile   = "azurelab.csv",
    [parameter(Mandatory=$False)] [string] $StorageAcct = "...",
    [parameter(Mandatory=$False)] [string] $Location    = "westus",
    [parameter(Mandatory=$False)] [string] $subnetName  = "...",
    [parameter(Mandatory=$False)] [string] $vnetName    = "...",
    [parameter(Mandatory=$False)] [switch] $ForceRun
)

Write-Output "checking if session is authenticated..."
if ($azCred -eq $null) {
    Write-Output "authentication is required."
    $azCred = Login-AzureRmAccount -EnvironmentName "AzureCloud" -AccountId $AzureUserID -SubscriptionId $azSubId -TenantId $AzureTenantID
}
else {
    Write-Output "authentication already confirmed."
}

$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
Write-Output "script path is $ScriptPath"

if (!(Test-Path $InputFile)) {
    if (!(Test-Path "$ScriptPath\$InputFile")) {
        Write-Host "Error: Unable to find the input file." -ForegroundColor Red
        Break;
    }
    else {
        $CsvFile = "$ScriptPath\$InputFile"
    }
}
else {
    $CsvFile = $InputFile
}
Write-Output "reading input file: $CsvFile..."
$csvData = Import-Csv $CsvFile

if ($csvData -ne $null) {
    if ($LocalUser -eq $null) {
        Write-Output "setting credentials for local administrator account..."
        $LocalUser = Get-Credential -Message "Type the name and password of the local administrator account."
    }

    foreach ($row in $csvData) {
        $vmName     = $row.Name
        $rgName     = $row.ResourceGroup
        $vmOS       = $row.OS
        $vmSize     = $row.Size
        $vmSNName   = $row.SubnetName
        $subnetPfx  = $row.SubnetRange
        $addressPfx = $row.AddressRange
        $LaWkSpace  = $row.OMSWorkspace
        $LaSolns    = $row.OMSSolutions
        $laCGName   = $row.OMSCompGroup
        $nicName    = "$vmName"+"-NIC1"
        $blobPath   = "$vmName"+"-os.vhd"
        $diskName   = "$vmName"+"-osdisk"
        $ipName     = "$vmName"+"-PIP"
        $laCGName   = $rgName

        $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -like "$StorageAcct"})
        
        if ($ForceRun -eq $True) {
            if ($vmName.Substring(0,1) -ne ";") {

                $rg = Get-AzureRmResourceGroup -Name $rgName -Location $Location -ErrorAction SilentlyContinue
                if ($rg -eq $null) {
                    Write-Output "creating resource group: $rgName..."
                    $rg = New-AzureRmResourceGroup -Name $rgName -Location $Location
                }
                else {
                    Write-Output "resource group already exists: $rgName"
                }

        #remove #$stAcct = Get-AzureRmStorageAccount -ResourceGroupName $rgName -Name $StorageAcct -ErrorAction SilentlyContinue
                if ($stAcct -eq $null) {
                    Write-Output "creating storage account: $StorageAcct..."
                    $stAcct = New-AzureRmStorageAccount -ResourceGroupName $rgName -Name $StorageAcct -SkuName Standard_LRS -Kind Storage -Location $Location -ErrorAction SilentlyContinue
                }
                else {
                    Write-Output "storage account already exists: $StorageAcct"
                }
                if ($stAcct -ne $null) {
                    $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
                    Write-Output "storage account URI: $stURI"
                }

                if ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}){
                    Write-Output 'subnet already exists: $subnetName'
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -like "$subnetName"}).id
                    } else {
                    Write-Output "creating virtual network subnet: $subnetName / $subnetPfx..."
                    $singleSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    }

        #remove #$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
                $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -like "$vnetName"})
                if ($vnet -ne $null) {
                    Write-Output "virtual network already exists: $vnetName"
                }
                else {
                    Write-Output "creating virtual network: $vnetName in $Location..."
                    $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location -AddressPrefix $addressPfx -Subnet $singleSubnet
                }

                Write-Output "creating public IP: $ipName..."
                $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Dynamic

                Write-Output "creating NIC: $nicName..."
                $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PublicIpAddressId $pip.Id

                Write-Output "preparing components for virtual machine..."

                $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
                $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmname -Credential $LocalUser -ProvisionVMAgent -EnableAutoUpdate
                $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus $vmOS -Version "latest"
                $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id

                $osDiskUri = "$stURI"+"vhds/$blobPath"
                Write-Output "disk blob uri is $osDiskUri"
                $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage

                Write-Output "creating virtual machine: $vmName..."
                New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm

                $vmNic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName
                $pvtIP = $($vmNic.IpConfigurations).PrivateIpAddress
                $pubIP = $(Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgname).IpAddress
                Write-Output "`tPrivate IP: $pvtIP"
                Write-Output "`tPublic IP: $pubIP"
            }
        }
        else {
            Write-Output "testmode enabled."
            Write-Output "vm: $vmName / size: $vmSize / os: $vmOS / Location: $Location"
            Write-Output "`tNIC Name: $nicName"
            Write-Output "`tBlob Path: $blobPath"
            Write-Output "`tDisk Name: $diskName"
            Write-Output "`tIP Name: $ipName"
            Write-Output "`tstorage blob: $osDiskUri"
            Write-Output "`tstorage disk: $diskName"
            Write-Output "`tSubnet Name: $vmSNName"
            Write-Output "`tSubnet prefix: $subnetPfx"
            Write-Output "`tAddress prefix: $addressPfx"
            Write-Output "`tOMS Workspace: $LaWkSpace"
            Write-Output "`tOMS Mgt Packs: $LaSolns"
            Write-Output "`tOMS Computer Group: $laCGName"
        }
    }
}

Write-Output "Finished!!!"

# Remove-AzureRmResourceGroup -Name $rgName -Force