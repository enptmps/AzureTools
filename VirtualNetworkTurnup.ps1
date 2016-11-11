function VirtualNetworkTurnup
{
    [CmdletBinding()]
    Param(
        [Parameter()][String]$ResourceGroupName,
        [Parameter()][String]$Location,
        [Parameter()][String]$vNetName,
        [Parameter()][String]$SubnetName,
        [Parameter()][String]$vNetAddressRange,
        [Parameter()][String]$SubNetAddressRange

    )

                function CheckVNetAvailability
                {
                    Param(
                        [Parameter()]$vNetName
                    )
                    
                    [PSObject]$Hold = Get-AzureRmVirtualNetwork | ?{$_.name -eq "$vNetName"}
                    
                    If ($Hold)
                    {
                        Return $True
                    }

                }
                # Prep the Subnet
                Write-Verbose "==================================="
                Write-Verbose "SubnetName: $subnetName"
                Write-Verbose "VnetName: $vnetName"
                Write-Verbose "==================================="


                $SuppliedVnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vNetName"})
                [bool]$SubNetIsInVNET = (Get-AzureRmVirtualNetwork `
                                            -ResourceGroupName $SuppliedVnet.ResourceGroupName `
                                            -Name $SubnetName.Name).Subnets | ?{$_.Name -eq "$subnetName"}
                # Subnet AND vnVt exist
                if (($SuppliedVnet) -and ($SubNetIsInVNET))
                {
                    Write-Verbose "vnet and subnet both exist"
                    $subnet = (($SuppliedVnet).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    Write-Verbose "Setting `$subnet to $subnet"
                }
                
                elseif (!($SuppliedVnet))
                {
                    Write-Verbose "vNet does not exist"
                    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    $vnet   = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }
                elseif ((Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"}) -eq $null) {
                    write-verbose "A3... $vnet"
                    write-verbose "B3... $subnet"
                    Write-Verbose "condition 3 = VNET exists BUT subnet does not exist"
                    $vnet = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                    Add-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -VirtualNetwork $vnet -AddressPrefix $subnetPfx
                    $vnet   = Set-AzureRmVirtualNetwork -VirtualNetwork $vnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                    $vnet   = (Get-AzureRmVirtualNetwork | ?{$_.Name -eq "$vnetName"})
                    
                }
                else {
                    Write-Verbose "condition 4"
                    if ($vnet -eq $null) { 
                        Write-Verbose "A4... vnet does not exist" 
                    }
                    else {
                        Write-Verbose "A4... vnet DOES exist"
                    }
                    if ($subnet -eq $null) { 
                        Write-Verbose "B4... subnet does not exist" 
                    }
                    else {
                        Write-Verbose "B4... subnet DOES exist"
                    }
                    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetPfx
                    $vnet   = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $rgnet -Location $Location -AddressPrefix $addressPfx -Subnet $subnet
                    $subnet = ((Get-AzureRmVirtualNetwork).Subnets | ?{$_.Name -eq "$subnetName"}).Id
                }

}