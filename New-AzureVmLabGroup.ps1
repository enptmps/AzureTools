param (
    [parameter(Mandatory=$False)] [string] $azEnv      = "AzureCloud",
    [parameter(Mandatory=$True)] [string] $azAcct,
    [parameter(Mandatory=$True)] [string] $azTenId,
    [parameter(Mandatory=$True)] [string] $azSubId,
    [parameter(Mandatory=$True)] [string] $InputFile
)

Write-Output "checking if session is authenticated..."
if ($azCred -eq $null) {
    Write-Output "authentication is required."
    $azCred = Login-AzureRmAccount -EnvironmentName $azEnv -AccountId $azAcct -SubscriptionId $azSubId -TenantId $azTenId
}
else {
    Write-Output "authentication already confirmed."
}

Write-Output "reading input file: $InputFile..."
$csvData = Import-Csv $InputFile

Write-Output "setting credentials for local administrator account..."
$LocalUser = Get-Credential -Message "Type the name and password of the local administrator account."

if ($csvData -ne $null) {

    foreach ($row in $csvData) {
        $Location       = $row.Location
        $vmName         = $row.Name
        $sourceCont     = $row.sourceContainer
        $sourceVHD      = $row.SourceVHD
        $destCont       = $row.destinationContainer
        $osDiskUri      = $row.osdiskUri
        $saName         = $row.StorageAccount
        $storagesku     = $row.StorageSku
        $vmSize         = $row.Size
        $Publisher      = $row.PublisherName
        $Offer          = $row.Offer
        $Version        = $row.Version
        $Skus           = $row.Skus
        $privIP         = $row.PrivateIP
        $vnetName       = $row.vnetName
        $subnetName     = $row.SubnetName
        $subnetPfx      = $row.SubnetRange
        $addressPfx     = $row.AddressRange
        $rgName         = $row.ResourceGroup
        $rgstore        = $row.StorageResGroup
        $rgnet          = $row.NetworkingResGroup
        $caching        = $row.caching
        $DataDiskSize1  = $row.DataDiskSize1
        $nicName        = "$vmName"+"-nic1"
        $osdiskname     = "$vmName"+"-os.vhd"
        $diskName       = "$vmName"+"osdisk"
        $datadiskname   = "$vmName"+"-datadisk0.vhd"
        $ipName         = "$vmName"+"-pip1"

            # Check Storage Account Availability
            $StorageAccountNameExists = Get-AzureRmStorageAccountNameAvailability -Name $saName
            $StNameExistsInTheTenant  = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
            if ($StorageAccountNameExists.NameAvailable -eq "False" -and $StNameExistsInTheTenant -ne $null){
                Write-Output "Storage account" $saName "name already taken"
                Write-Output "Please choose another Storage Account Name"
                Write-Output "This Powershell command can be used: Get-AzureRmStorageAccountNameAvailability -Name"
                Break
            }
            else {
                Write-Output "Storage account: $saName is available"
            }
       
            if ($vmName.Substring(0,1) -ne ";") {
            
            # Resource Group
            $rg = Get-AzureRmResourceGroup -Name $rgName -Location $Location -ErrorAction SilentlyContinue
            if ($rg -eq $null) {
                Write-Output "creating resource group: $rgName..."
                $rg = New-AzureRmResourceGroup -Name $rgName -Location $Location
            }
            else {
                Write-Output "resource group already exists: $rgName"
            }
            
            # Resource Group Storage
            $rgs = Get-AzureRmResourceGroup -Name $rgstore -Location $Location -ErrorAction SilentlyContinue
            if ($rgs -eq $null) {
                Write-Output "creating resource group: $rgstore..."
                $rgs = New-AzureRmResourceGroup -Name $rgstore -Location $Location
            }
            else {
                Write-Output "resource group already exists: $rgstore"
            }
            
            # Resource Group Network
            $rgn = Get-AzureRmResourceGroup -Name $rgnet -Location $Location -ErrorAction SilentlyContinue
            if ($rgn -eq $null) {
                Write-Output "creating resource group: $rgnet..."
                $rgn = New-AzureRmResourceGroup -Name $rgnet -Location $Location
            }
            else {
                Write-Output "resource group already exists: $rgnet"
            }
            
            # Storage Account
            $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
            if ($stAcct -eq $null) {
                Write-Output "creating storage account: $saName..."
                $stAcct = New-AzureRmStorageAccount -ResourceGroupName $rgstore -Name $saName -SkuName $storagesku -Kind Storage -Location $Location #-ErrorAction SilentlyContinue
            }
            else {
                Write-Output "storage account already exists: $saName"
            }
            if ($stAcct -ne $null) {
                $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
                Write-Output "storage account URI: $stURI"
            }
            
            # Subnet
            if ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}){
                Write-Output "subnet already exists: $subnetName"
                $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
            } 
            else {
                Write-Output "creating virtual network subnet: $subnetName / $subnetPfx..."
                $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
           }
            
            # VNet
            $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
            if ($vnet -ne $null) {
                Write-Output "virtual network already exists: $vnetName"
            }
            else {
               Write-Output "creating virtual network: $vnetName in $Location..."
                $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
            }
            
            # Public IP Address Creation
            #Write-Output "creating public IP: $ipName..."
            #$pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static
            
            # NIC Creation
            Write-Output "creating NIC: $nicName..."
            $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PrivateIpAddress $privIP
            
            # VM components
            Write-Output "preparing components for virtual machine..."
            $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
            $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmname -Credential $LocalUser -ProvisionVMAgent -EnableAutoUpdate
            $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
            
            # VM Disk (OS)
            $osDiskUri   = "$stURI"+"$destCont"+"/$osdiskname"
            if ($Publisher -eq "") { 
                $imageUri    = "$stURI"+"$sourceCont"+"/$sourceVHD"
                Write-Output "disk blob uri is $osDiskUri"
                Write-Output "Image from Source VHD $osDiskUri"
                $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage -SourceImageUri $imageUri -Windows
            }
            else {
                Write-Output "disk blob uri is $osDiskUri"
                Write-Output "Marketplace Image from publisher $Publisher"
                $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage
                $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $Publisher -Offer $Offer -Skus $Skus -Version $Version
            }
            
            # VM Creation
            Write-Output "creating virtual machine: $vmName..."
            New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm
            
            # VM Disk (DATA)            
            if ($datadiskname -ne "") {
                $dataDiskUri = "$stURI"+"$destCont"+"/$datadiskname"
                Write-Output "Creatung Data Disk: $datadiskname"     
                $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName 
                Add-AzureRmVMDataDisk -VM $vm -Name $datadiskname -VhdUri $dataDiskUri -Caching $Caching -DiskSizeinGB $DataDiskSize1  -CreateOption Empty
                Update-AzureRmVM -ResourceGroupName $rgName -VM $vm
            }
            
            # Write Results to Screen
            $vmNic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName
            $pvtIP = $($vmNic.IpConfigurations).PrivateIpAddress
            $pubIP = $(Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgname).IpAddress
            Write-Output "`tPrivate IP: $pvtIP"
            Write-Output "`tPublic IP: $pubIP"
        }

<#        else {
            Write-Output "testmode enabled."
            Write-Output "vm: $vmName / size: $vmSize / Location: $Location"
            $blobPath  = "$vmName"+"os.vhd"
            $osDiskUri = "$stURI"+"vhds/$blobPath"
            $diskName  = "$vmName"+"osdisk"
            Write-Output "`tstorage blob: $osDiskUri"
            Write-Output "`tstorage disk: $diskName"
        }
#>
    }
}

Write-Output "Finished!!!"
