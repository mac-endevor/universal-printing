[System.Reflection.Assembly]::LoadWithPartialName("System.Messaging") | Out-Null
$queuePath = ".\private$\PrintProcessorQueue"
if (-not [System.Messaging.MessageQueue]::Exists($queuePath)) {
    $queue = [System.Messaging.MessageQueue]::Create($queuePath, $true)  # $true = транзакционная
	$queue.UseJournalQueue = $True
    $queue.SetPermissions("adsrv\Administrator",
		[System.Messaging.MessageQueueAccessRights]::FullControl, 
        [System.Messaging.AccessControlEntryType]::Allow)
    Write-Host "Queue created : $queuePath"
} else {
    Write-Host "Queue already exists: $queuePath"
}