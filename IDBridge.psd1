@{
    ModuleVersion = '1.0.0'
    RootModule = 'IDBridge.psm1'
    NestedModules = @(
      'core\IDBridge.core.psm1',
      'google\IDBridge.google.psm1'
      'ad\IDBridge.ad.psm1'
      'groups\IDBridge.groups.psm1'
      'initialize\IDBridge.initialize.psm1'
    )
    Author = 'Sam Cattanach'
    Description = 'IdentityBridge Module'
    PowerShellVersion = '7.5'
  }
  