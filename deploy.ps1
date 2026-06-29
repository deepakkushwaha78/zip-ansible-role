############################################################
# ZIP Distribution Script
############################################################

# Source ZIP
$SourceZip = "C:\builds\zip-ansible-role-main.zip"

# Destination Folder
$DestinationFolder = "Users\Administrator\Downloads"

# CSV File
$CsvFile = "C:\scripts\servers.csv"

# Log File
$LogFile = "C:\scripts\deployment.log"

# Verify ZIP exists
if (!(Test-Path $SourceZip)) {
    Write-Host "Source ZIP not found: $SourceZip" -ForegroundColor Red
    exit
}

# Verify CSV exists
if (!(Test-Path $CsvFile)) {
    Write-Host "CSV file not found: $CsvFile" -ForegroundColor Red
    exit
}

$Servers = Import-Csv $CsvFile

foreach ($Server in $Servers)
{
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "Server : $($Server.Name)"
    Write-Host "IP     : $($Server.IP)"
    Write-Host "==========================================" -ForegroundColor Cyan

    # Check Port 445
    $Test = Test-NetConnection $Server.IP -Port 445 -WarningAction SilentlyContinue

    if (!$Test.TcpTestSucceeded)
    {
        Write-Host "Port 445 is not reachable." -ForegroundColor Red
        Add-Content $LogFile "$($Server.Name),$($Server.IP),FAILED,Port 445 Closed"
        continue
    }

    Write-Host "Port 445 Reachable." -ForegroundColor Green

    # Connect to C$
    cmd.exe /c "net use \\$($Server.IP)\C$ `"$($Server.Password)`" /user:$($Server.Username) /persistent:no" | Out-Null

    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Authentication Failed." -ForegroundColor Red
        Add-Content $LogFile "$($Server.Name),$($Server.IP),FAILED,Authentication Failed"
        continue
    }

    try
    {
        # Destination UNC Path
        $UNC = "\\$($Server.IP)\C$\$DestinationFolder"

        # Copy ZIP
        Copy-Item $SourceZip $UNC -Force

        Write-Host "ZIP Copied Successfully." -ForegroundColor Green

        Add-Content $LogFile "$($Server.Name),$($Server.IP),SUCCESS"
    }
    catch
    {
        Write-Host $_.Exception.Message -ForegroundColor Red

        Add-Content $LogFile "$($Server.Name),$($Server.IP),FAILED,$($_.Exception.Message)"
    }

    # Disconnect Share
    cmd.exe /c "net use \\$($Server.IP)\C$ /delete /y" | Out-Null
}

Write-Host ""
Write-Host "Deployment Completed." -ForegroundColor Green
