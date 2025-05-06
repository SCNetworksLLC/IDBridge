# Root module file that loads submodules
Import-Module "$PSScriptRoot\core\IDBridge.core.psm1" -Force
Import-Module "$PSScriptRoot\google\IDBridge.google.psm1" -Force
Import-Module "$PSScriptRoot\ad\IDBridge.ad.psm1" -Force
Import-Module "$PSScriptRoot\groups\IDBridge.groups.psm1" -Force
Import-Module "$PSScriptRoot\initialize\IDBridge.initialize.psm1" -Force