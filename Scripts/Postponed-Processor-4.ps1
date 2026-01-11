# Postponed-Processor.ps1 - Обработчик очереди для отложенной печати

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
$global:logPath = "C:\Prints\PrintScrips\Logs\PostponedProcessor-log.txt"

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

Write-Log "=== PostponedProcessor started ==="

### 2. Настройка принтера  ###
$PrinterName = "RICOH SP 200N DDST"
try {
    $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$PrinterName'" -ErrorAction Stop
    Write-Log "Provided printer '$PrinterName' exists"
}
catch {
    Write-Log "Error: Printer '$PrinterName' doesn't exist. Exiting..."
    exit 1
}

### 3. Настройка очереди приема файлов для обработки ###
Add-Type -AssemblyName System.Messaging
[System.Reflection.Assembly]::LoadWithPartialName("System.Messaging") | Out-Null

$PostponedQueuePath = ".\private$\postponedprinting"
if (-not [System.Messaging.MessageQueue]::Exists($PostponedQueuePath)) {
    Write-Log "Queue '$PostponedQueuePath' doesn't exists. Exiting..."
    exit 1
} 
else {
    Write-Log "Queue '$PostponedQueuePath' exists"
}

try {
    $PostponedQueue = New-Object System.Messaging.MessageQueue $PostponedQueuePath
    $PostponedQueue.Formatter = New-Object System.Messaging.XmlMessageFormatter @([String])
    Write-Log "Connected to queue: $PostponedQueuePath"
} 
catch {
    Write-Log "Could not connect to queue $PostponedQueuePath - $_"
    exit 1
}

### 4. ОСНОВНОЙ ЦИКЛ ОБРАБОТКИ ОЧЕРЕДИ ###
while ($true) {
    $tx = $null
    
    try {
        # 1. ПРОВЕРЯЕМ ДОСТУПНОСТЬ ПРИНТЕРА
        $printerStatus = Get-PrinterStatus -PrinterName $PrinterName -ExpectedPort 9100 

        # 2. РАЗДЕЛЕНИЕ ЛОГИКИ ПО УСЛОВИЮ
        if ($printerStatus) {
            Write-Log "Printer '$PrinterName' is available. Processing queue..."
            
            # 3. СОЗДАЕМ И НАЧИНАЕМ ТРАНЗАКЦИЮ
            $tx = New-Object System.Messaging.MessageQueueTransaction
            $tx.Begin()
            Write-Log "Starting new transaction"
            
            # 4. ПОЛУЧАЕМ СООБЩЕНИЕ В КОНТЕКСТЕ ЭТОЙ ТРАНЗАКЦИИ
            # ИСПРАВЛЕНО: используем $PostponedQueue, а не $PostponedQueuePath
            $message = $PostponedQueue.Receive([TimeSpan]::FromSeconds(10), $tx)
            
            if ($message) {
                $filePath = $message.Body
                $fileName = [System.IO.Path]::GetFileName($filePath)
                Write-Log "Received new file for processing: $filePath"

                if (-not (Test-Path $filePath -PathType Leaf)) {
                    Write-Log "ERROR: Received file '$filePath' doesn't exist. Removing message from queue"
                    $tx.Commit()
                    Write-Log "File '$filePath' was removed from queue. Committing transaction."
                    continue
                }
                else {
                    # 5. ПРОВЕРЯЕМ БЛОКИРОВКУ ФАЙЛА
					$lockResult = Test-IsFileLocked -Path $filePath
					if ($lockResult.Available) {
						Write-Log "File '$filePath' is available, proceeding to print. It takes $($lockResult.Attempts) attempts"
					} else {
						Write-Log "File is locked after $($lockResut.Attempts) attempts with status: $($lockResult.Message). Aborting transaction."
						$tx.Abort()
						continue
					}

                    # 6. ОТПРАВКА ФАЙЛА НА ПЕЧАТЬ
                    Write-Log "Attempting to print file: $filePath"
                    try {
                        Start-Process -FilePath $filePath -Verb Print -ErrorAction Stop
                        Write-Log "Print command sent for file: $filePath"
                        
                        # 7. ПРОВЕРЯЕМ ПОДТВЕРЖДЕНИЕ ПЕЧАТИ В ЖУРНАЛЕ СОБЫТИЙ
                        $eventFound = Test-PrintJobSubmitted -FilePath $filePath -TimeoutSeconds 30
                        
                        if ($eventFound) {
                            Write-Log "SUCCESS: Committing transaction or file '$fileName'."
                            $tx.Commit()
							$updateMark	= Update-FileMarker -FilePath $filePath -OldStatus Postponed -NewStatus Printed
							if ($updateMark) {
								Write-Log "File $filePath marked as Printed"
							}
                        } else {
                            Write-Log "WARNING: Aborting transaction for file '$fileName'."
                            $tx.Abort()
                        }
                    }
                    catch {
                        Write-Log "ERROR: Failed to send print command for '$filePath': $_"
                        $tx.Abort()
                        continue
                    }
                }
            } else {
                Write-Log "No messages in queue. Transaction completed."
                if ($tx -and $tx.Status -eq 'Pending') {
                    $tx.Abort()
                }
            }
        } 
        else {
            # ПРИНТЕР НЕДОСТУПЕН - ЖДЕМ 15 СЕКУНД
      #      Write-Log "Printer '$PrinterName' is offline. Sleeping for 60 seconds..."
            Start-Sleep -Seconds 60
            continue
        }
    } 
    catch [System.Messaging.MessageQueueException] {
        # Таймаут - это нормально, просто продолжаем цикл
        if ($_.Exception.MessageQueueErrorCode -eq 'IOTimeout') {
      #      Write-Log "Queue timeout - no messages. Continuing..."
            continue
        }
        Write-Log "MSMQ Error: $_"
        if ($tx -and $tx.Status -eq 'Pending') { 
            $tx.Abort() 
        }
        Start-Sleep -Seconds 5
    } 
    catch {
        Write-Log "Unknown error: $_"
        if ($tx -and $tx.Status -eq 'Pending') { 
            $tx.Abort() 
        }
        Start-Sleep -Seconds 5
    } 
    finally {
        if ($tx) { 
            $tx.Dispose() 
        }
    }
    
    # Небольшая пауза между итерациями цикла, даже если принтер доступен
    Start-Sleep -Seconds 1
}

Write-Log "=== PostponedProcessor stopped ==="