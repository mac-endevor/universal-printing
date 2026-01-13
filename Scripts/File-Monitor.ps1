# FileMonitor.ps1 - Монитор папки для отправки файлов в очередь MSMQ

### 0. ИНИЦИАЛИЗАЦИЯ ###

# 1. Импорт модуля
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
$global:logPath = "C:\Prints\PrintScrips\Logs\Monitor-log.txt"

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

### 1. НАЧАЛО ОБРАБОТКИ ###

Write-Log "=== FileMonitor started ==="


### 2. ПРОВЕРКА И НАСТРОЙКА MSMQ ###
Add-Type -AssemblyName System.Messaging
[System.Reflection.Assembly]::LoadWithPartialName("System.Messaging") | Out-Null

$global:queuePath = ".\private$\printprocessorqueue"
if (-not [System.Messaging.MessageQueue]::Exists($queuePath)) {
    Write-Log "Critical error: Queue '$queuePath' not found. FileMontor stopped"
    exit 1
} else {
    Write-Log "Queue MSMQ '$queuePath' found and can be used"
}

### 3. НАСТРОЙКА НАБЛЮДАТЕЛЯ ЗА ФАЙЛАМИ ###
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = "C:\Prints\output"
$watcher.Filter = "*.pdf"
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true

### 4. ОПРЕДЕЛЕНИЕ ДЕЙСТВИЯ ПРИ СОЗДАНИИ ФАЙЛА ###
$action = {
	$queuePath = $global:queuePath
    $logPath = $global:logPath
	
    $path = $Event.SourceEventArgs.FullPath
    $changeType = $Event.SourceEventArgs.ChangeType
    
    Write-Log "New file found: $path (event: $changeType)" -LogFilePath $logPath
    
    if (Test-Path $path -PathType Leaf) {
		$result = Send-ToQueue -FilePath $path -QueuePath $queuePath -LogFilePath $logPath
        if ($result) {
            Write-Log "SUCCESS: File $path was sent to queue" -LogFilePath $logPath
        } else {
            Write-Log "ERROR: Could not send $path to queue" -LogFilePath $logPath
        }
    } else {
        Write-Log "INFO: $path is not a file, skipping" -LogFilePath $logPath
    }
}

### 5. РЕГИСТРАЦИЯ СОБЫТИЯ И ЗАПУСК МОНИТОРА ###

$eventJob = Register-ObjectEvent -InputObject $watcher -EventName "Created" -Action $action -SourceIdentifier FileCreated
Write-Log "Monitoring for directory '$($watcher.Path)' has been started. Waiting for new PDF..."

### 6. ГЛАВНЫЙ ЦИКЛ И ОБРАБОТКА ЗАВЕРШЕНИЯ ###
try {
    while ($true) {
        Start-Sleep -Seconds 5
#		Write-Log "FileMonitor heartbeat"
    }
} finally {
    Write-Log "FileMonitor receiving stop signal..."
    Unregister-Event -SourceIdentifier FileCreated -ErrorAction SilentlyContinue
    $eventJob | Remove-Job -Force -ErrorAction SilentlyContinue
    $watcher.Dispose()
    Write-Log "=== FileMonitor has been stopped ==="
}