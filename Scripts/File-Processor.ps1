# File-Processor.ps1 - Обработчик очереди для отправки на печать

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
$logPath = "C:\Prints\PrintScrips\Logs\Processor-log.txt"

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

Write-Log "=== FileProcessor started ==="

### 2. Настройка принтераИ ###
$PrinterName = "RICOH SP 200N DDST"
try {
    $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$PrinterName'" -ErrorAction Stop
    Write-Log "Provided printer '$PrinterName' exists"
}
catch {
    Write-Log "Error: Printer '$PrinterName' doesn't exist. Exiting..."
    exit 1
}

### 3. Настройка очереди приема файлов для обработкиИ ###
Add-Type -AssemblyName System.Messaging
[System.Reflection.Assembly]::LoadWithPartialName("System.Messaging") | Out-Null

$IncomingQueuePath = ".\private$\printprocessorqueue"
if (-not [System.Messaging.MessageQueue]::Exists($IncomingQueuePath)) {
    Write-Log "Queue '$IncomingQueuePath' doesn't exists. Exiting..."
    exit 1
} 
else {
    Write-Log "Queue '$IncomingQueuePath' exists"
}

try {
    $IncomingQueue = New-Object System.Messaging.MessageQueue $IncomingQueuePath
    $IncomingQueue.Formatter = New-Object System.Messaging.XmlMessageFormatter @([String])
    Write-Log "Connected to queue: $IncomingQueuePath"
} 
catch {
    Write-Log "Could not connect to queue $$IncomingQueuePath - $_"
    exit 1
}

### 4. Настройка очереди файлов для отложенной печатиИ ###
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
    Write-Log "Could not connect to queue $PostponedQueuePath. Exiting..."
    exit 1
}

### 5. ОСНОВНОЙ ЦИКЛ ОБРАБОТКИ ОЧЕРЕДИ ###
while ($true) {
    $tx = $null
    try {
        # 1. СОЗДАЕМ И НАЧИНАЕМ ТРАНЗАКЦИЮ
        $tx = New-Object System.Messaging.MessageQueueTransaction
        $tx.Begin()
#        Write-Log "Starting new transaction"
        
        # 2. ПОЛУЧАЕМ СООБЩЕНИЕ В КОНТЕКСТЕ ЭТОЙ ТРАНЗАКЦИИ
        $message = $IncomingQueue.Receive([TimeSpan]::FromSeconds(10), $tx)
        
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
                # 3. ПРОВЕРЯЕМ БЛОКИРОВКУ ФАЙЛА
				$lockResult = Test-IsFileLocked -Path $filePath
				if ($lockResult.Available) {
					Write-Log "File '$filePath' is available, proceeding to print. It takes $($lockResult.Attempts) attempts"
				} else {
					Write-Log "File is locked after $($lockResut.Attempts) attempts with status: $($lockResult.Message). Aborting transaction."
					$tx.Abort()
					continue
				}
                
                # 4. ПРОВЕРЯЕМ ДОСТУПНОСТЬ ПРИНТЕРА
                $printerStatus = Get-PrinterStatus -PrinterName $PrinterName -ExpectedPort 9100 

                # 5. РАЗДЕЛЕНИЕ ЛОГИКИ ПО УСЛОВИЮ
                if ($printerStatus) {
                    # 6. ОТПРАВКА ФАЙЛА НА ПЕЧАТЬ, ЕСЛИ ПРИНТЕР ГОТОВ
                    Write-Log "Attempting to print file: $filePath"
                    try {
                        Start-Process -FilePath $filePath -Verb Print -ErrorAction Stop
                        Write-Log "Print command sent for file: $filePath"
                        
                        # 7. ПРОВЕРЯЕМ ПОДТВЕРЖДЕНИЕ ПЕЧАТИ В ЖУРНАЛЕ СОБЫТИЙ
                        $eventFound = Test-PrintJobSubmitted -FilePath $filePath -TimeoutSeconds 30
                        
                        if ($eventFound) {
                            Write-Log "SUCCESS: Committing transaction or file '$fileName'."
                            $tx.Commit()
							$setMark = New-FileMarker -FilePath $filePath -Status Printed
							if ($setMark) {
								Write-Log "File $filePath marked as Printed"
							}
                        } else {
                            Write-Log "WARNING: Aborting transaction for file '$fileName'."
                            $tx.Abort()
                        }
                    }
                    catch {
                        Write-Log "ERROR: Aborting transaction - failed to send print command for '$filePath': $_"
                        $tx.Abort()
                        continue
                    }
                } else {
                    # 8. ОТПРАВКА ФАЙЛА В ОЧЕРЕДЬ ОТЛОЖЕННОЙ ПЕЧАТИ, ЕСЛИ ПРИНТЕР НЕ ГОТОВ
                    Write-Log "Printer '$PrinterName' is not available. Sending file '$filePath' to postponed printing queue."
                    $sendResult = Send-ToQueue -FilePath $filePath -QueuePath $PostponedQueuePath
                    
                    if ($sendResult) {
                        Write-Log "SUCCESS: Committing transaction or file '$fileName'. Sent to postponed printing queue $PostponedQueuePath"
                        $tx.Commit()
						$setMark = New-FileMarker -FilePath $filePath -Status Postponed
						if ($setMark) {
							Write-Log "File $filePath marked as Postponed"
						}
                    } else {
                        Write-Log "ERROR: Aborting transaction. - could not send '$filePath' to queue '$PostponedQueuePath'"
                        $tx.Abort()
                    }
                    continue
                }
            }
        }
    } 
    catch [System.Messaging.MessageQueueException] {
        # Таймаут - это нормально, просто продолжаем цикл
        if ($_.Exception.MessageQueueErrorCode -eq 'IOTimeout') {
#            Write-Log "Queue timeout - no messages. Continuing..."
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
}

Write-Log "=== FileProcessor stopped ==="