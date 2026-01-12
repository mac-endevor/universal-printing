# Universal-printing

There are a lot of Windows-only printers. Even network printers require drivers on a client side (of course if it's not Mopria or AirPrint certified device). And my Ricoh SP200N one of them: network but with client-side rendering and propriatery DDST protocol.

The goal of this project is to enable printing from Linux and FreeBSD on such devices not by reverse engineering of DDST protocol (foo2ddst project did that for some Ricoh models), but via proxy Windows host with a number of utilities. If one have home lab, then runing tiny Windows VM is not a big deal, but provides great compatibility with every Windows compatible pinter.

# Overview

Universal-printing requires following components:
- Windows host (baremetal or virtual)
	- Configured priner with driver for Windows shared via Samba
	- [mfilemon] (https://github.com/lomo74/mfilemon) virtual printer (requires Ghostscript)
	- set of Powershell scripts from this repository
- Linux or FreeBDS client with CUPs installed

![Componetns overview](/images/overview.svg "Overview")

# How to use
- Add printer via Control panel and make sure it works like expected
- Enable logging of files sent for printing via Loal Group Policy:

> Computer Configuration -> Administrative Templates -> Printers -> Allow job name in event logs

- Install Ghostscript
- Install [mfilemon] (https://github.com/lomo74/mfilemon)
- Create working directory for storing intermediate PDFs
- Add new printer with mfilemon port acording to project's 

