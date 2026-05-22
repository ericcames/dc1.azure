# WinRM bootstrap for Ansible — runs once on first boot via Azure custom_data.
#
# Configures WinRM over HTTPS with a self-signed certificate and opens the
# firewall so AAP / ansible.windows can connect. Pair with these inventory
# vars on the windows group:
#
#   ansible_connection: winrm
#   ansible_winrm_transport: ntlm
#   ansible_winrm_server_cert_validation: ignore
#   ansible_port: 5986

$ErrorActionPreference = "Stop"

# Ensure WinRM service is running and set to start automatically.
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM

# Create a self-signed cert for the local hostname. Good enough for demo;
# replace with a real cert for production-style work.
$cert = New-SelfSignedCertificate `
    -DnsName $env:COMPUTERNAME `
    -CertStoreLocation Cert:\LocalMachine\My `
    -KeyUsage DigitalSignature, KeyEncipherment `
    -KeyLength 2048

# Remove any pre-existing HTTPS listener, then create one bound to the cert.
# Use PowerShell-native New-WSManInstance instead of `cmd.exe /c winrm ...`
# — the latter's nested quoting gets mangled when the script runs under the
# SYSTEM context via the Azure CustomScriptExtension, resulting in a listener
# with an empty CertificateThumbprint.
Get-ChildItem -Path WSMan:\localhost\Listener `
    | Where-Object { $_.Keys -contains 'Transport=HTTPS' } `
    | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

New-WSManInstance -ResourceURI 'winrm/config/Listener' `
    -SelectorSet @{Address='*'; Transport='HTTPS'} `
    -ValueSet @{Hostname=$env:COMPUTERNAME; CertificateThumbprint=$cert.Thumbprint} | Out-Null

# Allow basic + NTLM auth, raise envelope size for large playbooks.
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service '@{AllowUnencrypted="false"}'
winrm set winrm/config '@{MaxEnvelopeSizekb="8192"}'

# Open the firewall on 5986/TCP for WinRM-HTTPS.
$ruleName = "WinRM-HTTPS-In-TCP"
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $ruleName `
        -DisplayName "Windows Remote Management (HTTPS-In)" `
        -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow `
        -Profile Any | Out-Null
}

# Allow ICMPv4 echo so a quick ping works during demo troubleshooting.
$pingRule = "ICMPv4-In-Echo-Request"
if (-not (Get-NetFirewallRule -Name $pingRule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name $pingRule `
        -DisplayName "Allow ICMPv4 Echo Request" `
        -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow `
        -Profile Any | Out-Null
}

Write-Host "WinRM-HTTPS bootstrap complete on $env:COMPUTERNAME (thumbprint $($cert.Thumbprint))"
