<#
  autologon.ps1 -- make the VM a usable interactive GUI session for pywinauto.
  Phase 0 finding: GUI automation needs a real, unlocked, logged-in desktop.
  The gusztavvargadr box default account is vagrant/vagrant.
  Pure ASCII (PS reads .ps1 as ANSI).
#>
$ErrorActionPreference = "Stop"
$winlogon = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
Set-ItemProperty $winlogon -Name AutoAdminLogon  -Value "1"
Set-ItemProperty $winlogon -Name DefaultUserName -Value "vagrant"
Set-ItemProperty $winlogon -Name DefaultPassword -Value "vagrant"
# "." = local machine; hostname-independent (vagrant renames the host AFTER this
# provisioner runs, so a literal name would go stale and break autologon).
Set-ItemProperty $winlogon -Name DefaultDomainName -Value "."
Set-ItemProperty $winlogon -Name ForceAutoLogon -Value "1"

# never lock / blank the screen (a locked desktop breaks UIA)
$desktop = "HKCU:\Control Panel\Desktop"
Set-ItemProperty $desktop -Name ScreenSaveActive -Value "0" -ErrorAction SilentlyContinue
$noLock = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
New-Item -Path $noLock -Force | Out-Null
Set-ItemProperty $noLock -Name NoLockScreen -Value 1 -Type DWord
# disable lock screen timeout / require-signin
powercfg /change monitor-timeout-ac 0
powercfg /change standby-timeout-ac 0
Write-Host "autologon + no-lock configured (reboot applies autologon)."
