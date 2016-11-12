<#
.SYNOPSIS
	Azure-Buildout.ps1
    
    Create Azure ARM VM environment using CSV input data.

.PARAMETER CredFile
    [string] (optional) CSV file with account, tenant and subscription ID info

.PARAMETER InputFile
	[string] (REQUIRED) name of CSV input file

.PARAMETER AccountID
	[string] (required) email address for tenant/subscription connection

.PARAMETER TenantId
	[string] (required) guid for tenant ID

.PARAMETER SubscriptionId
	[string] (required) guid for subscription ID

.PARAMETER LogName
    [string] (optional) Modifies the transcript log filename
    if not specified, the default is "Transaction"
    which makes an output named "AzureBuildout-Transaction.log"

.PARAMETER TestMode
	[switch] (optional) Disables VM creation process, continues otherwise

.NOTES
	Date Created.... 09/08/2016
	Date Modified... 11/10/2016

	Version......... 2016.11.12.03

.EXAMPLE
    Azure-Buildout.ps1 -CredFile "mycreds.csv" -InputFile "contoso.csv"

.EXAMPLE
    Azure-Buildout.ps1 -CredFile "mycreds.csv" -InputFile "contoso.csv" -LogName "Contoso3"

.EXAMPLE
    Azure-Buildout.ps1 -CredFile "mycreds.csv" -InputFile "contoso.csv" -TestMode -Verbose

#>


param (
    [parameter(Mandatory=$False)] [string] $CredFile = "creds.csv",
    [parameter(Mandatory=$True)]  [string] $InputFile,
    [parameter(Mandatory=$False)] [string] $AccountID = "",
    [parameter(Mandatory=$False)] [string] $TenantId = "",
    [parameter(Mandatory=$False)] [string] $SubscriptionId = "",
    [parameter(Mandatory=$False)] [string] $LogName = "Transaction",
    [parameter(Mandatory=$False)] [switch] $TestMode
)
Start-Transcript -Path ".\logs\AzureBuildout-$LogName.log" -Append

$StartTime = Get-Date

#region FUNCTIONS

#------------------------------------------------------------------
# Establish Azure Authentication
#------------------------------------------------------------------

Write-Output "info: checking if session is authenticated..."

Write-Verbose "info: searching for credential cache: $CredFile..."

$azCred = Select-AzureRmProfile -Path "$CredFile"

if ($azCred -ne $null) {
    Write-Output "info: authentication confirmed."
    $accountID = $azCred.Context.Account.Id
    $tenantID  = $azCred.Context.Tenant.TenantId
    $subscriptionID = $azCred.Context.Subscription.SubscriptionId
}
else {
    $azCred = Login-AzureRmAccount
    $accountID = $azCred.Context.Account.Id
    $tenantID  = $azCred.Context.Tenant.TenantId
    $subscriptionID = $azCred.Context.Subscription.SubscriptionId
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
        if (!($TestMode)) {
            $rgx = New-AzureRmResourceGroup -Name $Rgn -Location $Loc -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Verbose "info: resource group already exists: $Rgn"
    }
    $rgx
}

#------------------------------------------------------------------
# Return $TRUE if blob (file) exists in specified location
#------------------------------------------------------------------

function Test-BlobExists {
    param (
        [parameter(Mandatory=$True)] [string] $BlobName,
        [parameter(Mandatory=$True)] [string] $ResourceGroupName,
        [parameter(Mandatory=$True)] [string] $StorageAccountName,
        [parameter(Mandatory=$True)] [string] $ContainerName
    )
    Write-Verbose "[test-blobexists]"
    Write-Verbose "info: BlobName............. $BlobName"
    Write-Verbose "info: ResourceGroupName.... $ResourceGroupName"
    Write-Verbose "info: StorageAccountName... $StorageAccountName"
    Write-Verbose "info: ContainerName........ $ContainerName"

    $StorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
    $StorageContext = New-AzureStorageContext –StorageAccountName $StorageAccountName -StorageAccountKey $StorageKey
    $(Get-AzureStorageBlob -Context $StorageContext -Container $ContainerName | ?{$_.Name -eq $BlobName})
}

#------------------------------------------------------------------
# Copy VHD from Source Library to VM Storage for SourceVHD use
#------------------------------------------------------------------

function Copy-SourceVHD {
    param (
        [parameter(Mandatory=$True)] [string] $SourceBlob,
        [parameter(Mandatory=$True)] [string] $SrcResourceGroupName,
        [parameter(Mandatory=$True)] [string] $SrcContainerName,
        [parameter(Mandatory=$True)] [string] $SrcStorageAccountName,
        [parameter(Mandatory=$True)] [string] $DestResourceGroupName,
        [parameter(Mandatory=$True)] [string] $DestContainerName,
        [parameter(Mandatory=$True)] [string] $DestStorageAccountName,
        [parameter(Mandatory=$False)] [switch] $OverWrite = $False
    )
    Write-Verbose "[copy-sourcevhd] $SourceBlob"
    Write-Verbose "info: SrcResourceGroupName..... $SrcResourceGroupName"
    Write-Verbose "info: DestResourceGroupName.... $DestResourceGroupName"
    Write-Verbose "info: SrcStorageAccountName.... $SrcStorageAccountName"
    Write-Verbose "info: DestStorageAccountName... $DestStorageAccountName"
    Write-Verbose "info: SrcContainerName......... $SrcContainerName"
    Write-Verbose "info: DestContainerName........ $DestContainerName"

    $SourceStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $SrcResourceGroupName -Name $SrcStorageAccountName)[0].Value
    $DestStorageKey   = (Get-AzureRmStorageAccountKey -ResourceGroupName $DestResourceGroupName -Name $DestStorageAccountName)[0].Value

    $SourceStorageContext = New-AzureStorageContext –StorageAccountName $SourceStorageAccount -StorageAccountKey $SourceStorageKey
    $DestStorageContext   = New-AzureStorageContext –StorageAccountName $DestStorageAccountName -StorageAccountKey $DestStorageKey

    $Blobs = (Get-AzureStorageBlob -Context $SourceStorageContext -Container $SrcContainerName | ?{$_.Name -eq $SourceBlob})
    $BlobCpyAry = @()
    
    $DestBlobs = (Get-AzureStorageBlob -Context $DestStorageContext -Container $DestContainerName | ?{$_.Name -eq $SourceBlob})
    if ((!($OverWrite)) -and ($DestBlobs -ne $null)) {
        Write-Output "$SourceBlob already exists in destination."
    }
    else {
        Write-Verbose "info: Copying blob objects..."
        if (!($TestMode)) {
            foreach ($Blob in $Blobs) {
                Write-Verbose "info: copying $($Blob.Name)..."
                $BlobCopy = Start-CopyAzureStorageBlob -Context $SourceStorageContext `
                    -SrcContainer $SourceContainer -SrcBlob $Blob.Name `
                    -DestContext $DestStorageContext -DestContainer $DestContainer `
                    -DestBlob $Blob.Name -Force
                $BlobCpyAry += $BlobCopy
            }

            foreach ($BlobCopy in $BlobCpyAry) {
                $CopyState = $BlobCopy | Get-AzureStorageBlobCopyState
                $Message = $CopyState.Source.AbsolutePath + " " + $CopyState.Status + `
                    " {0:N2}%" -f (($CopyState.BytesCopied/$CopyState.TotalBytes)*100) 
                Write-Output $Message
            }
        }
        else {
            foreach ($Blob in $Blobs) {
                Write-Verbose "test: copying $($Blob.Name)..."
            }
        }
    }
    $(Get-AzureStorageBlob -Context $DestStorageContext -Container $DestContainerName | ?{$_.Name -eq $SourceBlob})
}

#------------------------------------------------------------------
# verify marketplace image publisher is valid
#------------------------------------------------------------------

function Test-ImagePublisher {
    param (
        $Loc, $Publisher
    )
    $(!(Get-AzureRmVMImagePublisher -Location $Loc | ?{$_.PublisherName -eq $Publisher}) -ne $null)
}

#------------------------------------------------------------------
# verify marketplace image publisher offername is valid
#------------------------------------------------------------------

function Test-ImageOffer {
    param (
        $Loc, $Publisher, $OfferName
    )
    $(!(Get-AzureRmVMImageOffer -Location $Loc -PublisherName $Publisher | ?{$_.Offer -eq $OfferName}) -ne $null)
}

#------------------------------------------------------------------
# verify marketplace SKU exists for specified publisher and offer
#------------------------------------------------------------------

function Test-ImageSKU {
    param (
        $Loc, $Publisher, $OfferName, $Sku
    )
    $(!(Get-AzureRmVMImageSku -Location $Loc -PublisherName $Publisher -Offer $OfferName | ?{$_.Skus -eq $Sku}) -ne $null)
}

#endregion

#------------------------------------------------------------------
# Begin Loop Process
#------------------------------------------------------------------

$csvFile = ".\csv\$InputFile"

Write-Verbose "info: Reading input file: $csvFile..."
$csvData = Import-Csv $csvFile

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

        $storagesku     = $row.StorageSku           # storage SKU

        # describes the networking options

        $privIP         = $row.PrivateIP
        $pubIP          = $row.PublicIP
        $vnetName       = $row.vnetName
        $subnetName     = $row.SubnetName
        $subnetPfx      = $row.SubnetRange
        $addressPfx     = $row.AddressRange
        $rgnet          = $row.NetworkingResGroup

        # describes data disks

        $caching        = $row.caching              # disk caching option
        $DataDiskSize1  = $row.DataDiskSize1        # data disk size 1
        $DataDiskSize2  = $row.DataDiskSize2        # data disk size 2

        # describes availability sets

        $ASName         = $row.ASName               # availability set name
        $ASFDomains     = $row.ASFaultDomains       # avail set fault domains
        $ASUDomains     = $row.ASUpdateDomains      # avail set update domains

        $VmAdminUser    = $row.AdminUser            # local admin username
        $VmAdminPwd     = $row.AdminPwd             # local admin password

        $nicName        = "$vmName"+"nic1"
        $osdiskname     = "$vmName"+"os.vhd"
        $diskName       = "$vmName"+"osdisk"
        if ($DataDiskSize1 -ne "") {
            $dataDiskName1  = "$vmName"+"datadisk1.vhd"
        }
        else {
            $dataDiskName1 = ""
        }
        if ($DataDiskSize2 -ne "") {
            $dataDiskName2  = "$vmname"+"datadisk2.vhd"
        }
        else {
            $dataDiskName2 = ""
        }
        if ($PubIP -ne "") {
            $ipName         = "$vmName"+"pip1"
        }
        else {
            $ipName = ""
        }

        # check if first cell begins with ";" denoting a commented line

        if ($vmName.Substring(0,1) -ne ";") {
            
            Write-Verbose "=================================== 0"
            foreach ($xx in $row) {
                Write-Verbose $xx
            }

            Write-Verbose "=================================== 1"
            Write-Verbose "info: checking for existing vm named: $vmName..."
            if ((Get-AzureRmVM -VM $vmName -ResourceGroupName $rgName -ErrorAction SilentlyContinue) -ne $null) {
                Write-Output "info: VM $vmName already exists."
            }
            else {
                
                Write-Verbose "=================================== 2"

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
                
                Write-Verbose "=================================== 3"
                $StorageAccountNameExists   = [bool](Get-AzureRmStorageAccountNameAvailability -Name $DestSA).NameAvailable
                $StNameExistsInTheTenant    = [bool](Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$DestSA"})
                if ((!($StorageAccountNameExists)) -and (!($StNameExistsInTheTenant))){
                    Write-Output "==================================="
                    Write-Output "ERROR: Storage account" $DestSA "name already taken"
                    Write-Output "ERROR: Please choose another Storage Account Name"
                    Write-Output "ERROR: This Powershell command can be used: Get-AzureRmStorageAccountNameAvailability -Name"
                    Write-Output "==================================="
                    Break
                }
                else {
                    Write-Verbose "info: Storage account: $DestSA is either available or already yours"
                }
                
                # Storage Account Logic

                Write-Verbose "=================================== 4"
                if (!($StNameExistsInTheTenant)){
                    Write-Verbose "info: Creating storage account $DestSA in $DestRG with $storageSku"
                    if (!($TestMode)) {
                        $stAcct = New-AzureRmStorageAccount -ResourceGroupName $DestRG -Name $DestSA -SkuName $storagesku -Kind Storage -Location $Location -ErrorAction SilentlyContinue
                    }
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
                    if (!($TestMode)) {
                        $stAcct = New-AzureRmStorageAccount -ResourceGroupName $DestRG -Name $DestSA -SkuName $storagesku -Kind Storage -Location $Location #-ErrorAction SilentlyContinue
                    }
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

                Write-Verbose "=================================== 5"

                if ($SourceBlob -ne "") {
                    Write-Verbose "info: checking if source VHD ($SourceBlob) exists in ($SourceSA)..."
                    $stTemplateTemp = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$SourceSA"})
                    $StTemplateuri  = $stTemplateTemp.PrimaryEndpoints.Blob.ToString()
                    $StorageContext = (Get-AzureRmStorageAccount -ResourceGroupName $SourceRG -Name $SourceSA).context
                    Write-Verbose "SourceVHD......... $SourceBlob"
                    Write-Verbose "stTemplateUri..... $StTemplateuri"
                    Write-Verbose "StorageContext.... $StorageContext"
                    Write-Verbose "SourceCont........ $SourceCont"
                    Write-Verbose "=================================== 6"
                    Write-Verbose "info: checking for valid source object..."
                    $CheckForSourceVHD  = [bool](Get-AzureStorageBlob -Context $StorageContext -Container $SourceCont | ? {$_.name -eq $SourceBlob})
                    if (($imageUri -ne "") -and ($Publisher -eq "") -and (!($CheckForSourceVHD))){
                        Write-Output "Error: Source image not found (.vhd): $SourceBlob"
                        Break
                    }
                    else {
                        Write-Verbose "info: source VHD blob ($SourceBlob) was found in container ($SourceCont)."
                    }
                }
                else {
                    Write-Verbose "=================================== 6"
                    Write-Verbose "info: Source image for this is a Marketplace build."
                    Write-Verbose "info: Publisher.... $Publisher"
                    Write-Verbose "info: OfferName.... $Offer"
                    Write-Verbose "info: sku.......... $Skus"
                    Write-Verbose "info: verifying marketplace image parameters..."
                    if (!(Test-ImagePublisher -Loc $Location -Publisher $Publisher)) {
                        Write-Output "error: Invalid marketplace publisher name specified!"
                        Break
                    }
                    if (!(Test-ImageOffer -Loc $Location -Publisher $Publisher -OfferName $Offer)) {
                        Write-Output "error: Invalid marketplace offer name specified!"
                        Break
                    }
                    if (!(Test-ImageSKU -Loc $Location -Publisher $Publisher -OfferName $Offer -Sku $Skus)) {
                        Write-Output "error: Invalid marketplace publisher name specified!"
                        Break
                    }
                    Write-Verbose "info: source image parameters have been validated."
                }

                #------------------------------------------------------------------
                # Networking
                #------------------------------------------------------------------
                
                # Prep the Subnet
                Write-Verbose "=================================== 7"
                Write-Verbose "info: SubnetName.... $subnetName"
                Write-Verbose "info: VnetName...... $vnetName"
                Write-Verbose "=================================== 8"
                Write-Verbose "info: configuring vnets and subnets..."

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
                    if (!($TestMode)) {
                        $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                        $vnet   = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
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
                    if (!($TestMode)) {
                        $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                        $vnet   = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                        Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx | Out-Null
                        $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
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
                        if (!($TestMode)) {
                            $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                            $vnet   = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                            Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx | Out-Null
                            $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                            $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                        }
                    }
                    else {
                        Write-Verbose "info: B5... subnet EXISTS"
                        $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    }
                }

                #------------------------------------------------------------------
                # NIC and Public IP
                #------------------------------------------------------------------
                
                Write-Verbose "=================================== 9"
                Write-Verbose "info: checking for requested public IP..."
                If ($pubIP -ne "") {
                    Write-Verbose "info: Creating public IP: $ipName..."
                    if (!($TestMode)) {
                        $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Static
                    }
                    Write-Verbose "info: Creating NIC: $nicName..."
                    if (!($TestMode)) {
                        $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PublicIpAddressId $pip.Id -PrivateIpAddress $privIP -Force
                    }
                }
                else {
                    Write-Verbose "info: No public IP address specified for $vmName"
                    Write-Verbose "info: Creating NIC: $nicName..."
                    if (!($TestMode)) {
                        $nic = New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $subnet -PrivateIpAddress $privIP -Force
                    }
                }

                Write-Verbose "=================================== 10"
                Write-Verbose "info: Preparing credentials for VM Local Admin..."

                $SecurePassword = ConvertTo-SecureString "$VmAdminPwd" -AsPlainText -Force
                $Credential     = New-Object System.Management.Automation.PSCredential ($VmAdminUser, $SecurePassword); 
            
                #------------------------------------------------------------------
                # Availability Set
                #------------------------------------------------------------------
                
                Write-Verbose "=================================== 11"
                if ($ASName -ne "") {
                    Write-Verbose "info: Availability set specified: $asname"
                    $aset1 = Get-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asName -ErrorAction SilentlyContinue
                    if (!($aset1)) {
                        Write-Verbose "info: Creating availability set: $asname"
                        if (($ASFDomains -ne "") -and ($ASUDomains -ne "")) {
                            Write-Verbose "info: setting Update Domains to $ASUDomains and Fault Domains to $ASFDomains..."
                            if (!($TestMode)) {
                                $aset1 = New-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asname -Location $location -PlatformUpdateDomainCount $ASUDomains -PlatformFaultDomainCount $ASFDomains
                            }
                        }
                        elseif ($ASFDomains -ne "") {
                            Write-Verbose "info: setting Fault Domains to $ASFDomains..."
                            if (!($TestMode)) {
                                $aset1 = New-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asname -Location $location -PlatformFaultDomainCount $ASFDomains
                            }
                        }
                        elseif ($ASUDomains -ne "") {
                            Write-Verbose "info: setting Update Domains to $ASUDomains..."
                            if (!($TestMode)) {
                                $aset1 = New-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asname -Location $location -PlatformUpdateDomainCount $ASUDomains
                            }
                        }
                        else {
                            Write-Verbose "info: using default Update and Fault domains..."
                            if (!($TestMode)) {
                                $aset1 = New-AzureRmAvailabilitySet -ResourceGroupName $rgName -Name $asname -Location $location
                            }
                        }
                    }
                    else {
                        Write-Verbose "info: Availability set already exists: $asname"
                    }
                    Write-Verbose "info: Creating VM configuration with availability set: $vmName..."
                    if (!($TestMode)) {
                        $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize -AvailabilitySetId $aset1.Id
                    }
                }
                else {
                    Write-Verbose "info: Creating VM configuration: $vmName..."
                    if (!($TestMode)) {
                        $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
                    }
                }

                #------------------------------------------------------------------
                # Update Virtual Machine Configuration
                #------------------------------------------------------------------

                Write-Verbose "=================================== 12"
                Write-Verbose "info: Configuring VM OS and NIC association..."
                # NOTE: customer may want to disable ProvisionVMAgent parameter ***
                if (!($TestMode)) {
                    $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $Credential
                    #$vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
                }
                Write-Verbose "info: attaching NIC to vm configuration..."
                if (!($TestMode)) {
                    $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
                }

                #------------------------------------------------------------------
                # OS Disk
                #------------------------------------------------------------------

                Write-Verbose "=================================== 13"
                $osDiskUri = "$stURI"+"$DestCont/$osdiskname"
                Write-Verbose "info: Disk blob uri is $osDiskUri"
                if ($Publisher -eq "") { 
                    Write-Verbose "info: OS Disk Image from Source VHD $osDiskUri"
                    $SourceBlobURI = "$stURI"+"$SourceCont"+"/$SourceBlob"
                    $DestBlobURI   = "http://$DestSA.blob.core.windows.net/$DestCont/$DestBlob"
                    
                    Write-Verbose "info: Source Blob URI is $SourceBlobURI"
                    Write-Verbose "info: Destination Blob URI is $DestBlobURI"

                    if ((Test-BlobExists -BlobName $SourceBlob -ResourceGroupName $DestRG -StorageAccountName $DestSA -ContainerName $DestCont)) {
                        Write-Verbose "info: destination blob already exists"
                    }
                    else {
                        Write-Verbose "info: destination blob not found, copying from source..."
                        Copy-SourceVHD -SourceBlob $SourceBlob `
                                    -SrcResourceGroupName $SourceRG `
                                    -SrcContainerName $SourceCont `
                                    -SrcStorageAccountName $SourceSA `
                                    -DestResourceGroupName $DestRG `
                                    -DestContainerName $DestCont `
                                    -DestStorageAccountName $DestSA 
                    }
                    Write-Verbose "info: setting VM OS disk..."
                    if (!($TestMode)) {
                        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri `
                                -CreateOption FromImage -SourceImageUri $DestBlobURI -Windows
                    }
                }
                else {
                    
                    Write-Verbose "info: Marketplace Image from publisher $Publisher"
                    if (!($TestMode)) {
                        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $osDiskUri -CreateOption FromImage
                        $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $Publisher `
                                -Offer $Offer -Skus $Skus -Version $Version
                    }
                }
            
                #------------------------------------------------------------------
                # Create Virtual Machine
                #------------------------------------------------------------------
                
                Write-Verbose "=================================== 14"
                if (!($TestMode)) {
                    Write-Output "info: Creating virtual machine: $vmName..."
                    $vmt1  = Get-Date
                    $newvm = New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm
                    $vmt2  = Get-Date
                    $RunTime = [math]::Round(($vmt2 - $vmt1).TotalMinutes,2)
                    Write-Host "info: virtual machine creation took $RunTime minutes"
                }
                else {
                    Write-Output "test: **** SKIPPING VM CREATION FOR TEST MODE: $vmName ****"
                }

                #------------------------------------------------------------------
                # Data Disks
                #------------------------------------------------------------------

                Write-Verbose "=================================== 15"
                Write-Verbose "info: verifying data disk parameters..."
                if ($DataDiskSize1 -ne "") {
                    Write-Verbose "info: Creating Data Disk 1: $dataDiskName1"     
                    $dataDiskUri1 = "$stURI"+"$DestCont"+"/$dataDiskName1"
		            Write-Verbose "info: Data Disk 1 URI: $dataDiskUri1"
                    if (!($TestMode)) {
                        $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName 
                        Write-Verbose "info: Attaching data disk1 ($dataDiskName1) to VM ($vmName)"
                        Add-AzureRmVMDataDisk -VM $vm -Name $dataDiskName1 -VhdUri $dataDiskUri1 `
                                -Caching $Caching -DiskSizeinGB $DataDiskSize1 -CreateOption Empty | Out-Null
                        Update-AzureRmVM -ResourceGroupName $rgName -VM $vm | Out-Null
                    }
                    else {
                        Write-Verbose "test: Attaching data disk 1 ($dataDiskName1) to VM ($vmName)"
                    }
                    if ($DataDiskSize2 -ne "") {
                        Write-Verbose "info: Creating Data Disk 2: $dataDiskName2"     
                        $dataDiskUri2 = "$stURI"+"$DestCont"+"/$dataDiskName2"
		                Write-Verbose "info: Data Disk 2 URI: $dataDiskUri2"
                        if (!($TestMode)) {
                            $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $vmName 
                            Write-Verbose "info: Attaching data disk2 ($dataDiskName1) to VM ($vmName)"
                            Add-AzureRmVMDataDisk -VM $vm -Name $dataDiskName2 -VhdUri $dataDiskUri2 `
                                    -Lun 1 -Caching $Caching -DiskSizeinGB $DataDiskSize2 -CreateOption Empty | Out-Null
                            Update-AzureRmVM -ResourceGroupName $rgName -VM $vm | Out-Null
                        }
                        else {
                            Write-Verbose "test: Attaching data disk 2 ($dataDiskName2) to VM ($vmName)"
                        }
                    }
                    else {
                        Write-Verbose "info: No Data Disk 2 Requested for $vmName"
                    }
                }
                else {
                    Write-Verbose "info: No Data Disk 1 Requested for $vmName"
                }
            
                Write-Verbose "=================================== 16"
                # Write Results to Screen
                if (!($TestMode)) {
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
                }
                else {
                    $RunTime = 0
                }
                Write-Output "info: Virtual Machine: $vmName, completed in $RunTime minutes"
            }
        }
    }
}
else {
    Write-Output "$csvFile contains no data for processing."
}

$StopTime = Get-Date
$RunTime = [math]::Round(($StopTime - $StartTime).TotalMinutes,2)
Write-Host "info: Finished!!! Runtime was $RunTime minutes"
Stop-Transcript
