$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$anonymizeScript = Join-Path $repoRoot 'scripts\anonymize.ps1'
$stagingCollisionFixture = Join-Path $PSScriptRoot 'fixtures\invoke-anonymize-with-staging-collision.ps1'
$enginePath = (Get-Process -Id $PID).Path

function New-TestProfile {
    param(
        [Parameter(Mandatory = $true)][string] $ProfilePath,
        [object[]] $ProfileActions = @(),
        [string] $PressAction = ''
    )

    New-Item -ItemType Directory -Path $ProfilePath -Force | Out-Null

    $profile = [ordered]@{
        name            = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        packageName     = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
        displayName     = 'Anonymize Pester fixture'
        deviceType      = 'Loupedeck72'
        applicationName = '@_defaultwin'
        profileActions  = @($ProfileActions)
        macroCommands   = @()
        profileCommands = @()
        macroAdjustments = @()
        profileAdjustments = @()
        layout          = [ordered]@{
            page = [ordered]@{
                pressAction = $PressAction
            }
        }
    }

    $profile | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath (Join-Path $ProfilePath 'ProfileInfo.json') -Encoding UTF8

    return $ProfilePath
}

function Invoke-Anonymize {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination,
        [switch] $Force
    )

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $anonymizeScript,
        '-Path', $Source,
        '-Destination', $Destination
    )
    if ($Force) { $arguments += '-Force' }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $enginePath @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output   = (($output | ForEach-Object { [string] $_ }) -join [Environment]::NewLine)
    }
}

function Invoke-AnonymizeWithStagingCollision {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $stagingCollisionFixture,
        '-AnonymizeScript', $anonymizeScript,
        '-Source', $Source,
        '-Destination', $Destination
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $enginePath @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = (($output | ForEach-Object { [string] $_ }) -join [Environment]::NewLine)
    }
}

Describe 'anonymize.ps1 output safety' {
    It 'replaces a forced destination instead of preserving an unknown stale file' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'force-source')
        $destination = Join-Path $TestDrive 'force-output'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $stale = Join-Path $destination 'stale-unknown.txt'
        Set-Content -LiteralPath $stale -Value 'must not survive' -Encoding UTF8

        $actual = Invoke-Anonymize -Source $source -Destination $destination -Force

        $actual.ExitCode | Should Be 0
        (Test-Path -LiteralPath $stale) | Should Be $false
        (Test-Path -LiteralPath (Join-Path $destination 'ProfileInfo.json') -PathType Leaf) | Should Be $true
        @(Get-ChildItem -LiteralPath $TestDrive -Force -Directory | Where-Object { $_.Name -like '*.anonymize-*' }).Count | Should Be 0
    }

    It 'detects and removes a UNC path embedded in a profile action' {
        $uncAction = [pscustomobject][ordered]@{
            name               = 'UNC_ACTION'
            displayName        = 'UNC fixture action'
            templateActionName = '$@Generic___@FixtureAction'
            targetPath         = '\\fixture-server\private-share\secret.txt'
        }
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'unc-action-source') -ProfileActions @($uncAction) -PressAction 'UNC_ACTION'
        $destination = Join-Path $TestDrive 'unc-action-output'

        $actual = Invoke-Anonymize -Source $source -Destination $destination
        $profileText = Get-Content -LiteralPath (Join-Path $destination 'ProfileInfo.json') -Raw -Encoding UTF8
        $profile = $profileText | ConvertFrom-Json

        $actual.ExitCode | Should Be 0
        @($profile.profileActions).Count | Should Be 0
        $profile.layout.page.pressAction | Should Be ''
        $profileText | Should Not Match '(?i)fixture-server|private-share'
    }

    It 'rejects a drive-letter leak copied into metadata' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'metadata-source')
        $metadata = Join-Path $source 'metadata'
        New-Item -ItemType Directory -Path $metadata -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $metadata 'AdvancedInfo.json') -Value '{"path":"C:\\Users\\fixture-user\\secret.txt"}' -Encoding UTF8
        $destination = Join-Path $TestDrive 'metadata-output'

        $actual = Invoke-Anonymize -Source $source -Destination $destination

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match 'PATHS STILL PRESENT'
        (Test-Path -LiteralPath $destination) | Should Be $false
    }

    It 'rejects a UNC leak copied into an asset' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'asset-source')
        $assets = Join-Path $source 'assets'
        New-Item -ItemType Directory -Path $assets -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $assets 'note.txt') -Value 'open \\fixture-server\private-share\secret.txt' -Encoding UTF8
        $destination = Join-Path $TestDrive 'asset-output'

        $actual = Invoke-Anonymize -Source $source -Destination $destination

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match 'PATHS STILL PRESENT'
        (Test-Path -LiteralPath $destination) | Should Be $false
    }

    It 'rejects a destination nested under the source before writing it' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'outer-source')
        $destination = Join-Path $source 'published'

        $actual = Invoke-Anonymize -Source $source -Destination $destination

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match '(?i)overlap'
        (Test-Path -LiteralPath $destination) | Should Be $false
    }

    It 'rejects a destination reached through a junction before writing under the source' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'junction-source')
        $sourceJunction = Join-Path $TestDrive 'source-junction'
        New-Item -ItemType Junction -Path $sourceJunction -Target $source | Out-Null
        $destination = Join-Path $sourceJunction 'published'

        $actual = Invoke-Anonymize -Source $source -Destination $destination

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match '(?i)reparse point'
        (Test-Path -LiteralPath (Join-Path $source 'published')) | Should Be $false
    }

    It 'rejects a destination that contains the source without modifying either tree' {
        $destination = Join-Path $TestDrive 'outer-destination'
        $source = New-TestProfile -ProfilePath (Join-Path $destination 'nested-source')
        $sourceMarker = Join-Path $source 'source-marker.txt'
        Set-Content -LiteralPath $sourceMarker -Value 'source stays intact' -Encoding UTF8

        $actual = Invoke-Anonymize -Source $source -Destination $destination -Force

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match '(?i)overlap'
        (Test-Path -LiteralPath $sourceMarker -PathType Leaf) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $destination 'ProfileInfo.json')) | Should Be $false
    }

    It 'leaves an existing destination untouched when staged content fails leak validation' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'failed-stage-source')
        $metadata = Join-Path $source 'metadata'
        New-Item -ItemType Directory -Path $metadata -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $metadata 'AdvancedInfo.json') -Value '{"path":"D:\\Private\\secret.txt"}' -Encoding UTF8

        $destination = Join-Path $TestDrive 'existing-output'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $sentinel = Join-Path $destination 'published-sentinel.txt'
        Set-Content -LiteralPath $sentinel -Value 'known-good output' -Encoding UTF8

        $actual = Invoke-Anonymize -Source $source -Destination $destination -Force

        $actual.ExitCode | Should Be 1
        (Get-Content -LiteralPath $sentinel -Raw -Encoding UTF8).Trim() | Should Be 'known-good output'
        @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count | Should Be 1
        @(Get-ChildItem -LiteralPath $TestDrive -Force -Directory | Where-Object { $_.Name -like '*.anonymize-*' }).Count | Should Be 0
    }

    It 'rejects a likely secret copied into nested metadata and preserves the prior output' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'secret-source')
        $metadata = Join-Path $source 'metadata'
        New-Item -ItemType Directory -Path $metadata -Force | Out-Null
        $fakeSecret = 'fixtureToken1234567890ABCDEF'
        Set-Content -LiteralPath (Join-Path $metadata 'credentials.yaml') `
            -Value "api_key: $fakeSecret" -Encoding UTF8

        $destination = Join-Path $TestDrive 'secret-output'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        $sentinel = Join-Path $destination 'published-sentinel.txt'
        Set-Content -LiteralPath $sentinel -Value 'known-good output' -Encoding UTF8

        $actual = Invoke-Anonymize -Source $source -Destination $destination -Force

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match '(?i)secret|privacy'
        $actual.Output | Should Not Match ([regex]::Escape($fakeSecret))
        (Get-Content -LiteralPath $sentinel -Raw -Encoding UTF8).Trim() | Should Be 'known-good output'
        @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count | Should Be 1
    }

    It 'refuses to replace an output tree containing a reparse point' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'reparse-output-source')
        $destination = Join-Path $TestDrive 'reparse-output'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        $external = Join-Path $TestDrive 'external-target'
        New-Item -ItemType Directory -Path $external -Force | Out-Null
        $externalMarker = Join-Path $external 'keep.txt'
        Set-Content -LiteralPath $externalMarker -Value 'keep' -Encoding UTF8
        New-Item -ItemType Junction -Path (Join-Path $destination 'linked-data') -Target $external | Out-Null

        $actual = Invoke-Anonymize -Source $source -Destination $destination -Force

        $actual.ExitCode | Should Be 1
        $actual.Output | Should Match '(?i)reparse point'
        (Get-Content -LiteralPath $externalMarker -Raw -Encoding UTF8).Trim() | Should Be 'keep'
        (Test-Path -LiteralPath (Join-Path $destination 'linked-data')) | Should Be $true
    }

    It 'does not clean a staging path whose creation failed before ownership was acquired' {
        $source = New-TestProfile -ProfilePath (Join-Path $TestDrive 'collision-source')
        $destination = Join-Path $TestDrive 'collision-output'

        $actual = Invoke-AnonymizeWithStagingCollision -Source $source -Destination $destination

        $actual.ExitCode | Should Be 1
        $staging = @(Get-ChildItem -LiteralPath $TestDrive -Directory -Force |
            Where-Object { $_.Name -like '.collision-output.anonymize-staging-*' })
        $staging.Count | Should Be 1
        (Test-Path -LiteralPath (Join-Path $staging[0].FullName 'keep.txt')) | Should Be $true
        (Test-Path -LiteralPath $destination) | Should Be $false
    }

    It 'anonymizes the repository starter without false-positive asset leaks' {
        $source = Join-Path $repoRoot 'profiles\loupedeck72\general\starter\BA78990AAAC341CEA0FBC11FEEBFF88D'
        $destination = Join-Path $TestDrive 'repository-starter-output'

        $actual = Invoke-Anonymize -Source $source -Destination $destination

        $actual.ExitCode | Should Be 0
        (Test-Path -LiteralPath (Join-Path $destination 'ProfileInfo.json') -PathType Leaf) | Should Be $true
        @(Get-ChildItem -LiteralPath $destination -Recurse -File).Count | Should BeGreaterThan 1
    }
}
