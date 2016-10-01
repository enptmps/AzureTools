# VM Disk (DATA)
# Parameter help description
function fnDataDiskLoop{
Param (
[Parameter()] [String] $rgName,
[Parameter()] [String] $vm,
[Parameter()] [String] $diskname,
[Parameter()] [String] $Caching,
[Parameter()] [String] $DataDiskSize1,
[Parameter()] [String] $destCont,
[Parameter()] [String] $saName,
[Parameter()] [Switch] $TestMode
)

        [int]$highlun = '0'

        ($vmName = (Get-AzureRMVM -ResourceGroupName $rgName -Name $vm)) | Out-Null
            Write-Verbose "`$VM config loaded for $($vmName.name)"
        $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
        $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
            Write-Verbose "`$stURI is: $stURI"
        
        
            if (($vmname).StoragePRofile.DataDisks.Count -gt '0'){
            Write-Verbose "Found $highlun LUNs"
            [int]$highlun = (($vmName).StorageProfile.DataDisks.Lun[-1])
            $lunid = $highlun + 1
            Write-Verbose "Setting `$lunID to $lunID"
            } else {
            $lunid = '0'
            Write-Verbose "Setting `$lunID to $lunID"
            }
            Write-Verbose "Found high LUN id of $highlun"
        
        $datadiskname = "$($vmName.name)" +"-" +"$diskname" +"$lunid" +".vhd"
            Write-Verbose "`$datadiskname is set: $datadiskname"
        $dataDiskUri = "$stURI"+"$destCont"+"/$datadiskname"
            Write-Verbose "`$dataDiskURI is $dataDiskURI and `$lunID is set to $lunID"

            
            Write-Verbose "Begining to Create Data Disk: $datadiskname"
    if ($TestMode){
        Write-Output "Test Mode Enabled, use in combination with -Verbose to view planned outcomes"
        Break
    } else {
        $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $($vmName.name) 
        Add-AzureRmVMDataDisk -VM $vmName -Name $datadiskname -VhdUri $dataDiskUri -Caching $Caching -DiskSizeinGB $DataDiskSize1  -CreateOption Empty -Lun $lunid
        Update-AzureRmVM -ResourceGroupName $rgName -VM $vmName

    }
}