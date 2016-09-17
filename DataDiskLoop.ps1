# VM Disk (DATA)
# Parameter help description
Param (
[Parameter()] [String] $rgName,
[Parameter()] [String] $vm,
[Parameter()] [String] $datadiskname,
[Parameter()] [String] $Caching,
[Parameter()] [String] $DataDiskSize1,
[Parameter()] [String] $destCont,
[Parameter()] [String] $saName
)

    $vmName = (Get-AzureRMVM -ResourceGroupName $rgName -Name $vm)
        Write-Verbose "`$VM config loaded for $($vmName.name)"
    $stAcct = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
    $stURI = $stAcct.PrimaryEndpoints.Blob.ToString()
        Write-Verbose "`$stURI is: $stURI" 
    $datadiskname = "$($vmName.name)" +"-datadisk1.vhd"
        Write-Verbose "`$datadiskname is set: $datadiskname"
    $dataDiskUri = "$stURI"+"$destCont"+"/$datadiskname"
        Write-Verbose "`$dataDiskURI is $dataDiskURI"
        
    [int]$highlun = (($vmName).StorageProfile.DataDisks.Lun[-1])
    $lunid = $highlun + 1
        Write-Verbose "Found high LUN id of $highlun | Assigning $lunid to new DataDisk $dataDiskUri"
        
        Write-Verbose "Begining to Create Data Disk: $datadiskname"
    $vm = Get-AzureRmVM -ResourceGroupName $rgName -Name $($vmName.name) 
    Add-AzureRmVMDataDisk -VM $vmName -Name $datadiskname -VhdUri $dataDiskUri -Caching $Caching -DiskSizeinGB $DataDiskSize1  -CreateOption Empty -Lun $lunid
    Update-AzureRmVM -ResourceGroupName $rgName -VM $vmName
