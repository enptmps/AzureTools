#Requires -Version 5.0
#Requires -Module AzureRM.Storage
#Requires -Module DNSClient

class StorageAccountStamp
{
    [String]$StorageAccountName
    [String]$StorageAccountStamp
    [String]$IP4Address

    StorageAccountStamp([String]$StorageAccountName,[String]$StorageAccountStamp,$IP4Address)
    {
        $this.StorageAccountName = $StorageAccountName
        $this.StorageAccountStamp = $StorageAccountStamp
        $this.IP4Address = $IP4Address
    }

    [string] Compare([StorageAccountStamp]$StorageAccountStamp)
    {
        if ($this.StorageAccountStamp -eq $StorageAccountStamp.StorageAccountStamp)
        {
            Return (write-output "$($this.StorageAccountName) resides on the SAME StorageStamp as $($StorageAccountStamp.StorageAccountName)")
        } Else {
            Return (write-output "$($this.StorageAccountName) resides on a DIFFERENT StorageStamp as $($StorageAccountStamp.StorageAccountName)")
        }
    }
}
function Get-StorageAccountStamp
{
    [cmdletbinding()]
    Param(
        [Parameter(ValueFromPipeline=$true)][PSObject]$StorageAccount = (Get-AzureRMStorageAccount)
    )
Begin
{
    $hold = $null
    $OutputObject = @()
}
Process
{

    $hold = $StorageAccount
    Write-Verbose "$($hold.count)"


    ForEach ($blob in $hold)
        {
        $SAName = $blob.StorageAccountName
        $hold = $null
            Write-Verbose "`$Hold is currently $hold"
        $hold = $blob.PrimaryEndpoints.Blob
            Write-Verbose "`$Hold is currently $hold"
        $hold = $hold.subString(8)
            Write-Verbose "`$Hold is currently $hold"
        $BlobEndpoint = $hold.trimEnd('/')
            Write-Verbose "`$BlobEndpoint is set to $BlobEndpoint"
        $StampDiscover = (Resolve-DNSName $BlobEndpoint)
            Write-Verbose "`$StampDiscover found $StampDiscover[1]"
        $SAStamp = $StampDiscover[1].name
        $SAStampIP = $StampDiscover[1].ip4address

        $OutputObject += [StorageAccountStamp]::New("$SaName","$SaStamp","$SAStampIP")
        #$OutputObject = ($OutputObject | Sort-Object StorageAccountStamp)
        }
}
End
{
    Return $OutputObject
}
}