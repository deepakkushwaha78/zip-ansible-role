#############################################################
# ZIP Deployment Script
# Author : Deepak
# Purpose: Copy ZIP to multiple Windows Servers using SMB
#############################################################

$SourceZip = "C:\builds\zip-ansible-role-main.zip"

$DestinationFolder = "Users\Administrator\Downloads"

$CsvFile = "C:\scripts\servers.csv"

$LogFile = "C:\scripts\deployment.log"

#-----------------------------------------

if (!(Test-Path $SourceZip))
{
    Write-Host "Source ZIP not found." -ForegroundColor Red
    exit
}

$Servers = Import-Csv $CsvFile

foreach($Server in $Servers)
{
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Server : $($Server.Name)"
    Write-Host "IP     : $($Server.IP)"
    Write-Host "========================================" -ForegroundColor Cyan

    # Test Port 445

    $Result = Test-NetConnection $Server.IP -Port 445 -WarningAction SilentlyContinue

    if(!$Result.TcpTestSucceeded)
    {
        Write-Host "Port 445 Closed" -ForegroundColor Red

        Add-Content $LogFile "$($Server.Name),FAILED,445 Closed"

        continue
    }

    Write-Host "Port 445 Reachable" -ForegroundColor Green

    try
    {
        # Remove previous drive if exists

        if(Get-PSDrive Z -ErrorAction SilentlyContinue)
        {
            Remove-PSDrive Z -Force
        }

        # Create Credential

        $SecurePassword = ConvertTo-SecureString $Server.Password -AsPlainText -Force

        $Credential = New-Object System.Management.Automation.PSCredential(
            $Server.Username,
            $SecurePassword
        )

        # Map Remote Drive

        New-PSDrive `
            -Name Z `
            -PSProvider FileSystem `
            -Root "\\$($Server.IP)\C$" `
            -Credential $Credential `
            -ErrorAction Stop | Out-Null

        # Create Folder if not exists

        if(!(Test-Path "Z:\$DestinationFolder"))
        {
            New-Item `
                -ItemType Directory `
                -Path "Z:\$DestinationFolder" `
                -Force | Out-Null
        }

        # Copy ZIP

        Copy-Item `
            $SourceZip `
            "Z:\$DestinationFolder\" `
            -Force

        Write-Host "ZIP Copied Successfully" -ForegroundColor Green

        Add-Content $LogFile "$($Server.Name),SUCCESS"

        # Remove Drive

        Remove-PSDrive Z -Force

    }
    catch
    {
        Write-Host ""
        Write-Host $_.Exception.Message -ForegroundColor Red

        Add-Content $LogFile "$($Server.Name),FAILED,$($_.Exception.Message)"

        if(Get-PSDrive Z -ErrorAction SilentlyContinue)
        {
            Remove-PSDrive Z -Force
        }
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Deployment Completed"
Write-Host "========================================" -ForegroundColor Green
