# Clean-Processor.ps1
# Автоматическое удаление без подтверждения

### КОНФИГУРАЦИЯ ###
$DaysOld = 7
$ConfirmEachFile = $false  # Автоматический режим

### ИМПОРТ МОДУЛЯ ###
$modulePath = "C:\Prints\PrintScrips\Modules\PrintFunctions\PrintFunctions.psd1"
try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "Module PrintFunctions successfully loaded" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Unable to load module" -ForegroundColor Red
    Write-Host "ERROR details: $_" -ForegroundColor Yellow
    exit 1
}

# 2. Задание пути к логу
$logPath = "C:\Prints\PrintScrips\Logs\CleanProcessor-log.txt"

# 3. Проверка доступности директории лога (теперь в основном скрипте)
if (-not (Test-DirectoryWritable -Path (Split-Path $logPath -Parent))) {
    Write-Host "Log directory is not writable. Exiting..." -ForegroundColor Red
    exit 1
}

# 4. Инициализация модуля с путем к логу
try {
	Initialize-Module -LogFilePath $logPath
	 Write-Host "Module PrintFunctions successfully initialized with variable logPath" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Unable to initilize module" -ForegroundColor Red
    Write-Host "ERROR details: $_" -ForegroundColor Yellow
	exit 1
}	

#5. Задание рабочего каталога
$SourceDirectory = "C:\Prints\output"
if (-not (Test-DirectoryWritable -Path $SourceDirectory)) {
    Write-Host "Work directory is not writable. Exiting..." -ForegroundColor Red
    exit 1
}


Write-Log "=== Auto cleanup started ==="

### ПОИСК И УДАЛЕНИЕ ###
try {
    $printedMarkers = Get-ChildItem -Path $SourceDirectory -Filter "*.printed" -Recurse -File
    $stats = @{Removed = 0; Skipped = 0; Errors = 0}
    
    foreach ($marker in $printedMarkers) {
        $originalFilePath = $marker.FullName -replace '\.printed$', ''
        $markerAge = (Get-Date) - $marker.LastWriteTime
        
        if ($markerAge.TotalDays -ge $DaysOld) {
            try {
                # Удаляем оригинальный файл
                if (Test-Path $originalFilePath) {
                    Remove-Item -Path $originalFilePath -Force -ErrorAction Stop
                }
                
                # Удаляем маркер
                Remove-Item -Path $marker.FullName -Force -ErrorAction Stop
                
                $stats.Removed++
                Write-Log "Removed: $([System.IO.Path]::GetFileName($originalFilePath)) (age: $([math]::Round($markerAge.TotalDays,1)) days)"
            }
            catch {
                $stats.Errors++
                Write-Log "ERROR removing $($marker.FullName): $_"
            }
        }
        else {
            $stats.Skipped++
        }
    }
    
    Write-Log "Auto cleanup completed. Removed: $($stats.Removed), Skipped: $($stats.Skipped), Errors: $($stats.Errors)"
}
catch {
    Write-Log "FATAL ERROR: $_"
}