# Get public and private function definition files.

$Private = @()
$Public  = @()
$Custom  = @()
$Plugins = @()

#$Private = @( Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$Public = @( Get-ChildItem -Path $PSScriptRoot\public\*.ps1 -ErrorAction SilentlyContinue -Recurse )

if (Test-Path "C:\IDBridge\Custom") {
    $Custom = @( Get-ChildItem -Path "C:\IDBridge\Custom\*.ps1" -ErrorAction SilentlyContinue -Recurse )
}

if (Test-Path "C:\IDBridge\Plugins") {
    $Plugins = @( Get-ChildItem -Path "C:\IDBridge\Plugins\*.ps1" -ErrorAction SilentlyContinue -Recurse )
}

$FoundErrors = @(
    foreach ($Import in @($Private + $Public + $Custom + $Plugins)) {
        try { . $Import.Fullname}
        catch {
            Write-Error -Message "Failed to import functions from $($Import.Fullname): $_"
            $true
        }
    }
)

if ($FoundErrors.Count -gt 0) {
    $ModuleName = (Get-ChildItem $PSScriptRoot\*.psd1).BaseName
    Write-Warning "Importing module $ModuleName failed. Fix errors before continuing."
    break
}

Export-ModuleMember -Function '*' -Alias '*' -Cmdlet '*'