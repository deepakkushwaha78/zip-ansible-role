# =====================================================
# OpenSSH Installation Script
# =====================================================

$Source = "C:\Users\Administrator\Downloads\OpenSSH-Win64"
$Destination = "C:\Program Files\OpenSSH"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " OpenSSH Installation Started"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Verify source folder exists
if (!(Test-Path $Source))
{
    Write-Host "ERROR: Source folder not found:" -ForegroundColor Red
    Write-Host $Source
    exit 1
}

# Create destination folder
if (!(Test-Path $Destination))
{
    Write-Host "Creating $Destination ..."
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

# Copy OpenSSH files
Write-Host "Copying OpenSSH files..."
Copy-Item "$Source\*" "$Destination\" -Recurse -Force

# Change directory
Set-Location $Destination

Write-Host "Current Directory:"
Get-Location

# Verify install script exists
if (!(Test-Path ".\install-sshd.ps1"))
{
    Write-Host "ERROR: install-sshd.ps1 not found." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Running install-sshd.ps1..."
Write-Host ""

powershell.exe -ExecutionPolicy Bypass -File ".\install-sshd.ps1"

if ($LASTEXITCODE -ne 0)
{
    Write-Host "Installation script failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Configuring sshd service..."

Set-Service -Name sshd -StartupType Automatic

Start-Service sshd

Write-Host ""
Write-Host "Checking sshd Service..."

Get-Service sshd

Write-Host ""
Write-Host "Checking Port 22..."

netstat -ano | findstr ":22"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host " OpenSSH Installed Successfully"
Write-Host "==========================================" -ForegroundColor Green
