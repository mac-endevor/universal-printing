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
$queue = New-Object System.Messaging.MessageQueue -ArgumentList $path

#
# Receive message
#
$timeSpan = New-Object System.TimeSpan(0, 0, 3)
$rmsg = $queue.Receive($timeSpan)
$rmsg.Formatter = New-Object System.Messaging.XmlMessageFormatter -ArgumentList "System.String,mscorlib"

[console]::WriteLine("received '{0}' message with body '{1}'", $rmsg.Label, $rmsg.Body)

$queue.Dispose()