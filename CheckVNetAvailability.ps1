function CheckVNetAvailability
{
    Param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty]
        [ValidateScript({If ($_ -match '^([a-zA-Z0-9-]){2,64}$')
        {
            $True
        } Else {
            Throw "$_ is not a valid Azure VirtualNetwork Name (2-64 Alphanumeric and hyphen)"  
        }})]
        $vNetName
    )
                    
    [PSObject]$Hold = Get-AzureRmVirtualNetwork | ?{$_.name -eq "$vNetName"}
                    
    If ((!$Hold))
    {
        Return $True
    } Else {
        Return $False
    }
}