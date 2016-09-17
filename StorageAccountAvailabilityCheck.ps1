# Check Storage Account Availability

param (
    [Parameter()] [String] $saName
)
$StorageAccountNameExists = Get-AzureRmStorageAccountNameAvailability -Name $saName
$StNameExistsInTheTenant  = (Get-AzureRmStorageAccount | ?{$_.StorageAccountName -eq "$saName"})
if ((!($StorageAccountNameExists.NameAvailable)) -and ($StNameExistsInTheTenant)){
    Write-Output "Storage account" $saName "name already taken"
    Write-Output "Please choose another Storage Account Name"
    Write-Output "This Powershell command can be used: Get-AzureRmStorageAccountNameAvailability -Name"
    Break
}
else {
    Write-Output "Storage account: $saName is available"
}