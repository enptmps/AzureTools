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