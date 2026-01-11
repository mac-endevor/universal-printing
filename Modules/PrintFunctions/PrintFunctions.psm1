# PrintFunctions.psm1
# Модуль общих функций для обработки печати


#region КОНФИГУРАЦИЯ
# Конфигурационные переменные (можно менять перед импортом модуля)
$Script:LogPath = $null
$Script:LogDirectoryPath = $null

function Initialize-Module {
    <#
    .SYNOPSIS
    Инициализирует модуль с указанными путями для логов
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogFilePath,
        
        [Parameter(Mandatory=$false)]
        [string]$LogDirectory = $null
    )
    
    $Script:LogPath = $LogFilePath
    
    if ($LogDirectory) {
        $Script:LogDirectoryPath = $LogDirectory
    } else {
        $Script:LogDirectoryPath = Split-Path -Path $LogFilePath -Parent
    }
    
    Write-Verbose "Module initialized. Log path: $LogFilePath"
}
#endregion

#region ЛОГИРОВАНИЕ

### Функция записи лога в файл
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )
    
    # Используем либо переданный путь, либо глобальный
    $logPathToUse = if ($LogFilePath) { $LogFilePath } else { $Script:LogPath }
    
    if ([string]::IsNullOrEmpty($logPathToUse)) {
        Write-Warning "Log path is not initialized. Call Initialize-Module first or provide LogFilePath parameter."
        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message"
        return
    }
    
    $logline = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message"
    
    try {
        Add-Content -Path $logPathToUse -Value $logline -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file '$logPathToUse': $_"
        Write-Host $logline
    }
}
#endregion


#region ФАЙЛОВЫЕ ОПЕРАЦИИ

### Функция проверки существования и доступности каталога на запись
function Test-DirectoryWritable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )

    if (!(Test-Path $Path -PathType Container)) {
        Write-Log "Log path '$Path' does not exist or is not a directory." -LogFilePath $LogFilePath
        return $false
    }

    $tempFileName = Join-Path $Path ([System.IO.Path]::GetRandomFileName())
    $isWritable = $false

    try {
        [System.IO.File]::OpenWrite($tempFileName).Close() | Out-Null
        Write-Log "Test file $tempFileName created in '$Path' successfully." -LogFilePath $LogFilePath
        $isWritable = $true
    }
    catch {
        Write-Log "Unable to create test file $tempFileName in '$Path'" -LogFilePath $LogFilePath
        $isWritable = $false
    }
    finally {
        if (Test-Path $tempFileName) {
            Remove-Item $tempFileName -Force | Out-Null
            Write-Log "Test file $tempFileName was successfully removed." -LogFilePath $LogFilePath
        }
    }

    return $isWritable
}

### Функция проверки блокировки файла
function Test-IsFileLocked {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True)]
        [string]$Path,

        [Parameter(Mandatory=$false)]
        [int]$MaxRetries = 20,
        
        [Parameter(Mandatory=$false)]
        [int]$SleepTime = 15,
		
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )
    
    $Item = Convert-Path $Path -ErrorAction SilentlyContinue

    if (-not $Item) {
        Write-Log "Error: Path variable not valid - $Path" -LogFilePath $LogFilePath
        return [pscustomobject]@{
            File         = $Path
            IsLocked     = 'InvalidPath'
            Message      = 'Path cannot be resolved'
            Available    = $false
            Attempts     = 0
        }
    }

    $retryCount = 0
    $fileAvailable = $false
    $finalResult = $null
    
    while ($retryCount -lt $MaxRetries -and -not $fileAvailable) {
        $retryCount++
        
        if ([System.IO.File]::Exists($Item)) {
            try {
                $FileStream = [System.IO.File]::Open($Item, 'Open', 'Write')
                $FileStream.Close()
                $FileStream.Dispose()
                $IsLocked = $false
                $Message = 'File is available'
            } 
            catch [System.UnauthorizedAccessException] {
                $IsLocked = 'AccessDenied'
                $Message = 'Access denied to file'
            } 
            catch [System.IO.IOException] {
                $IsLocked = $true
                $Message = 'File is locked by another process'
            } 
            catch {
                $IsLocked = 'UnknownError'
                $Message = $_.Exception.Message
            }
            
            Write-Log "Lock check attempt $retryCount / $MaxRetries : $Item, result: $IsLocked" -LogFilePath $LogFilePath
            
            if ($IsLocked -eq $false) {
                $fileAvailable = $true
                Write-Log "File '$Item' is available after $retryCount attempt(s)" -LogFilePath $LogFilePath
                $finalResult = [pscustomobject]@{
                    File         = $Item
                    IsLocked     = $false
                    Available    = $true
                    Message      = $Message
                    Attempts     = $retryCount
                }
            } 
            else {
                # Если это не блокировка файла (другие ошибки), то прекращаем попытки
                if ($IsLocked -in @('AccessDenied', 'UnknownError')) {
                    Write-Log "Non-retryable error detected: $Message. Stopping retries." -LogFilePath $LogFilePath
                    $finalResult = [pscustomobject]@{
                        File         = $Item
                        IsLocked     = $IsLocked
                        Available    = $false
                        Message      = $Message
                        Attempts     = $retryCount
                    }
                    break
                }
                # Если файл заблокирован и есть еще попытки
                elseif ($retryCount -lt $MaxRetries) {
                    Write-Log "File is locked (attempt $retryCount/$MaxRetries). Waiting $SleepTime seconds..." -LogFilePath $LogFilePath
                    Start-Sleep -Seconds $SleepTime
                }
                else {
                    # Достигнут лимит попыток
                    Write-Log "File still locked after $retryCount attempts" -LogFilePath $LogFilePath
                    $finalResult = [pscustomobject]@{
                        File         = $Item
                        IsLocked     = $true
                        Available    = $false
                        Message      = "File is still locked after $retryCount attempts"
                        Attempts     = $retryCount
                    }
                }
            }
        } 
        else {
            Write-Log "Error: file doesn't exist - $Item" -LogFilePath $LogFilePath
            $finalResult = [pscustomobject]@{
                File         = $Item
                IsLocked     = 'NotFound'
                Available    = $false
                Message      = 'File does not exist'
                Attempts     = $retryCount
            }
            break
        }
    }
    
    # Если по какой-то причине $finalResult не установлен
    if (-not $finalResult) {
        $finalResult = [pscustomobject]@{
            File         = $Item
            IsLocked     = $true
            Available    = $false
            Message      = "File check completed without clear result after $retryCount attempts"
            Attempts     = $retryCount
        }
    }
    
    return $finalResult
}

### Создание файла-маркера
function New-FileMarker {
    <#
    .SYNOPSIS
    Создает пустой файл-маркер рядом с указанным файлом
    
    .DESCRIPTION
    Создает файл-маркер с тем же именем, что и исходный файл, но с добавлением
    расширения, соответствующего статусу (.printed, .postponed и т.д.)
    
    .PARAMETER FilePath
    Полный путь к исходному файлу
    
    .PARAMETER Status
    Статус обработки файла
    
    .PARAMETER LogFilePath
    Путь к файлу лога (необязательно)
    
    .EXAMPLE
    New-FileMarker -FilePath "C:\Files\document.pdf" -Status Printed
    # Создаст файл: C:\Files\document.pdf.printed
    
    .EXAMPLE
    New-FileMarker -FilePath "C:\Files\report.docx" -Status Postponed
    # Создаст файл: C:\Files\report.docx.postponed
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Printed", "Postponed", "Error", "Processing")]
        [string]$Status,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )
    
    try {
        if (-not (Test-Path $FilePath -PathType Leaf)) {
            Write-Log "Source file not found: $FilePath" -LogFilePath $LogFilePath
            return $false
        }
        
        # Создаем путь для маркера (рядом с оригинальным файлом)
        $markerPath = "$FilePath.$($Status.ToLower())"
        
        # Проверяем, не существует ли уже маркер с таким статусом
        if (Test-Path $markerPath) {
            Write-Log "Marker already exists: $markerPath" -LogFilePath $LogFilePath
            return $true
        }
        
        # Создаем пустой файл-маркер
        $null = New-Item -ItemType File -Path $markerPath -Force
        
        Write-Log "Marker created: $markerPath" -LogFilePath $LogFilePath
        return $true
    }
    catch {
        Write-Log "Failed to create marker for $FilePath : $_" -LogFilePath $LogFilePath
        return $false
    }
}

### Изменение файла-маркера
function Update-FileMarker {
    <#
    .SYNOPSIS
    Обновляет статус маркера файла
    
    .DESCRIPTION
    Удаляет старый маркер и создает новый с обновленным статусом
    
    .PARAMETER FilePath
    Путь к файлу
    
    .PARAMETER OldStatus
    Текущий статус (необязательно)
    
    .PARAMETER NewStatus
    Новый статус
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet("Printed", "Postponed", "Error", "Processing")]
        [string]$OldStatus,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Printed", "Postponed", "Error", "Processing")]
        [string]$NewStatus,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )
    
    try {
        # Если указан OldStatus, удаляем только его
        if ($OldStatus) {
            $oldMarkerPath = "$FilePath.$($OldStatus.ToLower())"
            if (Test-Path $oldMarkerPath) {
                Remove-Item -Path $oldMarkerPath -Force
                Write-Log "Old marker removed: $oldMarkerPath" -LogFilePath $LogFilePath
            }
        } else {
            # Иначе удаляем все маркеры файла
            Remove-FileMarker -FilePath $FilePath -LogFilePath $LogFilePath
        }
        
        # Создаем новый маркер
        return New-FileMarker -FilePath $FilePath -Status $NewStatus -LogFilePath $LogFilePath
    }
    catch {
        Write-Log "Failed to update marker for $FilePath : $_" -LogFilePath $LogFilePath
        return $false
    }
}
#endregion


#region ОПЕРАЦИИ С ПРИНТЕРОМ

### Функция проверки доступности принтера
function Get-PrinterStatus {
    <#
    .SYNOPSIS
    Комплексная проверка доступности сетевого принтера через WMI и сетевой порт.
    #>
    
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$PrinterName,
        
        [Parameter(Mandatory = $false)]
        [int]$PortCheckTimeout = 3000,
        
        [Parameter(Mandatory = $false)]
        [int]$ExpectedPort = 9100,
        
        [Parameter(Mandatory = $false)]
        [string]$LogFilePath = $null
    )
    
    # Храним результаты проверок
    $results = @{
        PrinterExists = $false
        OSStatus = $false
        NetworkStatus = $false
        Details = @{}
    }
    
    Write-Log "Starting to check whether printer ready for printing: '$PrinterName'" -LogFilePath $LogFilePath
    
    # ШАГ 1: Проверка существования принтера и его статуса в ОС
    Write-Log "Step 1: Getting printer status from OS..." -LogFilePath $LogFilePath
    try {
        $printer = Get-CimInstance -ClassName Win32_Printer -Filter "Name = '$PrinterName'" -ErrorAction Stop
        
        if ($printer) {
            $results.PrinterExists = $true
            $results.Details.PrinterName = $printer.Name
            $results.Details.PrinterStatus = $printer.PrinterStatus
            $results.Details.WorkOffline = $printer.WorkOffline
            $results.Details.PortName = $printer.PortName
            
            Write-Log "Printer found. Status: $($printer.PrinterStatus), WorkOffline: $($printer.WorkOffline)" -LogFilePath $LogFilePath
            
            # Коды статусов, которые считаем "готовыми"
            $readyStatuses = @(3, 4, 5)
            
            if ($printer.PrinterStatus -in $readyStatuses -and -not $printer.WorkOffline) {
                $results.OSStatus = $true
                Write-Log "OS printer status: READY" -LogFilePath $LogFilePath
            } else {
                Write-Log "OS printer status: UNAVAILABLE (Status: $($printer.PrinterStatus), WorkOffline: $($printer.WorkOffline))" -LogFilePath $LogFilePath
            }
        }
    }
    catch {
        Write-Log "ERROR: Printer '$PrinterName' was not found" -LogFilePath $LogFilePath
        $results.Details.Error = "Printer '$PrinterName' was not found"
        return $false
    }
    
    if (-not $results.OSStatus) {
        Write-Log "Getting status was cancelled: printer unavailable in OS" -LogFilePath $LogFilePath
        return $false
    }
    
    # ШАГ 2: Проверка доступности сетевого порта
    Write-Log "Step 2: Testing printer's port availability..." -LogFilePath $LogFilePath
    
    $ipAddress = $null
    $portName = $printer.PortName
    
    if ($portName -match '\b(?:\d{1,3}\.){3}\d{1,3}\b') {
        $ipAddress = $matches[0]
        Write-Log "Extracting IP-address: $ipAddress" -LogFilePath $LogFilePath
    } else {
        Write-Log "Could not extract IP-address from PortName: '$portName'" -LogFilePath $LogFilePath
        $results.Details.Error = "Could not get printer's IP-address"
        return $false
    }
    
    # Проверяем доступность порта
    try {
        Write-Verbose "Checking port $ExpectedPort on $ipAddress (timeout: ${PortCheckTimeout}ms)"
        
        $portTest = Test-NetConnection -ComputerName $ipAddress -Port $ExpectedPort -WarningAction SilentlyContinue -ErrorAction Stop
        
        if ($portTest.TcpTestSucceeded) {
            $results.NetworkStatus = $true
            $results.Details.IPAddress = $ipAddress
            $results.Details.Port = $ExpectedPort
            $results.Details.PingSucceeded = $portTest.PingSucceeded
            Write-Log "Network port is reachable" -LogFilePath $LogFilePath
        } else {
            Write-Log "Network port is unreachable" -LogFilePath $LogFilePath
            $results.Details.NetworkError = "Network port $ExpectedPort at $ipAddress unreachable"
        }
    }
    catch {
        Write-Log "ERROR during network port test: $_" -LogFilePath $LogFilePath
        $results.Details.NetworkError = $_.Exception.Message
        $results.NetworkStatus = $false
    }
    
    # ШАГ 3: Формируем итоговый результат
    $finalResult = $results.OSStatus -and $results.NetworkStatus
    
    if ($finalResult) {
        Write-Log "Test sum: Printer '$PrinterName' fully operational" -LogFilePath $LogFilePath
    } else {
        Write-Log "Test sum: Printer '$PrinterName' not ready" -LogFilePath $LogFilePath
        if (-not $results.OSStatus) {
            Write-Log "Root cause: OS printer status" -LogFilePath $LogFilePath
        }
        if (-not $results.NetworkStatus) {
            Write-Log "Root cause: Network port is unreachable" -LogFilePath $LogFilePath
        }
    }
    
    # Возвращаем только булево значение для совместимости
    return $finalResult
}

### Функция проверки документа в спулере принтера
function Test-PrintJobSubmitted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [int]$TimeoutSeconds,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )

    $fileName = [System.IO.Path]::GetFileName($FilePath)
	
    $eventFound = $false
    $startTime = Get-Date
	
    Write-Log "Monitoring Event Log for $fileName print task" -LogFilePath $LogFilePath
	
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        try {
            $event = Get-WinEvent -FilterHashtable @{
                LogName = 'Microsoft-Windows-PrintService/Operational'
                ID = 307
                StartTime = (Get-Date).AddSeconds(-5)
            } -MaxEvents 10 -ErrorAction SilentlyContinue | 
            Where-Object { $_.Properties[1].Value -like "*$fileName*" } | 
            Select-Object -First 1

            if ($event) {
                $eventFound = $true
                $user = $event.Properties[2].Value
                $printer = $event.Properties[4].Value
                Write-Log "SUCCESS: Print task was found. File '$fileName' sent to printer '$printer' by user '$user'." -LogFilePath $LogFilePath
                break
            }
        }
        catch {
            Write-Log "ERROR searching event log: $_" -LogFilePath $LogFilePath
        }
        
        Start-Sleep -Seconds 2
    }

    if (-not $eventFound) {
        Write-Log "WARNING: Print task for '$fileName' was not found during $TimeoutSeconds seconds." -LogFilePath $LogFilePath
    }
    
    return $eventFound
}
#endregion


#region ОПЕРАЦИИ С ОЧЕРЕДЯМИ

### Функция отправки сообщения в очередь
function Send-ToQueue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [Parameter(Mandatory=$true)]
        [string]$QueuePath,
        
        [Parameter(Mandatory=$false)]
        [string]$LogFilePath = $null
    )
    
    try {
        $messageQueue = New-Object System.Messaging.MessageQueue $QueuePath
        $message = New-Object System.Messaging.Message
        $message.Body = $FilePath
        $message.Label = "New file for processing"
        $message.Recoverable = $true
        
        $messageQueue.Send($message, [System.Messaging.MessageQueueTransactionType]::Single)
        Write-Log "DEBUG: Successfully sent '$FilePath' to queue '$QueuePath'" -LogFilePath $LogFilePath
        return $true
    }
    catch {
        $errorDetails = $_.Exception.Message
        Write-Log "ERROR in Send-ToQueue for '$FilePath': $errorDetails" -LogFilePath $LogFilePath
        return $false
    }
}
#endregion