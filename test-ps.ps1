$cert = New-SelfSignedCertificate -DnsName "Win", "Ubu" -CertStoreLocation Cert:\CurrentUser\My -KeyExportPolicy Exportable
$pwd = ConvertTo-SecureString -String "ArcBox123\!" -Force -AsPlainText
$pfxBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $pwd)
$pfxBase64 = [Convert]::ToBase64String($pfxBytes)

$code = {
    $pswd = "ArcBox123\!"
    $pfxPath = "$Env:TEMP\test.pfx"
    [System.IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($using:pfxBase64))
    Write-Host "Success"
}
Invoke-Command -ScriptBlock $code
