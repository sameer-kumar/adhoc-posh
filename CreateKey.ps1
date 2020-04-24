$key = New-Object byte[] 32
$generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$generator.GetBytes($key)
$apiKey = [Convert]::ToBase64String($key)
$generator.Dispose()