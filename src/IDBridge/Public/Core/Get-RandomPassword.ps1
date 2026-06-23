<#
.SYNOPSIS
Create a random password given a length

.DESCRIPTION
Create a random password given a length. Default length is 10.

.PARAMETER passwordLength
Integer with the password length between 1 & 256

.EXAMPLE
Get-RandomPassword -PasswordLength 8

.NOTES
   Created by: Sam Cattanach 
   Modified: 2025-01-27 9:33 AM CST
#>
function Get-RandomPassword() {
    [cmdletbinding()]
    Param(
        [Parameter(ValueFromPipeline=$false)]
        [ValidateRange(1,256)]
        [int]$PasswordLength = 10
    )
 
    #ASCII Character set for Password
    $CharacterSet = @{
            Lowercase   = (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_}
            Uppercase   = (65..90)  | Get-Random -Count 10 | ForEach-Object {[char]$_}
            Numeric     = (48..57)  | Get-Random -Count 10 | ForEach-Object {[char]$_}
            #SpecialChar = "!@#$%^&*" -split '' | Where-Object {$_ -ne ''} | Get-Random -Count 10
            SpecialChar = (33..47)+(58..64)+(91..96)+(123..126) | Get-Random -Count 10 | ForEach-Object {[char]$_}
    }
 
    #Frame Random Password from given character set
    $StringSet = $CharacterSet.Uppercase + $CharacterSet.Lowercase + $CharacterSet.Numeric + $CharacterSet.SpecialChar
    
    #Join the objects together to get a string
    -join(Get-Random -Count $PasswordLength -InputObject $StringSet)
}