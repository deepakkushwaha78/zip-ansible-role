############################################################
# OpenSSH Installation Script
# Author  : Deepak Kushwaha
# Purpose : Install OpenSSH on Windows
############################################################

$Source      = "C:\Users\Administrator\Downloads\OpenSSH-Win64"
$Destination = "C:\Program Files\OpenSSH"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "        OpenSSH Installation Started"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

#----------------------------------------------------------
# Check Source Folder
#----------------------------------------------------------

if (!(Test-Path $Source))
{
    Write-Host "ERROR: Source folder not found." -ForegroundColor Red
    Write-Host $Source
    exit 1
}

#----------------------------------------------------------
# Create Destination Folder
#----------------------------------------------------------

if (!(Test-Path $Destination))
{
    Write-Host "Creating OpenSSH directory..."
    New-Item `
        -ItemType Directory `
        -Path $Destination `
        -Force | Out-Null
}

#----------------------------------------------------------
# Copy OpenSSH Files
#----------------------------------------------------------

Write-Host "Copying OpenSSH files..."

Copy-Item `
    "$Source\*" `
    "$Destination\" `
    -Recurse `
    -Force

#----------------------------------------------------------
# Verify install-sshd.ps1
#----------------------------------------------------------

if (!(Test-Path "$Destination\install-sshd.ps1"))
{
    Write-Host ""
    Write-Host "ERROR : install-sshd.ps1 not found." -ForegroundColor Red
    exit 1
}

#----------------------------------------------------------
# Install OpenSSH
#----------------------------------------------------------

Write-Host ""
Write-Host "Installing OpenSSH..."
Write-Host ""

Set-Location $Destination

powershell.exe `
    -ExecutionPolicy Bypass `
    -File "$Destination\install-sshd.ps1"

if ($LASTEXITCODE -ne 0)
{
    Write-Host ""
    Write-Host "OpenSSH Installation Failed." -ForegroundColor Red
    exit 1
}

#----------------------------------------------------------
# Configure SSHD Service
#----------------------------------------------------------

Write-Host ""
Write-Host "Configuring SSHD Service..."

Set-Service sshd -StartupType Automatic

Start-Service sshd

#----------------------------------------------------------
# Create Firewall Rule (if missing)
#----------------------------------------------------------

if (!(Get-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -ErrorAction SilentlyContinue))
{
    Write-Host "Creating Firewall Rule..."

    New-NetFirewallRule `
        -DisplayName "OpenSSH Server (sshd)" `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 | Out-Null
}

#----------------------------------------------------------
# Validation
#----------------------------------------------------------

Write-Host ""
Write-Host "Validating Installation..."

$Service = Get-Service sshd

if ($Service.Status -eq "Running")
{
    Write-Host ""
    Write-Host "SSHD Service : RUNNING" -ForegroundColor Green
}
else
{
    Write-Host ""
    Write-Host "SSHD Service : NOT RUNNING" -ForegroundColor Red
}

Write-Host ""
Write-Host "Listening Port..."

netstat -ano | findstr ":22"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " OpenSSH Installed Successfully"
Write-Host "==========================================" -ForegroundColor Green
