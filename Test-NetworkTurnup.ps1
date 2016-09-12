#Sample Produciton SubscriptionID
#$AzureSubscriptionID = "..."
#$AzureTenantID = "..."
#$AzureSubscriptionName = "..."

# Connection and Sub Selection
#Add-AzureRmAccount
#Add-AzureRmAccount -TenantId $AzureTenantID -SubscriptionId $AzureSubscriptionID

# 
$RegionPri = 'westus'
#$RegionSec = 'centralus'

$StorageRGName = "Core-Storage"
#$FOSTorageRGName = "BCDR-Storage"

$NetworkRGName = "Core-Networking"
#$FONetworkRGName = "BCDR-Networking"
$PriSiteVNet = "Test-AzrCoreNetwork"
$PriSiteVNetPrefix = "192.168.0.0/23"

$SubnetsPri = @{
    'Test-AzrCorp' = "192.168.0.0/24";
    'Test-AzrEdge' = "192.168.1.0/24"
}

$ApplicationRG = @(
    'APP-DEV'
    'APP-QA'
    'APP-PROD'
    'APP-TEST'
    'Core-Infrastructure'

)

$Prisubnets = @()

# Resource Group Creation
New-AzureRmResourceGroup -Name $NetworkRGName -Location $RegionPri
New-AzureRmResourceGroup -Name $StorageRGName -Location $RegionPri
ForEach ($app in $ApplicationRG){
    New-AzureRmResourceGroup -Name $app -Location $RegionPri
}
   
ForEach ($line in $SubnetsPri.GetEnumerator()){
    $Prisubnets += (New-AzureRmVirtualNetworkSubnetConfig -Name $line.Key -AddressPrefix $line.Value)
    }

New-AzureRmVirtualNetwork -ResourceGroupName $NetworkRGName -Name $PriSiteVNet -Location $RegionPri -AddressPrefix $PriSiteVNetPrefix -Subnet $PriSubnets

New-AzureRmStorageAccount -ResourceGroupName 'Core-Storage' -Location $RegionPri -Name "testcorestorage01" -Kind Storage -SkuName Standard_GRS
New-AzureRmStorageAccount -ResourceGroupName 'Core-Storage' -Location $RegionPri  -Name "testdiagtorage01" -Kind Storage -SkuName Standard_LRS

ForEach ($Subnet in ((Get-AzureRMVirtualNetwork -ResourceGroupName $NetworkRGName -Name $PriSiteVNet).Subnets)){New-AzureRmNetworkSecurityGroup -ResourceGroupName $NetworkRGName -Name ($subnet.name +"-NSG") -Location $RegionPri}
$nsg = Get-AzureRmNetworkSecurityGroup | ?{$_.name -like '*-NSG'}
$nsg | Add-AzureRmNetworkSecurityRuleConfig -Name RDP-In -Protocol Tcp -SourcePortRange '*' -DestinationPortRange '3389' -SourceAddressPrefix '*' -DestinationAddressPrefix '*' -Priority 100 -Access 'Allow' -Direction Inbound
$nsg | Set-AzureRmNetworkSecurityGroup