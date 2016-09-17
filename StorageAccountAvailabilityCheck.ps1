# Check Storage Account Availability

param (
    [Parameter()] [String] $saName
)
[bool]$StorageAccountNameAvailable = (Get-AzureRmStorageAccountNameAvailability -Name $saName).NameAvailable
[bool]$StNameExistsInTheTenant  = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
    Write-Verbose "Storage Name is Owned by Us: $StNameExistsInTheTenant"
    Write-Verbose "Storage Name is Available: $StorageAccountNameAvailable"
if ((!($StorageAccountNameAvailable)) -and (!($StNameExistsInTheTenant))){
    Write-Output "Storage account" $saName "name already taken"
    Write-Output "Please choose another Storage Account Name"
    Break
}
else {
    Write-Output "Storage account: $saName is available"
}