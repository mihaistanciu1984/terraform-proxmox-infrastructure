#ps1_sysprep_bootstrap
$Username = "admin_local"
$Password = ConvertTo-SecureString "PasswordPlainText" -AsPlainText -Force
New-LocalUser -Name $Username -Password $Password -Description "Admin creat prin Terraform"
Add-LocalGroupMember -Group "Administrators" -Member $Username

# Activează protocolul RDP
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"