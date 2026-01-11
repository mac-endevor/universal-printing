# Определите точное имя вашего компьютера
$computerName = $env:COMPUTERNAME
Write-Host "server name: $computerName"

# Пробуем несколько вариантов
$testPaths = @(
    ".\private$\printprocessorqueue",
    "localhost\private$\printprocessorqueue",
    "$computerName\private$\printprocessorqueue",
    "FormatName:DIRECT=OS:$computerName\private$\printprocessorqueue"
)

foreach ($path in $testPaths) {
    try {
        $queue = New-Object System.Messaging.MessageQueue $path
        # Пробуем получить свойства очереди (быстрая операция)
        $queue.GetType().Name | Out-Null
        Write-Host "ok: $path" -ForegroundColor Green
    } catch {
        Write-Host "Error ($path): $_" -ForegroundColor Red
    }
}