<#
.SYNOPSIS
Unit tests for the -Preview row flattener (ConvertTo-IDBridgePreviewRow).

.DESCRIPTION
Feeds hand-built change-list shapes (the same shapes the Get-*To* planners return) and checks
the flat row output — including that passwords stay out of the table unless -ShowPasswords,
and that a SecureString can never leak through the Changes column.
#>

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' '..' 'TestHelper.psm1') -Force
    Import-IDBridgeForTest
}

Describe 'ConvertTo-IDBridgePreviewRow' {
    It 'returns no rows when no change lists are supplied' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            $rows = ConvertTo-IDBridgePreviewRow -SourceData $records

            @($rows).Count | Should -Be 0
        }
    }

    It 'emits AD rows in apply order: CreateOU, Deactivate, Update, Rename, Move, Create, GroupAdd, GroupRemove' {
        $records = @(New-TestSourceRecord)
        $toCreate = @([PSCustomObject]@{ PersonID = '10001'; Splat = @{ DisplayName = 'Test User'; SamAccountName = 'tuser'; Office = 'Main'; Path = 'OU=Staff,DC=example,DC=org'; AccountPassword = 'x' } })
        $toUpdate = [PSCustomObject]@{
            UpdateList = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; Splat = @{ Identity = 'tuser'; Division = 'ts'; Title = 'Principal' } })
            RenameList = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; ADUserID = 'tuser'; NewName = 'Test Married 10001' })
            MoveList   = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; ADUserID = 'tuser'; NewOrgUnit = 'OU=Students,DC=example,DC=org' })
        }
        $groups = [PSCustomObject]@{
            Add    = @([PSCustomObject]@{ PersonID = '10001'; ADCurrentUserID = 'tuser'; Groups = @('Staff', 'Math Dept') })
            Remove = @([PSCustomObject]@{ PersonID = '10001'; ADCurrentUserID = 'tuser'; Groups = @('Old Team') })
        }

        InModuleScope IDBridge -Parameters @{ records = $records; toCreate = $toCreate; toUpdate = $toUpdate; groups = $groups } {
            $rows = ConvertTo-IDBridgePreviewRow -SourceData $records `
                -ADUsersToCreate $toCreate -ADUsersToUpdate $toUpdate -ADUsersToDeactivate $records `
                -ADUserGroupsToUpdate $groups -ADOrgUnitsToCreate @('OU=New,DC=example,DC=org')

            # One row per change; group rows are one per user+group pair.
            $rows.Action | Should -Be @('CreateOU', 'Deactivate', 'Update', 'Rename', 'Move', 'Create', 'GroupAdd', 'GroupAdd', 'GroupRemove')
            $rows | ForEach-Object { $_.Directory | Should -Be 'AD' }

            # Spot-check resolution: update rows pull Name/Account/Building from the source record.
            $update = $rows | Where-Object Action -EQ 'Update'
            $update.Name | Should -Be 'Test User'
            $update.Account | Should -Be 'tuser'
            $update.Changes | Should -Be 'Title=Principal'   # Identity/Division are bookkeeping, not changes

            ($rows | Where-Object Action -EQ 'Deactivate').OrgUnit | Should -Be 'OU=Trash,DC=example,DC=org'
            ($rows | Where-Object Action -EQ 'Rename').Changes | Should -Be "CN 'Test User 10001' -> 'Test Married 10001'"
            ($rows | Where-Object Action -EQ 'GroupAdd').Changes | Should -Be @('Staff', 'Math Dept')
        }
    }

    It 'leaves the Password column empty unless -ShowPasswords is set' {
        $records = @(New-TestSourceRecord)
        $toCreate = @([PSCustomObject]@{ PersonID = '10001'; Splat = @{ DisplayName = 'Test User'; SamAccountName = 'tuser'; Office = 'Main'; Path = 'OU=Staff,DC=example,DC=org'; AccountPassword = (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) } })

        InModuleScope IDBridge -Parameters @{ records = $records; toCreate = $toCreate } {
            $hidden = ConvertTo-IDBridgePreviewRow -SourceData $records -ADUsersToCreate $toCreate
            $shown = ConvertTo-IDBridgePreviewRow -SourceData $records -ADUsersToCreate $toCreate -ShowPasswords

            $hidden[0].Password | Should -Be ''
            $shown[0].Password | Should -Be 'hunter2'
        }
    }

    It 'renders a SecureString in an update splat as (secure), never the value' {
        $records = @(New-TestSourceRecord)
        $toUpdate = [PSCustomObject]@{
            UpdateList = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; Splat = @{ Identity = 'tuser'; Division = 'ts'; AccountPassword = (ConvertTo-SecureString 'hunter2' -AsPlainText -Force) } })
            RenameList = @(); MoveList = @()
        }

        InModuleScope IDBridge -Parameters @{ records = $records; toUpdate = $toUpdate } {
            $rows = ConvertTo-IDBridgePreviewRow -SourceData $records -ADUsersToUpdate $toUpdate -ShowPasswords

            $rows[0].Changes | Should -Be 'AccountPassword=(secure)'
        }
    }

    It 'renders hashtable splat values (Replace) as compact JSON' {
        $records = @(New-TestSourceRecord)
        $toUpdate = [PSCustomObject]@{
            UpdateList = @([PSCustomObject]@{ CN = 'Test User 10001'; PersonID = '10001'; Splat = @{ Identity = 'tuser'; Division = 'ts'; Replace = @{ EmployeeType = 'STUDENT' } } })
            RenameList = @(); MoveList = @()
        }

        InModuleScope IDBridge -Parameters @{ records = $records; toUpdate = $toUpdate } {
            $rows = ConvertTo-IDBridgePreviewRow -SourceData $records -ADUsersToUpdate $toUpdate

            $rows[0].Changes | Should -Be 'Replace={"EmployeeType":"STUDENT"}'
        }
    }

    It 'emits Google rows, including the license impact on deactivations' {
        $licenses = @([PSCustomObject]@{ skuName = 'Education Plus'; skuId = 'sku-1' })
        $records = @(New-TestSourceRecord -IDBActive $false -GoogleCurrentLicenses $licenses)
        $gCreate = @([PSCustomObject]@{ UPN = 'new@example.org'; PersonID = '10002'; Splat = @{ PrimaryEmail = 'new@example.org'; FirstName = 'New'; LastName = 'Hire'; Building = 'Main'; OrgUnitPath = '/Staff'; Password = 'x' } })

        InModuleScope IDBridge -Parameters @{ records = $records; gCreate = $gCreate } {
            $rows = ConvertTo-IDBridgePreviewRow -SourceData $records `
                -GoogleOrgUnitsToCreate @('/New') -GoogleUsersToDeactivate $records -GoogleUsersToCreate $gCreate

            $rows.Action | Should -Be @('CreateOU', 'Deactivate', 'Create')
            $rows | ForEach-Object { $_.Directory | Should -Be 'Google' }

            $deactivate = $rows | Where-Object Action -EQ 'Deactivate'
            $deactivate.OrgUnit | Should -Be '/Trash'
            $deactivate.Changes | Should -Be 'Archive account; move to trash OU; removes licenses: Education Plus'

            $create = $rows | Where-Object Action -EQ 'Create'
            $create.Name | Should -Be 'New Hire'
            $create.Account | Should -Be 'new@example.org'
        }
    }

    It 'emits AD rows before Google rows' {
        $records = @(New-TestSourceRecord)

        InModuleScope IDBridge -Parameters @{ records = $records } {
            $rows = ConvertTo-IDBridgePreviewRow -SourceData $records `
                -ADOrgUnitsToCreate @('OU=New,DC=example,DC=org') -GoogleOrgUnitsToCreate @('/New')

            $rows.Directory | Should -Be @('AD', 'Google')
        }
    }
}
