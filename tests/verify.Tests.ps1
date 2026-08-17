$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$verifyScript = Join-Path $repoRoot 'scripts\verify.ps1'
$enginePath = (Get-Process -Id $PID).Path

function New-TestProfile {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $FolderName,
        [Parameter(Mandatory = $true)][string] $ProfileName
    )

    $profilePath = Join-Path $Root $FolderName
    New-Item -ItemType Directory -Path $profilePath -Force | Out-Null

    $profile = [ordered]@{
        name            = $ProfileName
        deviceType      = 'Loupedeck72'
        applicationName = '@_defaultwin'
        displayName     = 'Pester fixture'
        layout          = [ordered]@{}
    }

    $profile | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $profilePath 'ProfileInfo.json') -Encoding UTF8

    return $profilePath
}

function Invoke-VerifyJson {
    param([Parameter(Mandatory = $true)][string] $ProfilePath)

    $output = @(& $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verifyScript -Path $ProfilePath -Json)
    $exitCode = $LASTEXITCODE
    $json = $output -join [Environment]::NewLine

    return [pscustomobject]@{
        ExitCode = $exitCode
        Json     = $json
        Result   = $json | ConvertFrom-Json
    }
}

function Invoke-VerifyText {
    param([Parameter(Mandatory = $true)][string] $ProfilePath)

    $output = @(& $enginePath -NoLogo -NoProfile -ExecutionPolicy Bypass -File $verifyScript -Path $ProfilePath 2>&1)
    $exitCode = $LASTEXITCODE

    return [pscustomobject]@{
        ExitCode = $exitCode
        Text     = $output -join [Environment]::NewLine
    }
}

function Assert-StableResultShape {
    param([Parameter(Mandatory = $true)] $Result)

    foreach ($propertyName in @(
        'Path', 'Name', 'DisplayName', 'DeviceType', 'Application', 'Slots',
        'Dependencies', 'MissingPlugins', 'Errors', 'Warnings', 'Ok'
    )) {
        ($Result.PSObject.Properties.Name -contains $propertyName) | Should Be $true
    }
}

Describe 'verify.ps1 -Json exit semantics' {
    It 'emits invalid-profile JSON and exits 1' {
        $profileName = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        $profilePath = New-TestProfile -Root $TestDrive -FolderName 'WRONG-FOLDER-NAME' -ProfileName $profileName

        $actual = Invoke-VerifyJson -ProfilePath $profilePath

        $actual.Result.Ok | Should Be $false
        @($actual.Result.Errors).Count | Should BeGreaterThan 0
        $actual.ExitCode | Should Be 1
    }

    It 'emits valid-profile JSON and exits 0' {
        $profileName = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'
        $profilePath = New-TestProfile -Root $TestDrive -FolderName $profileName -ProfileName $profileName

        $actual = Invoke-VerifyJson -ProfilePath $profilePath

        $actual.Result.Ok | Should Be $true
        @($actual.Result.Errors).Count | Should Be 0
        $actual.ExitCode | Should Be 0
    }

    It 'emits invalid-profile JSON and exits 1 for an explicitly specified empty directory' {
        $profilePath = Join-Path $TestDrive 'empty-profile-candidate'
        New-Item -ItemType Directory -Path $profilePath -Force | Out-Null

        $actual = Invoke-VerifyJson -ProfilePath $profilePath

        Assert-StableResultShape -Result $actual.Result
        $actual.Result.Ok | Should Be $false
        (@($actual.Result.Errors) -join [Environment]::NewLine) | Should Match 'ProfileInfo\.json is missing'
        $actual.ExitCode | Should Be 1
    }

    It 'keeps a stable result shape for malformed ProfileInfo.json' {
        $profilePath = Join-Path $TestDrive 'malformed-profile'
        New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profilePath 'ProfileInfo.json') -Value '{ not-json' -Encoding UTF8

        $actual = Invoke-VerifyJson -ProfilePath $profilePath

        Assert-StableResultShape -Result $actual.Result
        $actual.Result.Ok | Should Be $false
        (@($actual.Result.Errors) -join [Environment]::NewLine) | Should Match 'ProfileInfo\.json is not valid JSON'
        $actual.ExitCode | Should Be 1
    }

    It 'formats malformed ProfileInfo.json in text mode without a StrictMode property error' {
        $profilePath = Join-Path $TestDrive 'malformed-profile-text'
        New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $profilePath 'ProfileInfo.json') -Value '{ not-json' -Encoding UTF8

        $actual = Invoke-VerifyText -ProfilePath $profilePath

        $actual.Text | Should Match '\[FAIL\]'
        $actual.Text | Should Match 'ProfileInfo\.json is not valid JSON'
        $actual.Text | Should Not Match 'PropertyNotFound'
        $actual.ExitCode | Should Be 1
    }

    It 'warns about a UNC path without marking an otherwise valid profile invalid' {
        $profileName = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC'
        $profilePath = New-TestProfile -Root $TestDrive -FolderName $profileName -ProfileName $profileName
        $infoPath = Join-Path $profilePath 'ProfileInfo.json'
        $profile = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $profile | Add-Member -NotePropertyName networkPath -NotePropertyValue '\\fixture-server\private-share\file.txt'
        $profile | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $infoPath -Encoding UTF8

        $actual = Invoke-VerifyJson -ProfilePath $profilePath

        $actual.Result.Ok | Should Be $true
        (@($actual.Result.Warnings) -join [Environment]::NewLine) | Should Match 'Absolute path found'
        $actual.ExitCode | Should Be 0
    }
}
