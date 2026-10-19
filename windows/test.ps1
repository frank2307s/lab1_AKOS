$PASS = 0
$FAIL = 0

$SANDBOX = Join-Path $env:TEMP "lab1_tests_$(Get-Random)"
New-Item -ItemType Directory -Path $SANDBOX -Force | Out-Null
$BACKUP_SCRIPT = Join-Path $PSScriptRoot "backup.ps1"

function Check {
    param($msg, $condition)
    if ($condition) {
        Write-Host "  [PASS] $msg"
        $script:PASS++
    } else {
        Write-Host "  [FAIL] $msg"
        $script:FAIL++
    }
}

function Make-Logs {
    param($dir, $count, $sizeMB)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    for ($i = 1; $i -le $count; $i++) {
        $file = Join-Path $dir ("app_{0:D2}.log" -f $i)
        [System.IO.File]::WriteAllBytes($file, (New-Object byte[] ($sizeMB * 1MB)))
        (Get-Item $file).LastWriteTime = (Get-Date).AddDays(-$i)
    }
}

Write-Host "Testing: $BACKUP_SCRIPT"
Write-Host "Sandbox: $SANDBOX"

Write-Host "`nTest 1: Below threshold"
$log1 = Join-Path $SANDBOX "t1_log"
$bak1 = Join-Path $SANDBOX "t1_bak"
Make-Logs $log1 10 1
& $BACKUP_SCRIPT -LogDir $log1 -N 100 -M 3 -BackupDir $bak1 | Out-Null
Check "archive NOT created" (-not (Test-Path $bak1) -or (Get-ChildItem $bak1).Count -eq 0)
Check "10 files intact" ((Get-ChildItem $log1).Count -eq 10)

Write-Host "`nTest 2: Above threshold"
$log2 = Join-Path $SANDBOX "t2_log"
$bak2 = Join-Path $SANDBOX "t2_bak"
Make-Logs $log2 10 1
& $BACKUP_SCRIPT -LogDir $log2 -N 0 -M 3 -BackupDir $bak2 | Out-Null
$arch2 = (Get-ChildItem $bak2 -Filter "*.tar.gz" | Select-Object -First 1)
Check "archive created" ($null -ne $arch2)
Check "7 files left" ((Get-ChildItem $log2).Count -eq 7)

Write-Host "`nTest 3: Oldest first"
$log3 = Join-Path $SANDBOX "t3_log"
$bak3 = Join-Path $SANDBOX "t3_bak"
Make-Logs $log3 10 1
(Get-Item "$log3\app_05.log").LastWriteTime = (Get-Date).AddDays(-10)
(Get-Item "$log3\app_01.log").LastWriteTime = (Get-Date).AddDays(-1)
& $BACKUP_SCRIPT -LogDir $log3 -N 0 -M 2 -BackupDir $bak3 | Out-Null
Check "app_05 removed" (-not (Test-Path "$log3\app_05.log"))
Check "app_01 NOT deleted" (Test-Path "$log3\app_01.log")

Write-Host "`nTest 4: Archiving failure"
$log4 = Join-Path $SANDBOX "t4_log"
$bak4 = Join-Path $SANDBOX "t4_bak"
Make-Logs $log4 10 1
New-Item -ItemType File -Path $bak4 -Force | Out-Null 
& $BACKUP_SCRIPT -LogDir $log4 -N 0 -M 3 -BackupDir $bak4 | Out-Null
$rc4 = $LASTEXITCODE
Check "error code != 0" ($rc4 -ne 0)
Check "10 files intact" ((Get-ChildItem $log4).Count -eq 10)

Write-Host "`nTest 5: Custom args"
$log5 = Join-Path $SANDBOX "t5_log"
$bak5 = Join-Path $SANDBOX "t5_bak"
Make-Logs $log5 10 1
& $BACKUP_SCRIPT -LogDir $log5 -N 0 -M 1 -BackupDir $bak5 | Out-Null
Check "9 files left" ((Get-ChildItem $log5).Count -eq 9)

Write-Host "`nTest 6: Edge cases"
$log6 = Join-Path $SANDBOX "t6_log"
$bak6 = Join-Path $SANDBOX "t6_bak"
New-Item -ItemType Directory -Path "$log6\sub" -Force | Out-Null
& $BACKUP_SCRIPT -LogDir "$SANDBOX\nope" -N 80 -M 3 -BackupDir $bak6 | Out-Null
Check "missing dir: exit 1" ($LASTEXITCODE -eq 1)
& $BACKUP_SCRIPT -LogDir $log6 -N 0 -M 3 -BackupDir $bak6 | Out-Null
Check "only subfolder: exit 0" ($LASTEXITCODE -eq 0)
Check "subfolder not archived" (-not (Test-Path $bak6) -or (Get-ChildItem $bak6).Count -eq 0)

Remove-Item -Path $SANDBOX -Recurse -Force
Write-Host "`nTotal: passed $PASS, failed $FAIL"
if ($FAIL -gt 0) { exit 1 } else { exit 0 }