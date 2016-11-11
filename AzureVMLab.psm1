# Set-Alias -Name FunctionName1 -Value FunctionName2 -Scope Global

<#
AzureVMLab.psm1

.SYNOPSIS
    Functions library for evil deeds
 
.DESCRIPTION
    Module of functions to help ruin a good Azure tenant

.AUTHOR
    David "Code Destroyer" Stein 

.DATECREATED
    10/04/2016
#>


<#
.SYNOPSIS
    Return the full path to the executing script file
.DESCRIPTION
    Get-ScriptPath returns teh full path of the executing script file
#>

function Get-EP-ScriptPath {
    return $(Split-Path -Parent $MyInvocation.MyCommand.Definition).ToString()
}

<#
.SYNOPSIS
    Debug printing
.DESCRIPTION
    Write-Test prints out a caption and message with tab indentation
    and alt coloring text for debugging purposes.
.PARAMETER Caption
    The text label to describe the value shown
.PARAMETER Msg
    The value to be shown with the associated caption
#>

function Write-EP-Test {
    param ($caption, $msg)
    Write-Host "`t$caption`:`t$msg" -ForegroundColor Yellow
}

<#
.SYNOPSIS
    Return TRUE if vm "Name" value has a semi-colon prefix (comment)
.DESCRIPTION
    Test-CommentLine returns TRUE if the CSV file row begins with
    a semi-colon (;).  This is internalized after calling the 
    Import-Csv cmdlet, so the semi-colon is attached to the first
    logical column value only.  Therefore, this function inspects
    the first item in the array for the current rowset only.
.PARAMETER CsvRow
    The array representing a single row from the array defined
    from reading in a CSV file using Import-Csv
#>

function Test-EP-CommentLine {
    param (
        [parameter(Mandatory=$False)] $CsvRow
    )
    ($CsvRow.Name.Substring(0,1) -eq ";")
}

<#
.SYNOPSIS
    Create local admin user account for insertion into Azure VM guest OS
.DESCRIPTION
    Request-EP-LocalAdminAccount creates the user account object to 
    be created inside of an Azure RM VM as a local administrator.
.PARAMETER UserID
    Name of the local user account to create in the VM
.PARAMETER Testing
    Testing mode is either True or False
#>

function Request-EP-LocalAdminAccount {
    param (
        [parameter(Mandatory=$False)] $User,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-LocalAdminAccount" -ForegroundColor Green
    if ($User -eq $null) {
        Write-Host "setting credentials for local administrator account..." -ForegroundColor Yellow
        $result = Get-Credential -Message "Type the name and password of the local administrator account."
    }
    else {
        Write-Host "credentials are already defined" -ForegroundColor Yellow
        $result = $User
    }
    $result
}

<#
.SYNOPSIS
    Import and parse CSV file into a hash structure
.DESCRIPTION
    Request-EP-CsvData reads an input CSV file and returns a hash table
.PARAMETER InputFile
    Path and Filename of CSV to import
#>

function Request-EP-CsvData {
    param (
        [parameter(Mandatory=$True)] [string] $InputFile
    )
    Write-Host "** Request-EP-CsvData" -ForegroundColor Green
    $ScriptPath = Get-EP-ScriptPath
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
    Write-Host "reading input file: $CsvFile..." -ForegroundColor Yellow
    Import-Csv $CsvFile
}

<#
.SYNOPSIS
    Get or Create an Azure Resource Group
.DESCRIPTION
    Request-EP-AzureResourceGroup first tries to request the named Azure 
    resource group.  If the resource group is not defined, it is created.
    In either case, the result resource group object is returned.
.PARAMETER CsvRow
    The CSV logical rowset, from which the "ResourceGroup" column value
    is used to identify the resource group name.
.PARAMETER Testing
    Testing mode is either True or False
#>

function Request-EP-AzureResourceGroup {
    param (
        [parameter(Mandatory=$True)] $CsvRow,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-AzureResourceGroup" -ForegroundColor Green
    $rgName = $CsvRow.ResourceGroup
    $location = $CsvRow.Location
    if (!($Testing -eq $True)) {
        $rg = Get-AzureRmResourceGroup -Name $rgName -Location $Location -ErrorAction SilentlyContinue
        if ($rg -eq $null) {
            Write-Host "creating resource group: $rgName..." -ForegroundColor Yellow
            $result = New-AzureRmResourceGroup -Name $rgName -Location $Location
        }
        else {
            Write-Host "resource group already exists: $rgName" -ForegroundColor Yellow
            $result = $rg
        }
    }
    else {
        Write-EP-Test "rgname" $rgName
        Write-EP-Test "location" $location
    }
    $result
}

<#
.SYNOPSIS
    Get or Create an Azure RM Storage Account
.DESCRIPTION
    Request-EP-AzureStorageAccount returns an existing storage account, or
    creates a new storage account if the named account does not exist.
.PARAMETER CsvRow
    The CSV logical rowset, from which the "ResourceGroup" column value
    is used to identify the resource group name.
.PARAMETER Testing
    Testing mode is either True or False
#>

function Request-EP-AzureStorageAccount {
    param (
        [parameter(Mandatory=$True)] $CsvRow,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-AzureStorageAccount" -ForegroundColor Green
    $acctName = $CsvRow.StorageAcct
    $rgName   = $CsvRow.ResourceGroup
    $sku      = $CsvRow.SKU
    $location = $CsvRow.Location
    if (!($Testing)) {
        $test = Get-AzureRmStorageAccount -ResourceGroupName $rgName -Name $acctName -ErrorAction SilentlyContinue
        if ($test -eq $null) {
            Write-Host "creating storage account: $acctName..." -ForegroundColor Yellow
            $result = New-AzureRmStorageAccount -ResourceGroupName $rgName -Name $acctName -SkuName $SKU -Kind Storage -Location $Location -ErrorAction SilentlyContinue
        }
        else {
            Write-Host "storage account already exists: $acctName" -ForegroundColor Yellow
            $result = $test
        }
    }
    else {
        Write-EP-Test "acctName" $acctName
        Write-EP-Test "rgName" $rgName
        Write-EP-Test "sku" $sku
        Write-EP-Test "location" $location
    }
    $result
}

<#
.SYNOPSIS
    Get or Create an Azure RM virtual network
.DESCRIPTION
    Request-EP-AzureVMNetwork gets or creates an Azure RM virtual network
    if it does not already exist.
.PARAMETER CsvRow
.PARAMETER Testing
#>

function Request-EP-AzureVMNetwork {
    param (
        [parameter(Mandatory=$True)] $CsvRow,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-AzureVMNetwork" -ForegroundColor Green
    $rgName   = $CsvRow.ResourceGroup
    $vNetName = $CsvRow.VNet
    $SubName  = $CsvRow.subnetName
    $addPref  = $CsvRow.AddressRange
    $location = $CsvRow.Location

    if (!($Testing)) {
        $ssubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $subName -ErrorAction SilentlyContinue
        if ($ssubnet -eq $null) {
            $sSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subName -AddressPrefix $addPref -ErrorAction SilentlyContinue
        }
        $result = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
        if ($result -ne $null) {
            Write-Host "virtual network already exists: $vnetName"
        }
        else {
            Write-Host "creating virtual network:$vnetName in $Location..."
            $result = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgName -Location $Location -AddressPrefix $addPref -Subnet $SSubnet
        }
    }
    else {
        Write-EP-Test "rgName" $rgName
        Write-EP-Test "vnetName" $vNetName
        Write-EP-Test "subName" $SubName
        Write-EP-Test "addPref" $addPref
        Write-EP-Test "Location" $location
    }
    $result
}

<#
.SYNOPSIS
    Create a new Azure RM VM NIC
.DESCRIPTION
    Request-EP-AzureVMNIC creates a new NIC and Public IP
.PARAMETER CsvRow
.PARAMETER Testing
#>

function Request-EP-AzureVMNIC {
    param (
        [parameter(Mandatory=$True)] $CsvRow,
        [parameter(Mandatory=$True)] $vnet,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-AzureVMNIC" -ForegroundColor Green
    $ipName   = "$($CsvRow.Name)pip1"
    $nicName  = "$($CsvRow.Name)nic1"
    $rgName   = $CsvRow.ResourceGroup
    $location = $CsvRow.Location

    if (!($Testing)) {
        Write-Host "-- creating public IP: $ipName..." -ForegroundColor Yellow
        $pip = New-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgName -Location $Location -AllocationMethod Dynamic
        Write-Host "-- creating NIC: $nicName..." -ForegroundColor Yellow
        $result = $(New-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName -Location $Location -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id)
    }
    else {
        Write-EP-Test "ipName" $ipName
        Write-EP-Test "nicName" $nicName
    }
    $result
}

<#
.SYNOPSIS
    Return Azure RM Blob storage URI based on Storage Account Name
.DESCRIPTION
    Request-EP-AzureBlobURI returns the URI path for the blob container
    under the specified Azure RM storage account
.PARAMETER Acct
    The Azure RM storage account name
.PARAMETER Testing
#>

function Request-EP-AzureBlobURI {
    param (
        [parameter(Mandatory=$True)] $Acct,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-AzureBlobURI" -ForegroundColor Green
    if (!($Testing)) {
        if ($Acct -ne $null) {
            $result = $Acct.PrimaryEndpoints.Blob.ToString()
        }
    }
    else {
        Write-EP-Test "acct" $Acct
        Write-EP-Test "uri" $result
    }
    $result
}

<#
.SYNOPSIS
    Return Azure RM disk URI based on VM name and Storage Blob URI path
.DESCRIPTION
    Request-EP-AzureDiskURI returns the URI path for the blob container
    and VM-specific disk under the specified Azure RM storage account
.PARAMETER CsvRow
.PARAMETER BlobURI
.PARAMETER Testing
#>

function Request-EP-AzureDiskURI {
    param (
        [parameter(Mandatory=$True)] $CsvRow,
        [parameter(Mandatory=$True)] $BlobURI,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Request-EP-AzureDiskURI" -ForegroundColor Green
    $vmName = $CsvRow.Name
    $diskname   = "$vmName"+"-os.vhd"
    $result = "$BlobURI"+"vhds/$diskname"
    if ($Testing) {
        Write-EP-Test "vmname" $vmName
        Write-EP-Test "diskname" $diskname
        Write-EP-Test "diskURI" $result
    }
    $result
}

<#
.SYNOPSIS
    Create a new Azure RM virtual machine
.DESCRIPTION
    Provision-EP-VM creates a new Azure RM virtual machine
.PARAMETER CsvRow
.PARAMETER Nic
.PARAMETER Testing
#>

#----------------------------------------------------------------------
# create VM

function Provision-EP-VM {
    param (
        [parameter(Mandatory=$True)] $CsvRow,
        [parameter(Mandatory=$True)] $nic,
        [parameter(Mandatory=$True)] $DiskURI,
        [parameter(Mandatory=$False)] [bool] $Testing
    )
    Write-Host "** Provision-EP-VM" -ForegroundColor Green
    $rgName   = $CsvRow.ResourceGroup
    $location = $CsvRow.Location
    $vmname   = $CsvRow.Name
    $vmSize   = $CsvRow.Size
    $vmOS     = $CsvRow.OS
    $diskname = "$vmName"+"-os.vhd"
    $nicName  = "$($CsvRow.Name)nic1"
    $ipName   = "$($CsvRow.Name)pip1"
    if (!($Testing)) {
        $vm = New-AzureRmVMConfig -VMName $vmName -VMSize $vmSize
        $vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $vmname -Credential $LocalUser -ProvisionVMAgent -EnableAutoUpdate
        $vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName MicrosoftWindowsServer -Offer WindowsServer -Skus $vmOS -Version "latest"
        $vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic.Id
        Write-Host "vm os disk blob uri is $DiskUri"
        $vm = Set-AzureRmVMOSDisk -VM $vm -Name $diskName -VhdUri $DiskUri -CreateOption FromImage
        Write-Host "creating virtual machine: $vmName..." -ForegroundColor Green
        New-AzureRmVM -ResourceGroupName $rgName -Location $Location -VM $vm
        $vmNic  = Get-AzureRmNetworkInterface -Name $nicName -ResourceGroupName $rgName
        $pvtIP  = $($vmNic.IpConfigurations).PrivateIpAddress
        $pubIP  = $(Get-AzureRmPublicIpAddress -Name $ipName -ResourceGroupName $rgname).IpAddress
        Write-EP-Test "Private IP" $pvtIP
        Write-EP-Test "Public IP" $pubIP
    }
    else {
        Write-EP-Test "vmname" $vmname
        Write-EP-Test "vmsize" $vmsize
        Write-EP-Test "vmos" $vmos
    }
    $vm
}

#----------------------------------------------------------------------
# Test/Debug Print the CSV row set

function Display-EP-TestInputs {
    param (
        [parameter(Mandatory=$False)] $CsvRow
    )
    Write-Host "----- test mode -----" -ForegroundColor Green
    $csvRow
}

function Revert-EP-Resources {
    param (
        [parameter(Mandatory=$True)] $CsvDataSet
    )
    Write-Host "** Revert-EP-Resources" -ForegroundColor Green
    if ($CsvDataSet -ne $null) {
        $done = @()
        Write-Host "input data loaded successfully." -ForegroundColor Cyan
        foreach ($row in $CsvDataSet) {
            if (!(Test-EP-CommentLine $row)) {
                $rgName = $row.ResourceGroup
                $Location = $row.Location
                if (!($done.Contains($rgName))) {
                    Write-Host "verifying resource group $rgName..." -ForegroundColor Green
                    $rg = Get-AzureRmResourceGroup -Name $rgName -Location $Location -ErrorAction SilentlyContinue
                    if ($rg -ne $null) {
                        Write-Host "removing RM Resource Group $rgName..." -ForegroundColor Green
                        Remove-AzureRmResourceGroup -Name $rgName -Force
                        $done += $rgName
                    }
                    else {
                        Write-Host "resource group $rgName already removed." -ForegroundColor Green
                    }
                }
            }
        }
    }
}