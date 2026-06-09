#### IDBridge ####
#### Created by Sam Cattanach ####
# Get-Content -Path "C:\IDBridge\Logs\IDBridge.log" -Tail 200 -Wait

#region Import Modules
try {
    Import-Module "C:\GIT\IDBridge\IDBridge.psd1" -Force -ErrorAction Stop
} catch { Throw $_ }
#endregion Import Modules

Invoke-IDBridge