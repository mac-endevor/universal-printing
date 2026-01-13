# Universal-printing

There are a lot of Windows-only printers. Even network printers require drivers on a client side (of course if it's not Mopria or AirPrint certified device). And my Ricoh SP200N one of them: network but with client-side rendering and propriatery DDST protocol.

The goal of this project is to enable printing from Linux and FreeBSD on such devices not by reverse engineering of DDST protocol (foo2ddst project did that for some Ricoh models), but via proxy Windows host with a number of utilities. If one have home lab, then runing tiny Windows VM is not a big deal, but provides great compatibility with every Windows compatible pinter.

# Overview

Universal-printing requires following components:
- Linux or FreeBDS client with CUPs installed
- Windows host (baremetal or virtual)
	- Configured priner with driver for Windows shared via Samba
	- [mfilemon](https://github.com/lomo74/mfilemon) virtual printer (requires Ghostscript)
	- set of Powershell scripts from this repository

![Componetns overview](/assets/images/overview.svg "Overview")

# How it works

Below is general scheme:
![Architecture overview](/assets/images/Universal-printing.svg "Architecture and flow")

- **File-Monitor.ps1**:
	- Sets to monitor events "file created" in working directory recursevely for "*.pdf"
	- When the event rises - it just sends full path of created file to MSMQ queue named PrintProcessorQueue
- **File-Processor.ps1**:
	- Reads messages from PrintProcessorQueue queue in transactinal mode
	- Gets path for new file
	- Checks whether it still locked (printing of large file to PDF takes time)
	- When file unlocked it checks printer avaliability from OS perspective and via network port avaliability
	- If printer is ready - sends PDF to printer and commits transaction and creates file marker <filename.pdf>.printed
	- Otherwise sends file path to MSMQ gueue named postponedprinting and creates file marker <filename.pdf>.postponed
- **Postponed-Processor.ps1**:
	- Checks printer avaliability and start processsing only when it's become avaliable
	- Checks whether it still locked (printing of large file to PDF takes time)
	- When file unlocked it checks printer avaliability from OS perspective and via network port avaliability
	- If printer is ready - sends PDF to printer, commits transaction and updates file marker from .postponed to .printed.
- **Clean-Processor.ps1**:
	- gets files and their markers in working directory
	- remves files with .printed marker older then 7 days by-default

# How to use
- Add printer via Control panel and make sure it works like expected
- Enable logging of files sent for printing via Loal Group Policy:

> Computer Configuration -> Administrative Templates -> Printers -> Allow job name in event logs

- Install [Ghostscript](https://ghostscript.com/releases/gsdnld.html)
- Install [mfilemon](https://github.com/lomo74/mfilemon)
- Create working directory for storing intermediate PDFs
- Add new printer with mfilemon port acording to project's how-to
- Share the printer available over network for some local user account
- Download and unpack [archive](https://github.com/mac-endevor/universal-printing/blob/main/assets/universal-printing.zip) from /assets with Administrative, Modules and Scripts folder
- Edit scripts from Scripts folder to match your system:
	- For all from /Scripts folder:
		- Set **$logPath** variable
		- Set **$modulePath** variable
	- /Scripts/File-Monitor.ps1:
		- Set **$watcher.Path** variable - should point to working directory
	- /Scripts/File-Processor.ps1 and /Scripts/Postponed-Processor.ps1:
		- Set **$PrinterName** variable. You can get names of installed printers by running following Powershell command:
		
		> $(Get-CimInstance Win32_Printer).Name

	- /Scripts/Clean-Processor.ps1:
		- Set **$SourceDirectory** variable - should point to working directory
		- Set **$DaysOld** variable - days to keep printed files
	- /Administrative/CreateProcessorQueue.ps1 and /Administrative/CreatePostponedQueue.ps1:
		- Set username acount in **$queue.SetPermissions** which will have full control permissions for queues
- Install MSMQ Feature
- Create two MSMQ queues by running following PowerShell scripts:
	- /Administrative/CreateProcessorQueue.ps1 - queue between File-Monitor and File-Processor
	- /Administrative/CreatePostponedQueue.ps1 - queue between File-Processor and Postponed-Processor
- Make sure that queues are created by running following Powershell command:

 > Get-MsmqQueue -QueueType Private | Format-Table -Property QueueName, MessageCount
 
- Make first run by aunching scripts mannually to check that all set up correctly. To test them just put any PDF file into working directory and check logs
- If everything worked smoothly just add four tasks to Windows Task Scheduler:
	- **File-Monitor**:
		- Geneal tab:
			- Name: FileMonitor
			- Secutiry options:
				- user account: pick up the same user that was granted full control permissions for MSMQ queues
				- check "Run whether user is logged on or not"
		- Triggers tab:
			- Press New button and pick up "At system startup"
		- Action tab:
			- Press New button and configre it:
				- Action: Start a program
				- Programm/script: powershell.exe
				- Add arguments: -ExecutionPolicy Bypass -File C:\Ppath-to\File-Monitor.ps1
	- **File-Processor**:
		- Geneal tab:
			- Name: FileProcessor
			- Secutiry options:
				- user account: pick up the same user that was granted full control permissions for MSMQ queues
				- check "Run whether user is logged on or not"
		- Triggers tab:
			- Press New button and pick up "At system startup"
		- Action tab:
			- Press New button and configre it:
				- Action: Start a program
				- Programm/script: powershell.exe
				- Add arguments: -ExecutionPolicy Bypass -File C:\Ppath-to\File-Processor.ps1				
	- **Postponed-Processor**:
		- Geneal tab:
			- Name: PostponedProcessor
			- Secutiry options:
				- user account: pick up the same user that was granted full control permissions for MSMQ queues
				- check "Run whether user is logged on or not"
		- Triggers tab:
			- Press New button and pick up "At system startup"
		- Action tab:
			- Press New button and configre it:
				- Action: Start a program
				- Programm/script: powershell.exe
				- Add arguments: -ExecutionPolicy Bypass -File C:\Ppath-to\Postponed-Processor.ps1
	- **Clean-Processor**:
		- Geneal tab:
			- Name: CleanProcessor
			- Secutiry options:
				- check "Run whether user is logged on or not"
		- Triggers tab:
			- Press New button and pick up "Dayly" at 00:01 every 1 day
		- Action tab:
			- Press New button and configre it:
				- Action: Start a program
				- Programm/script: powershell.exe
				- Add arguments: -ExecutionPolicy Bypass -File C:\Ppath-to\Clean-Processor.ps
- Add new Samba printer via CUPS:
	- Choose: Windows Printer via SAMBA
	- Address: smb://user:password@windows-host-address/printer-name
	- Printer vendor and drier: Raw
	