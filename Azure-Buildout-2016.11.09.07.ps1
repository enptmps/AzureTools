<#
.SYNOPSIS
	Create Azure ARM VM lab

.PARAMETER AccountID
	[string] (required) email address for tenant/subscription connection

.PARAMETER TenantId
	[string] (required) guid for tenant ID

.PARAMETER SubscriptionId
	[string] (required) guid for subscription ID

.PARAMETER ParamFile
    [string] (optional) CSV file with account, tenant and subscription ID info

.PARAMETER InputFile
	[string] (optional) name of CSV input file

.PARAMETER TestMode
	[switch] (optional) Disables VM creation process, continues otherwise

.NOTES
	Date Created.... 09/08/2016
	Date Modified... 11/09/2016

	Version......... 2016.11.09.07
#>


param (
    [parameter(Mandatory=$False)] [string] $ParamFile = "config.csv",
    [parameter(Mandatory=$False)] [string] $AccountID = "",
    [parameter(Mandatory=$False)] [string] $TenantId = "",
    [parameter(Mandatory=$False)] [string] $SubscriptionId = "",
    [parameter(Mandatory=$False)] [string] $InputFile = "Azure-Buildout.csv",
    [parameter(Mandatory=$False)] [switch] $TestMode

)
Start-Transcript -Path "AzureBuildout-Transaction.log" -Append

$StartTime = Get-Date

#region FUNCTIONS

#------------------------------------------------------------------
# Establish Azure Authentication
#------------------------------------------------------------------

Write-Output "info: checking if session is authenticated..."
if ($azCred -eq $null) {
    $azCred = Login-AzureRmAccount
    $accountID = $azCred.Context.Account.Id
    $subscriptionID = $azCred.Context.Subscription.SubscriptionId
    $tenantID = $azCred.Context.Tenant.TenantId
}
else {
    Write-Output "info: authentication already confirmed."
    $accountID = $azCred.Context.Account.Id
    $subscriptionID = $azCred.Context.Subscription.SubscriptionId
    $tenantID = $azCred.Context.Tenant.TenantId
}

Write-Output "info: session context is: $AccountID"

#------------------------------------------------------------------
# Create or Return Resource Group
#------------------------------------------------------------------

function Make-ResourceGroup {
    param ($Rgn, $Loc)
    Write-Verbose "[make-resourcegroup] $Rgn $Loc"
    $rgx = Get-AzureRmResourceGroup -Name $Rgn -Location $Loc -ErrorAction SilentlyContinue
    if ($rgx -eq $null) {
        Write-Verbose "info: creating resource group: $Rgn..."
        $rgx = New-AzureRmResourceGroup -Name $Rgn -Location $Loc -ErrorAction SilentlyContinue
    }
    else {
        Write-Verbose "info: resource group already exists: $Rgn"
    }
    $rgx
}

#------------------------------------------------------------------
# Copy VHD from Source Library to VM Storage for SourceVHD use
#------------------------------------------------------------------

function Copy-SourceVHD {
    param ($SourceBlob, $SrcRG, $DestRG, $SourceSA, $DestSA, $SourceContainer, $DestContainer)
    Write-Verbose "[copy-sourcevhd] $SourceBlob"
    Write-Verbose "info: SOURCE RG..... $SrcRG"
    Write-Verbose "info: DEST RG....... $DestRg"
    Write-Verbose "info: SOURCE SA..... $SourceSA"
    Write-Verbose "info: DEST SA....... $DestSA"
    Write-Verbose "info: SOURCE CONT... $SourceContainer"
    Write-Verbose "info: DEST CONT..... $DestContainer"

    $SourceStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $SrcRG -Name $SourceSA)[0].Value
    $DestStorageKey   = (Get-AzureRmStorageAccountKey -ResourceGroupName $DestRG -Name $DestSA)[0].Value

    $SourceStorageContext = New-AzureStorageContext –StorageAccountName $SourceStorageAccount -StorageAccountKey $SourceStorageKey
    $DestStorageContext   = New-AzureStorageContext –StorageAccountName $DestSA -StorageAccountKey $DestStorageKey

    $Blobs = (Get-AzureStorageBlob -Context $SourceStorageContext -Container $SourceContainer | ?{$_.Name -eq $SourceBlob})
    $BlobCpyAry = @()
    
    $DestBlobs = (Get-AzureStorageBlob -Context $DestStorageContext -Container $DestContainer | ?{$_.Name -eq $SourceBlob})
    if ($DestBlobs -ne $null) {
        Write-Verbose "info: $SourceBlob already exists in destination."
    }
    else {
        foreach ($Blob in $Blobs) {
            Write-Output "info: Copying image disk $Blob.Name"
            $BlobCopy = Start-CopyAzureStorageBlob -Context $SourceStorageContext -SrcContainer $SourceContainer -SrcBlob $Blob.Name `
                -DestContext $DestStorageContext -DestContainer $DestContainer -DestBlob $Blob.Name
            $BlobCpyAry += $BlobCopy
        }

        foreach ($BlobCopy in $BlobCpyAry) {
            #Could ignore all rest and just run $BlobCopy | Get-AzureStorageBlobCopyState but I prefer output with % copied
            $CopyState = $BlobCopy | Get-AzureStorageBlobCopyState
            $Message = $CopyState.Source.AbsolutePath + " " + $CopyState.Status + " {0:N2}%" -f (($CopyState.BytesCopied/$CopyState.TotalBytes)*100) 
            Write-Output $Message
        }
    }
}

#endregion

#------------------------------------------------------------------
# Begin Loop Process
#------------------------------------------------------------------

Write-Verbose "info: Reading input file: $InputFile..."
$csvData = Import-Csv $InputFile

if ($csvData -ne $null) {
    
    Write-Output "info: Retrieved $($csvData.Length) rows for processing"

    foreach ($row in $csvData) {
	    $vmName         = $row.Name
        $Location       = $row.Location
        $rgName         = $row.ResourceGroup
        $vmSize         = $row.Size
        $Publisher      = $row.PublisherName
        $Offer          = $row.Offer
        $Version        = $row.Version
        $Skus           = $row.Skus

        # describes the source VHD location and name

        $SourceRG       = $row.SrcResourceGroup     # RG   - "VHDLibrary"
        $SourceSA       = $row.SrcStorageAcct       # SA   - "vhdsources"
        $SourceCont     = $row.SourceContainer      # CONT - "template"
        $SourceBlob     = $row.SourceVHD            # BLOB - "WS2012R2-1.vhd"

        # describes the destination VHD for the VM

        $DestRG         = $row.StorageResGroup      # RG   - "Test-Storage"
	    $DestSA         = $row.StorageAccount       # SA   - "testsabhf01"
        $DestCont       = $row.destinationContainer # CONT - "vhd"
        $DestBlob       = $SourceBlob               # BLOB - (copied) VHD

        $storagesku     = $row.StorageSku           # 

        # describes the networking options

        $privIP         = $row.PrivateIP
        $pubIP          = $row.PublicIP
        $vnetName       = $row.vnetName
        $subnetName     = $row.SubnetName
        $subnetPfx      = $row.SubnetRange
        $addressPfx     = $row.AddressRange
        $rgnet          = $row.NetworkingResGroup

        $caching        = $row.caching              #
        $DataDiskSize1  = $row.DataDiskSize1        #

        $ASName         = $row.ASName

        $VmAdminUser    = $row.AdminUser
        $VmAdminPwd     = $row.AdminPwd

        $nicName        = "$vmName"+"nic1"
        $osdiskname     = "$vmName"+"os.vhd"
        $diskName       = "$vmName"+"osdisk"
        $datadiskname   = "$vmName"+"datadisk.vhd"
        $ipName         = "$vmName"+"pip1"

        # check if first cell begins with ";" denoting a commented line

        if ($vmName.Substring(0,1) -ne ";") {
            
            if ($TestMode) {
                Write-Verbose "----------- Current Row -------------"
                foreach ($xx in $row) {
                    $xx
                }
                Write-Verbose "-------------------------------------"
            }
            Write-Verbose "---------------------------------------------------"
            if ((Get-AzureRmVM -VM $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue) -ne $null) {
                Write-Output "info: VM $vmName already exists."
            }
            else {
                
                $subnet = $null
                $vnet   = $null

                $RowStart = Get-Date
                $rg  = Make-ResourceGroup -rgn $rgName -loc $location
                $rgs = Make-ResourceGroup -rgn $DestRG -loc $location
                $rgn = Make-ResourceGroup -rgn $rgnet -loc $location

                #------------------------------------------------------------------
                # Storage Account
                #------------------------------------------------------------------
                
                # Check Storage Account Availability
                
                $StorageAccountNameExists   = [bool](Get-AzureRmStorageAccountNameAvailability -Name $DestSA).NameAvailable
                $StNameExistsInTheTenant    = [bool](Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$DestSA"})
                if ((!($StorageAccountNameExists)) -and (!($StNameExistsInTheTenant))){
                    Write-Output "ERROR: Storage account" $DestSA "name already taken"
                    Write-Output "ERROR: Please choose another Storage Account Name"
                    Write-Output "ERROR: This Powershell command can be used: Get-AzureRmStorageAccountNameAvailability -Name"
                    Break
                }
                else {
                    Write-Verbose "info: Storage account: $DestSA is either available or already yours"
                }
                
                # Storage Account Logic
                
                if (!($StNameExistsInTheTenant)){
                    Write-Verbose "info: Creating storage account $DestSA in $DestRG with $storageSku"
                    $stAcct = New-AzureRmStorageAccount -ResourceGroupName $DestRG -Name $DestSA -SkuName $storagesku -Kind Storage -Location $Location -ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose "info: Getting existing account $DestSA in $DestRG"
                    $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$DestSA"})
                }
                $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
                Write-Verbose "info: storage URI is $stURI"
            
                # Create Storage Account if needed

                $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$DestSA"})
                if ($stAcct -eq $null) {
                    Write-Output "info: Creating storage account: $DestSA..."
                    Write-Verbose "info: Name: $DestSA`ninfo: ResourceGroup: $DestRG`ninfo: SkuName: $storagesku"
                    $stAcct = New-AzureRmStorageAccount -ResourceGroupName $DestRG -Name $DestSA -SkuName $storagesku -Kind Storage -Location $Location #-ErrorAction SilentlyContinue
                }
                else {
                    Write-Verbose "info: Storage account already exists: $DestSA"
                }

                if ($stAcct -ne $null) {
                    Write-Verbose "info: Getting storage account URI..."
                    $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
                    Write-Verbose "info: Storage account URI: $stURI"
                }

                #------------------------------------------------------------------
                # Source VHD
                #------------------------------------------------------------------

                if ($SourceBlob -ne "") {
                    Write-Verbose "info: checking if source VHD ($SourceBlob) exists..."
                    $stTemplateTemp     = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$SourceSA"})
                    $StTemplateuri      = $stTemplateTemp.PrimaryEndpoints.Blob.ToString()
                    $StorageContext     = (Get-AzureRmStorageAccount -ResourceGroupName $SourceRG -Name $SourceSA).context
                    Write-Verbose "SourceVHD: $SourceBlob"
                    Write-Verbose "stTemplateUri: $StTemplateuri"
                    Write-Verbose "StorageContext: $StorageContext"
                    Write-Verbose "SourceCont: $SourceCont"
                    Write-Verbose "checking for valid source object..."
                    $CheckForSourceVHD  = [bool](Get-AzureStorageBlob -Context $StorageContext -Container $SourceCont | ? {$_.name -eq $SourceBlob})
                    if (($imageUri -ne "") -and ($Publisher -eq "") -and (!($CheckForSourceVHD))){
                        Write-Output "Error: Source image not found (.vhd): $SourceBlob"
                        Break
                    }    
                    else {
                        Write-Verbose "Source image found or this is a Marketplace build"
                    }
                }

                #------------------------------------------------------------------
                # Networking
                #------------------------------------------------------------------
                
                # Prep the Subnet
                Write-Verbose "==================================="
                Write-Verbose "info: SubnetName...: $subnetName"
                Write-Verbose "info: VnetName.....: $vnetName"
                Write-Verbose "==================================="

                # BOTH VNET AND SUBNET EXISTS
                if ((((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -ne "$subnetName"}) -eq $null) -and ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -ne $null)) {
                    #write-Verbose "A1..." $vnet
                    #Write-Verbose "B1..." ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"})
                    Write-Verbose "info: *** condition 1 = vnet and subnet BOTH EXIST"
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                # NEITHER VNET OR SUBNET EXISTS
                elseif ((((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}) -eq $null) -and ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null)) {
                    Write-verbose "info: A2... $vnet"
                    Write-verbose "info: B2... $subnet"
                    Write-Verbose "info: *** condition 2 = NEITHER EXIST: vnet or subnet"
                    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    $vnet   = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                # SUBNET EXISTS but vnet DOES NOT EXIST
                elseif ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null) {
                    Write-Verbose "info: *** condition 4"
                    Write-Verbose "info: A4... vnet does not exist" 
                    if ($subnet -eq $null) { 
                        Write-Verbose "info: B4... subnet does not exist" 
                    }
                    else {
                        Write-Verbose "info: B4... subnet DOES exist"
                    }
                    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                    Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx | Out-Null
                    $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                # VNET EXISTS but SUBNET DOES NOT EXIST
                else {
                    Write-Verbose "info: *** condition 5"
                    if ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null) {
                        Write-Verbose "info: B5... vnet is NULL"
                    }
                    else {
                        Write-Verbose "info: B5... vnet EXISTS"
                        $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                    }
                    if (((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}) -eq $null) {
                        Write-Verbose "info: B5... subnet not in vnet, adding to vnet now..."
                        $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                        $vnet   = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                        Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx | Out-Null
                        $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
                    else {
                        Write-Verbose "info: B5... subnet EXISTS"
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
                }

                #------------------------------------------------------------------
                # NIC and Public IP
                #------------------------------------------------------------------
                
                If ($pubIP -ne "") {
                    Write-Verbose "info: Creating public IP: $ipName..."
                    $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static
                    Write-Verbose "info: Creating NIC: $nicName..."
                    $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PublicIpAddressId $pip.Id -PrivateIpAddress $privIP -Force
                }
                else {
                    Write-Verbose "info: No public IP address specified for $vmName"
                    Write-Verbose "info: Creating NIC: $nicName..."
                    $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PrivateIpAddress $privIP -Force
                }

                Write-Verbose "info: Preparing credentials for VM Local Admin..."

                $SecurePassword = ConvertTo-SecureString "$VmAdminPwd" -AsPlainText -Force
                $Credential     = New-Object System.Management.Automation.PSCredential ($VmAdminUser, $SecurePassword); 
            
                #------------------------------------------------------------------
                # Availability Set
                #------------------------------------------------------------------
                
                if ($ASName -ne "") {
                    Write-Verbose "info: Availability set specified: $asname"
                    $aset1 = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asName -ErrorAction SilentlyContinue
                    if (!($aset1)) {
                        Write-Verbose "info: Creating availability set: $asname"
                        $aset1 = New-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asname -Location $location
                    }
                    else {
                        Write-Verbose "info: Availability set already exists: $asname"
                    }
                    Write-Verbose "info: Creating VM configuration with availability set: $vmName..."
                    $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $aset1.Id
                }
                else {
                    Write-Verbose "info: Creating VM configuration: $vmName..."
                    $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
                }

                #------------------------------------------------------------------
                # Update Virtual Machine Configuration
                #------------------------------------------------------------------

                Write-Verbose "info: Configuring VM OS and NIC association..."
                # NOTE: customer may want to disable ProvisionVMAgent parameter ***
                $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $Credential
                #$vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate

                $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
            
                #------------------------------------------------------------------
                # OS Disk
                #------------------------------------------------------------------

                $osDiskUri = "$stURI"+"$DestCont/$osdiskname"
                Write-Verbose "info: Disk blob uri is $osDiskUri"
                if ($Publisher -eq "") { 
                    Write-Verbose "info: OS Disk Image from Source VHD $osDiskUri"
                    $SourceBlobURI = "$stURI"+"$SourceCont"+"/$SourceBlob"
                    $DestBlobURI   = "http://$DestSA.blob.core.windows.net/$DestCont/$DestBlob"
                    
                    Write-Verbose "info: Source Blob URI is $SourceBlobURI"
                    Write-Verbose "info: Destination Blob URI is $DestBlobURI"

                    Copy-SourceVHD -SourceBlob $SourceBlob -SrcRG $SourceRG -DestRG $DestRG -SourceSA $SourceSA -DestSA $DestSA -SourceContainer $SourceCont -DestContainer $DestCont

                    Write-Verbose "info: setting VM OS disk..."
                    $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri `
                            -CreateOption FromImage -SourceImageUri $DestBlobURI -Windows
                }
                else {
                    
                    Write-Verbose "info: Marketplace Image from publisher $Publisher"
                    $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage
                    $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $Publisher `
                            -Offer $Offer -Skus $Skus -Version $Version
                }
            
                #------------------------------------------------------------------
                # Create Virtual Machine
                #------------------------------------------------------------------
                
                if (!($TestMode)) {
                    Write-Output "info: Creating virtual machine: $vmName..."
                    $vmt1 = Get-Date
                    $newvm = New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm
                    $vmt2 = Get-Date
                    $RunTime = [math]::Round(($vmt2 - $vmt1).TotalMinutes,2)
                    Write-Host "info: virtual machine creation took $RunTime minutes"

                }
                else {
                    Write-Output "info: SKIPPING VM CREATION FOR TEST MODE: $vmName"
                }

                #------------------------------------------------------------------
                # Data Disk
                #------------------------------------------------------------------

                if ($DataDiskSize1 -ne "") {
                    Write-Verbose "info: Creating Data Disk: $datadiskname"     
                    $dataDiskUri = "$stURI"+"$DestCont"+"/$datadiskname"
		            Write-Verbose "info: Data Disk URI: $dataDiskUri"
                    if (!($TestMode)) {
                        $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName 
                        Write-Verbose "info: Attaching data disk ($datadiskname) to VM ($vmName)"
                        Add-AzureRmVMDataDisk -VM $vm -Name $datadiskname -VhdUri $dataDiskUri `
                                -Caching $Caching -DiskSizeinGB $DataDiskSize1 -CreateOption Empty | Out-Null
                        Update-AzureRmVM -ResourceGroupName $rgName -VM $vm | Out-Null
                    }
                    else {
                        Write-Verbose "info: Attaching data disk ($datadiskname) to VM ($vmName)"
                    }
                }
                else {
                    Write-Verbose "info: No Data Disk Requested for $vmName"
                }
            
                # Write Results to Screen
                $vmNic = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName
                $pvtIP = $($vmNic.IpConfigurations).PrivateIpAddress
                Write-Verbose "info: Private IP: $pvtIP"
                If ($pubIP -ne "") {
                    $pubIP = $(Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgname).IpAddress
                    Write-Verbose "info: Public IP: $pub"
                }
                Write-Verbose "info: *** Virtual machine completed! $vmName"
                $RowStop = Get-Date
                $RunTime = [math]::Round(($RowStop - $RowStart).TotalMinutes,2)
                Write-Output "info: Virtual Machine: $vmName, completed in $RunTime minutes"
            }
        }
    }
}

$StopTime = Get-Date
$RunTime = [math]::Round(($StopTime - $StartTime).TotalMinutes,2)
Write-Host "info: Finished!!! Runtime was $RunTime minutes"
Stop-Transcript
