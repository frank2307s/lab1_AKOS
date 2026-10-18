param(
    [Parameter(Mandatory = $true)][string]$LogDir,
    [int]$N = 80,
    [int]$M = 5,
    [string]$BackupDir = $(if ($env:BACKUP_DIR) { $env:BACKUP_DIR } else { "Backup" })
)

if (-not (Test-Path -LiteralPath $LogDir -PathType Container)) {
    Write-Host "Error: '$LogDir' is not a directory"
    exit 1
}

$logPath = (Resolve-Path -LiteralPath $LogDir).Path
Write-Host "Working with directory: $logPath"

$vol = Get-Volume -FilePath $logPath
$used = [int][math]::Ceiling(($vol.Size - $vol.SizeRemaining) * 100 / $vol.Size)
Write-Host "Used: $used%"

if ($used -gt $N) {
    Write-Host "Usage $used% is above threshold $N%, archiving $M oldest files"
    $files = @(Get-ChildItem -LiteralPath $logPath -File | Sort-Object LastWriteTime | Select-Object -First $M)
    
    if ($files.Count -eq 0) {
        Write-Host "No files to archive"
        exit 0
    }

    Write-Host "Files selected for archiving:"
    $files | ForEach-Object { Write-Host $_.Name }

    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $archive = Join-Path (Resolve-Path -LiteralPath $BackupDir).Path "backup_$stamp.tar.gz"

    tar -czf $archive -C $logPath $files.Name

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Archive created: $archive"
        foreach ($f in $files) {
            Remove-Item -LiteralPath $f.FullName
        }
        Write-Host "Original files removed from $logPath"
    }
    else {
        Write-Host "Error: archiving failed"
        exit 1
    }
}
else {
    Write-Host "Usage $used% is within threshold $N%, nothing to do"
}
'@ -Encoding utf8