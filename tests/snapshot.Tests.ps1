$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:SnapshotScript = Join-Path $script:RepoRoot 'scripts\snapshot.ps1'
$script:FaultFixture = Join-Path $PSScriptRoot 'fixtures\invoke-snapshot-with-copy-fault.ps1'

if ($PSVersionTable.PSVersion.Major -le 5) {
    $script:ShellPath = Join-Path $PSHOME 'powershell.exe'
} else {
    $script:ShellPath = Join-Path $PSHOME 'pwsh.exe'
}

function Invoke-SnapshotProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Destination,

        [string[]] $AdditionalArguments = @()
    )

    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $script:SnapshotScript
        '-Destination'
        $Destination
    ) + $AdditionalArguments

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:ShellPath @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

function Invoke-SnapshotWithCopyFault {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Destination,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Corrupt', 'Swap', 'GuardProbe', 'StagingCollision')]
        [string] $Mode,

        [string] $MarkerPath
    )

    $arguments = @(
        '-NoLogo'
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $script:FaultFixture
        '-SnapshotScript'
        $script:SnapshotScript
        '-Destination'
        $Destination
        '-Mode'
        $Mode
    )
    if ($MarkerPath) { $arguments += @('-MarkerPath', $MarkerPath) }

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:ShellPath @arguments 2>&1 | ForEach-Object { $_.ToString() })
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

function Write-TestManifest {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    [pscustomobject]@{
        takenAt = '2026-01-01T00:00:00.0000000Z'
        source = 'fixture'
        profileCount = 0
        fileCount = 0
        files = @()
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Directory 'manifest.json') -Encoding UTF8
}

function Test-SnapshotManifestMatch {
    param(
        [Parameter(Mandatory = $true)] [object[]] $Expected,
        [Parameter(Mandatory = $true)] [object[]] $Actual
    )

    $source = Get-Content -LiteralPath $script:SnapshotScript -Raw
    $start = $source.IndexOf('function Test-ManifestMatch')
    $end = $source.IndexOf('function Get-Snapshot', $start)
    if ($start -lt 0 -or $end -le $start) { throw 'Could not isolate Test-ManifestMatch from snapshot.ps1.' }

    Invoke-Expression $source.Substring($start, $end - $start)
    return Test-ManifestMatch -Expected $Expected -Actual $Actual
}

Describe 'snapshot.ps1 publication safety' {
    BeforeEach {
        $script:OriginalLocalAppData = $env:LOCALAPPDATA
        $script:CaseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:LocalAppData = Join-Path $script:CaseRoot 'localappdata'
        $script:Source = Join-Path $script:LocalAppData 'Logi\LogiPluginService\Applications'
        $script:Destination = Join-Path $script:CaseRoot 'snapshots'

        New-Item -ItemType Directory -Path $script:Source -Force | Out-Null
        $env:LOCALAPPDATA = $script:LocalAppData
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }

    It 'does not publish a final directory or manifest when verification fails' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII

        $unrelatedPartial = Join-Path $script:Destination 'unrelated.partial'
        New-Item -ItemType Directory -Path $unrelatedPartial -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $unrelatedPartial 'keep.txt') -Value 'keep' -Encoding ASCII

        $result = Invoke-SnapshotWithCopyFault -Destination $script:Destination -Mode Corrupt

        $result.ExitCode | Should Be 1
        @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -notlike '*.partial' }).Count | Should Be 0
        @(Get-ChildItem -LiteralPath $script:Destination -Recurse -Filter 'manifest.json' -File -Force).Count | Should Be 0
        (Test-Path -LiteralPath (Join-Path $unrelatedPartial 'keep.txt')) | Should Be $true
        @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -like '*.partial' }).Count | Should Be 1
    }

    It 'ignores a manifest-bearing partial directory when choosing the latest snapshot' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII

        $published = Join-Path $script:Destination '20260101-000000'
        $failedPartial = Join-Path $script:Destination '99999999-999999.deadbeef.partial'
        Write-TestManifest -Directory $published
        Write-TestManifest -Directory $failedPartial

        $result = Invoke-SnapshotProcess -Destination $script:Destination -AdditionalArguments @('-Compare')

        $result.ExitCode | Should Be 0
        $result.Output | Should Match 'Drift since 20260101-000000'
        $result.Output | Should Not Match '99999999-999999\.deadbeef\.partial'
    }

    It 'rejects a copy whose hashes match only as a multiset but belong to different paths' {
        Set-Content -LiteralPath (Join-Path $script:Source 'alpha.txt') -Value 'alpha' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $script:Source 'beta.txt') -Value 'beta' -Encoding ASCII

        $result = Invoke-SnapshotWithCopyFault -Destination $script:Destination -Mode Swap

        $result.ExitCode | Should Be 1
        @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -notlike '*.partial' }).Count | Should Be 0
    }

    It 'rejects a destination nested under the live source before copy starts' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII
        $nestedDestination = Join-Path $script:Source 'snapshots'
        $copyMarker = Join-Path $script:CaseRoot 'copy-called.txt'

        $result = Invoke-SnapshotWithCopyFault `
            -Destination $nestedDestination `
            -Mode GuardProbe `
            -MarkerPath $copyMarker

        $result.ExitCode | Should Be 1
        (Test-Path -LiteralPath $copyMarker) | Should Be $false
        (Test-Path -LiteralPath $nestedDestination) | Should Be $false
        $result.Output | Should Match 'Destination must not be the source directory or a descendant'
    }

    It 'rejects a destination reached through a junction before writing under the source' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII
        $sourceJunction = Join-Path $script:CaseRoot 'source-junction'
        New-Item -ItemType Junction -Path $sourceJunction -Target $script:Source | Out-Null
        $junctionDestination = Join-Path $sourceJunction 'snapshots'

        $result = Invoke-SnapshotProcess -Destination $junctionDestination

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'reparse point'
        (Test-Path -LiteralPath (Join-Path $script:Source 'snapshots')) | Should Be $false
    }

    It 'rejects a reparse point inside the source tree before copying it' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII
        $external = Join-Path $script:CaseRoot 'external-data'
        New-Item -ItemType Directory -Path $external -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $external 'private.txt') -Value 'private' -Encoding ASCII
        New-Item -ItemType Junction -Path (Join-Path $script:Source 'linked-data') -Target $external | Out-Null

        $result = Invoke-SnapshotProcess -Destination $script:Destination

        $result.ExitCode | Should Be 1
        $result.Output | Should Match 'Source tree contains.+reparse point'
        (Test-Path -LiteralPath $script:Destination) | Should Be $false
    }

    It 'does not clean a staging path whose creation failed before ownership was acquired' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII

        $result = Invoke-SnapshotWithCopyFault -Destination $script:Destination -Mode StagingCollision

        $result.ExitCode | Should Be 1
        $partials = @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -like '*.partial' })
        $partials.Count | Should Be 1
        (Test-Path -LiteralPath (Join-Path $partials[0].FullName 'keep.txt')) | Should Be $true
        @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -notlike '*.partial' }).Count | Should Be 0
    }

    It 'requires size as well as path and hash to match' {
        $expected = @([pscustomobject]@{ Path = 'same.txt'; Size = 4; Hash = 'ABCDEF' })
        $actual = @([pscustomobject]@{ Path = 'same.txt'; Size = 5; Hash = 'ABCDEF' })

        (Test-SnapshotManifestMatch -Expected $expected -Actual $actual) | Should Be $false
    }

    It 'publishes one complete final snapshot and leaves no partial after a successful run' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII

        $result = Invoke-SnapshotProcess -Destination $script:Destination

        $result.ExitCode | Should Be 0
        $published = @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -notlike '*.partial' })
        $published.Count | Should Be 1
        @(Get-ChildItem -LiteralPath $script:Destination -Directory -Force |
            Where-Object { $_.Name -like '*.partial' }).Count | Should Be 0
        (Test-Path -LiteralPath (Join-Path $published[0].FullName 'manifest.json')) | Should Be $true
        (Test-Path -LiteralPath (Join-Path $published[0].FullName 'Applications\profile.txt')) | Should Be $true
    }

    It 'allows a destination that shares the source name prefix but is not its descendant' {
        Set-Content -LiteralPath (Join-Path $script:Source 'profile.txt') -Value 'source' -Encoding ASCII
        $siblingDestination = $script:Source + '-backups'

        $result = Invoke-SnapshotProcess -Destination $siblingDestination

        $result.ExitCode | Should Be 0
        @(Get-ChildItem -LiteralPath $siblingDestination -Directory -Force).Count | Should Be 1
    }
}
