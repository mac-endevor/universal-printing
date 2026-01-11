# PrintFunctions.psd1
@{
    ModuleVersion = '1.0.0'
    GUID = '9b167ac4-bde1-477e-9286-3602830f9cc6'
    Author = 'Pro-crucian'
    CompanyName = 'Home Lab'
    Copyright = '(c) 2026. All rights reserved.'
    Description = 'Common functions for print processing scripts'
    PowerShellVersion = '5.1'
    RootModule = 'PrintFunctions.psm1'
    
    # Экспортируемые функции
    FunctionsToExport = @(
        'Initialize-Module',
        'Write-Log',
        'Test-DirectoryWritable',
        'Test-IsFileLocked',
		'New-FileMarker',
		'Update-FileMarker',
        'Get-PrinterStatus',
        'Test-PrintJobSubmitted',
        'Send-ToQueue'
    )
    
    # Переменные для экспорта (опционально)
    VariablesToExport = @()
    
    # Дополнительные метаданные
    PrivateData = @{
        PSData = @{
            Tags = @('Print', 'Logging', 'MSMQ', 'Printer')
            LicenseUri = ''
            ProjectUri = ''
            IconUri = ''
            ReleaseNotes = 'Initial release with core print processing functions'
        }
    }
}