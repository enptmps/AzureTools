<#
.SYNOPSIS
    Copy-AzureBlob copies a Blob file from one resource group, storage account
    and container, to another resource group, storage account, and container.

.PARAMETER SrcBlob
    [string] Name of blob (file) to copy from source container.

.PARAMETER SrcResourceGroupName
    [string] Name of Resource Group where Source storage account resides.

.PARAMETER SrcContainerName
    [string] Name of Container under Source storage account where Source file resides.

.PARAMETER SrcStorageAccountName
    [string] Name of Storage Account which contains the Source File to copy.

.PARAMETER DestResourceGroupName
    [string] Name of Resource Group where Destination Storage Account and Container
    reside, in which Source File will be copied to.

.PARAMETER DestContainerName
    [string] Name of Destination Container where Source File will be copied to.

.PARAMETER DestStorageAccountName
    [string] Name of Destination Storage Account which holds the Storage Container
    where Source File will be copied to.

.PARAMETER OverWrite
    [switch] Forces overwrite of existing Source File in the destination container.

.NOTES
    Requires a valid Azure RM login session.
    If Source File exists in the specified destination (container) it will not be overwritten
#>

param (
    [parameter(Mandatory=$True)] [string] $SrcBlob,
    [parameter(Mandatory=$True)] [string] $SrcResourceGroupName,
    [parameter(Mandatory=$True)] [string] $SrcContainerName,
    [parameter(Mandatory=$True)] [string] $SrcStorageAccountName,
    [parameter(Mandatory=$True)] [string] $DestResourceGroupName,
    [parameter(Mandatory=$True)] [string] $DestContainerName,
    [parameter(Mandatory=$True)] [string] $DestStorageAccountName,
    [parameter(Mandatory=$True)] [switch] $OverWrite
)

$SourceStorageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $SrcResourceGroupName -Name $SrcStorageAccountName)[0].Value
$DestStorageKey   = (Get-AzureRmStorageAccountKey -ResourceGroupName $DestResourceGroupName -Name $DestStorageAccountName)[0].Value

$SourceStorageContext = New-AzureStorageContext –StorageAccountName $SourceStorageAccount -StorageAccountKey $SourceStorageKey
$DestStorageContext   = New-AzureStorageContext –StorageAccountName $DestStorageAccountName -StorageAccountKey $DestStorageKey

$Blobs = (Get-AzureStorageBlob -Context $SourceStorageContext -Container $SrcContainerName | ?{$_.Name -eq $SrcBlob})
$BlobCpyAry = @()
    
$DestBlobs = (Get-AzureStorageBlob -Context $DestStorageContext -Container $DestContainerName | ?{$_.Name -eq $SrcBlob})
if ((!($OverWrite)) -and ($DestBlobs -ne $null)) {
    Write-Output "$SrcBlob already exists in destination."
}
else {
    
    foreach ($Blob in $Blobs) {
        Write-Output "info: Copying $Blob.Name"
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
