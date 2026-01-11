#
#
# References:
#   http://ardalis.com/How-Can-I-View-MSMQ-Messages-and-Queues
#   to see queue, search via "Computer Mamagment"
#
#   simular sample: http://blogs.msdn.com/b/sajay/archive/2010/03/18/powershell-script-to-create-an-msmq.aspx
#

[Reflection.Assembly]::LoadWithPartialName("System.Messaging")
$path = ".\private$\printprocessorqueue"

$queue = $null
$exists = [System.Messaging.MessageQueue]::Exists($path)
if($exists -eq $false)
{
	$queue = [System.Messaging.MessageQueue]::Create($path)
} else
{
	$queue = New-Object System.Messaging.MessageQueue -ArgumentList $path
}
[console]::WriteLine("queue {0} exists (or created)", $path)

#
# Send message
#
$msg = New-Object System.Messaging.Message
$msg.Priority = [System.Messaging.MessagePriority]::Normal
$msg.Label = "Test Message (powershell)"
$msg.Body = "Test Body (powershell)"
$queue.Send($msg, [System.Messaging.MessageQueueTransactionType]::Single)
[console]::WriteLine("sent '{0}' message with body '{1}'", $msg.Label, $msg.Body)

#
# Receive message
#
$timeSpan = New-Object System.TimeSpan(0, 0, 3)
$rmsg = $queue.Receive($timeSpan)
$rmsg.Formatter = New-Object System.Messaging.XmlMessageFormatter -ArgumentList "System.String,mscorlib"

[console]::WriteLine("received '{0}' message with body '{1}'", $rmsg.Label, $rmsg.Body)

$queue.Dispose()