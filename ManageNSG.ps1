function Add-EPAzSimpleNSGRule {
    [CmdletBinding()]
    # Parameter help description
    Param(
    [Parameter(Mandatory=$True)][String] $NetworkSecurityGroup,
    [Parameter(Mandatory=$True)][String] $RuleName,
    [Parameter(Mandatory=$True)][Int32] $Priority,
    [Parameter(Mandatory=$True)][String] $Protocol,
    [Parameter(Mandatory=$True)][String] $Port,
    [Parameter(Mandatory=$False)][Switch] $Testing
    )

    Process {
        $nsgHold = (Get-AzureRmNetworkSecurityGroup | ?{$_.name -eq $($NetworkSecurityGroup)})
        Add-AzureRmNetworkSecurityRuleConfig -NetworkSecurityGroup $nsgHold -Priority $Priority `
            -Name $RuleName `
            -Protocol $Protocol `
            -SourcePortRange $Port `
            -DestinationPortRange $Port `
            -SourceAddressPrefix * `
            -DestinationAddressPrefix * `
            -Direction Inbound `
            -Access Allow
        Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsgHold
        }
}

function Remove-EPAzNSGRule {
    [CmdletBinding()]
    # Parameter help description
    Param(
    [Parameter(Mandatory=$True)][String] $NetworkSecurityGroup,
    [Parameter(Mandatory=$True)][String] $RuleName,
    [Parameter(Mandatory=$False)][Switch] $Testing
    )
    Begin {}
    Process {
        $nsgHold = (Get-AzureRmNetworkSecurityGroup | ?{$_.name -eq $($NetworkSecurityGroup)})
        Remove-AzureRmNetworkSecurityRuleConfig -NetworkSecurityGroup $nsgHold -Name $RuleName | Out-Null
        Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsgHold
        }
    End {}
    }