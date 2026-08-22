# Get public and private function definition files.

$Private = @()
$Public  = @()

# Casing matches the real folder names - on a case-sensitive filesystem (Linux, e.g.
# Claude Code cloud sessions) a lowercase glob finds nothing and the module loads empty.
$Private = @( Get-ChildItem -Path $PSScriptRoot\Private\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$Public = @( Get-ChildItem -Path $PSScriptRoot\Public\*.ps1 -ErrorAction SilentlyContinue -Recurse )

$FoundErrors = @(
    foreach ($Import in @($Private + $Public)) {
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