<#
.SYNOPSIS
    Timestamped local backup of the Logi Options+ profile tree, with a hash manifest.

.DESCRIPTION
    Options+ writes its own ZIP snapshots, but on an undocumented schedule with
    no retention guarantee. This takes a copy you control, and records a SHA256
    manifest so you can see exactly what changed between two points in time.

    Read-only against the live tree. It copies; it never modifies Options+.

.PARAMETER Destination
    Root directory for snapshots. Each run creates a timestamped subdirectory.
    Defaults to %USERPROFILE%\logi-profile-snapshots.

.PARAMETER List
    List existing snapshots instead of taking one.

.PARAMETER Compare
    Compare the live tree against the most recent snapshot and report drift.
    Takes no copy.

.EXAMPLE
    .\snapshot.ps1
    Take a snapshot into the default location.

.EXAMPLE
    .\snapshot.ps1 -Compare
    Show what changed since the last snapshot.

.LINK
    https://github.com/ssurmacz2-arch/logi-options-profiles
#>

[CmdletBinding()]
param(
    [string] $Destination = (Join-Path $env:USERPROFILE 'logi-profile-snapshots'),
    [switch] $List,
    [switch] $Compare
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$Source = Join-Path $env:LOCALAPPDATA 'Logi\LogiPluginService\Applications'
if (-not (Test-Path $Source)) { throw "Profile tree not found: $Source" }

function Get-Manifest {
    param([string] $Root)
    $items = Get-ChildItem -LiteralPath $Root -Recurse -File -Force
    $out = New-Object System.Collections.ArrayList
    foreach ($f in $items) {
        [void]$out.Add([pscustomobject]@{
            Path = $f.FullName.Substring($Root.Length).TrimStart('\')
            Size = $f.Length
            Hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
        })
    }
    return $out
}

function Get-NormalizedFullPath {
    param([string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($fullPath)
    while ($fullPath.Length -gt $root.Length -and
           ($fullPath.EndsWith([string][System.IO.Path]::DirectorySeparatorChar) -or
            $fullPath.EndsWith([string][System.IO.Path]::AltDirectorySeparatorChar))) {
        $fullPath = $fullPath.Substring(0, $fullPath.Length - 1)
    }
    return $fullPath
}

function Test-PathIsSameOrDescendant {
    param(
        [string] $ParentPath,
        [string] $CandidatePath
    )

    $parent = Get-NormalizedFullPath -Path $ParentPath
    $candidate = Get-NormalizedFullPath -Path $CandidatePath
    if ($candidate.Equals($parent, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }

    $prefix = $parent + [System.IO.Path]::DirectorySeparatorChar
    return $candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointInExistingPath {
    param(
        [string] $Path,
        [string] $Label
    )

    $current = Get-NormalizedFullPath -Path $Path
    while (-not (Test-Path -LiteralPath $current)) {
        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { return }
        $current = $parent
    }

    while ($true) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label path traverses a junction, symbolic link, or other reparse point: $current"
        }

        $parent = [System.IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Assert-NoReparsePointInTree {
    param(
        [string] $Root,
        [string] $Label
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $rootItem = Get-Item -LiteralPath $Root -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "$Label tree contains a junction, symbolic link, or other reparse point: $($rootItem.FullName)"
    }

    $pending = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pending.Push([System.IO.DirectoryInfo] $rootItem)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($child in $directory.GetFileSystemInfos()) {
            if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label tree contains a junction, symbolic link, or other reparse point: $($child.FullName)"
            }
            if ($child -is [System.IO.DirectoryInfo]) { $pending.Push($child) }
        }
    }
}

function Test-ManifestMatch {
    param(
        [object[]] $Expected,
        [object[]] $Actual
    )

    $expectedItems = @($Expected)
    $actualItems = @($Actual)
    if ($expectedItems.Count -ne $actualItems.Count) { return $false }

    $expectedMap = @{}
    foreach ($file in $expectedItems) {
        $path = [string]$file.Path
        if ($expectedMap.ContainsKey($path)) { return $false }
        $expectedMap[$path] = [pscustomobject]@{
            Size = [long]$file.Size
            Hash = [string]$file.Hash
        }
    }

    $actualMap = @{}
    foreach ($file in $actualItems) {
        $path = [string]$file.Path
        if ($actualMap.ContainsKey($path)) { return $false }
        $actualMap[$path] = [pscustomobject]@{
            Size = [long]$file.Size
            Hash = [string]$file.Hash
        }
    }

    foreach ($path in $expectedMap.Keys) {
        if (-not $actualMap.ContainsKey($path)) { return $false }
        if ($expectedMap[$path].Size -ne $actualMap[$path].Size) { return $false }
        if (-not [string]::Equals(
                $expectedMap[$path].Hash,
                $actualMap[$path].Hash,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }
    return $true
}

function Get-Snapshot {
    if (-not (Test-Path $Destination)) { return @() }
    return @(Get-ChildItem -LiteralPath $Destination -Directory |
             Where-Object {
                 -not $_.Name.EndsWith('.partial', [System.StringComparison]::OrdinalIgnoreCase) -and
                 (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json'))
             } |
             Sort-Object Name)
}

# ---- list ----

if ($List) {
    $snaps = Get-Snapshot
    Write-Host ""
    if (@($snaps).Count -eq 0) { Write-Host "No snapshots in $Destination"; Write-Host ""; exit 0 }
    Write-Host "Snapshots in $Destination" -ForegroundColor Cyan
    Write-Host ""
    foreach ($s in $snaps) {
        $m = Get-Content (Join-Path $s.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        "{0}   {1,4} files   {2,4} profiles" -f $s.Name, @($m.files).Count, $m.profileCount
    }
    Write-Host ""
    exit 0
}

# ---- compare ----

if ($Compare) {
    $snaps = Get-Snapshot
    if (@($snaps).Count -eq 0) { throw "No snapshot to compare against. Run without -Compare first." }
    $latest = $snaps[-1]
    $old = (Get-Content (Join-Path $latest.FullName 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json).files
    $new = Get-Manifest -Root $Source

    $oldMap = @{}; foreach ($f in @($old)) { $oldMap[$f.Path] = $f.Hash }
    $newMap = @{}; foreach ($f in @($new)) { $newMap[$f.Path] = $f.Hash }

    $added    = @($newMap.Keys | Where-Object { -not $oldMap.ContainsKey($_) })
    $removed  = @($oldMap.Keys | Where-Object { -not $newMap.ContainsKey($_) })
    $modified = @($newMap.Keys | Where-Object { $oldMap.ContainsKey($_) -and $oldMap[$_] -ne $newMap[$_] })

    Write-Host ""
    Write-Host "Drift since $($latest.Name)" -ForegroundColor Cyan
    Write-Host ""
    foreach ($f in ($added    | Sort-Object)) { Write-Host "  added     $f" -ForegroundColor Green }
    foreach ($f in ($removed  | Sort-Object)) { Write-Host "  removed   $f" -ForegroundColor Red }
    foreach ($f in ($modified | Sort-Object)) { Write-Host "  modified  $f" -ForegroundColor Yellow }
    if (@($added).Count + @($removed).Count + @($modified).Count -eq 0) {
        Write-Host "  no changes" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "$(@($added).Count) added, $(@($removed).Count) removed, $(@($modified).Count) modified"
    Write-Host ""
    exit 0
}

# ---- snapshot ----

Assert-NoReparsePointInExistingPath -Path $Source -Label 'Source'
Assert-NoReparsePointInTree -Root $Source -Label 'Source'
Assert-NoReparsePointInExistingPath -Path $Destination -Label 'Destination'

if (Test-PathIsSameOrDescendant -ParentPath $Source -CandidatePath $Destination) {
    throw "Destination must not be the source directory or a descendant: $Destination"
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$runId = [guid]::NewGuid().ToString('N')
$snapshotName = $stamp
$target = Join-Path $Destination $snapshotName
if (Test-Path -LiteralPath $target) {
    $snapshotName = '{0}-{1}' -f $stamp, $runId.Substring(0, 8)
    $target = Join-Path $Destination $snapshotName
}

$stagingName = '{0}.{1}.partial' -f $snapshotName, $runId
$staging = Join-Path $Destination $stagingName
$stagingOwned = $false
$snapshotError = $null
$manifest = @()
$profileCount = 0

try {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Assert-NoReparsePointInExistingPath -Path $Destination -Label 'Destination'

    $createdStaging = New-Item -ItemType Directory -Path $staging
    if (($createdStaging.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing reparse-point staging directory: $staging"
    }
    $stagingOwned = $true

    $stagedApplications = Join-Path $staging 'Applications'
    Copy-Item $Source -Destination $stagedApplications -Recurse -Force
    Assert-NoReparsePointInTree -Root $stagedApplications -Label 'Staging'

    $manifest = Get-Manifest -Root $stagedApplications
    $profileCount = @(Get-ChildItem -LiteralPath $stagedApplications -Recurse -Filter 'ProfileInfo.json').Count

    # Preserve path identity: matching only the multiset of hashes can accept
    # two files whose contents were swapped during the copy.
    $srcManifest = Get-Manifest -Root $Source
    if (-not (Test-ManifestMatch -Expected $srcManifest -Actual $manifest)) {
        throw 'VERIFY FAILED - copy does not match source'
    }

    [pscustomobject]@{
        takenAt      = (Get-Date).ToString('o')
        source       = $Source
        profileCount = $profileCount
        fileCount    = @($manifest).Count
        files        = $manifest
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $staging 'manifest.json') -Encoding UTF8

    # Directory.Move is the publication boundary. A final directory cannot be
    # observed until the verified staging directory is complete.
    [System.IO.Directory]::Move($staging, $target)
    $staging = $null
    $stagingOwned = $false
} catch {
    $snapshotError = $_
} finally {
    if ($stagingOwned -and $staging -and (Test-Path -LiteralPath $staging)) {
        $stagingFullPath = Get-NormalizedFullPath -Path $staging
        $destinationFullPath = Get-NormalizedFullPath -Path $Destination
        $stagingItem = Get-Item -LiteralPath $stagingFullPath -Force
        $stagingParent = [System.IO.Path]::GetDirectoryName($stagingFullPath)
        $isDirectChild = $stagingParent.Equals(
            $destinationFullPath,
            [System.StringComparison]::OrdinalIgnoreCase)
        $isPartial = [System.IO.Path]::GetFileName($stagingFullPath).EndsWith(
            '.partial',
            [System.StringComparison]::OrdinalIgnoreCase)
        $isReparse = (($stagingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)

        if ($isDirectChild -and $isPartial -and -not $isReparse) {
            try {
                Remove-Item -LiteralPath $stagingFullPath -Recurse -Force
            } catch {
                if (-not $snapshotError) { $snapshotError = $_ }
                else { Write-Warning "Could not clean staging directory: $stagingFullPath" }
            }
        } else {
            if (-not $snapshotError) {
                $snapshotError = [System.InvalidOperationException]::new(
                    "Refusing to clean unexpected or reparse-point staging path: $stagingFullPath")
            }
        }
    }
}

if ($snapshotError) {
    Write-Host ""
    Write-Host $snapshotError.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Snapshot $snapshotName" -ForegroundColor Cyan
Write-Host "  location: $target"
Write-Host "  profiles: $profileCount"
Write-Host "  files:    $(@($manifest).Count)"
Write-Host "  verified: every file path and hash matches the source" -ForegroundColor Green
Write-Host ""
Write-Host "  Compare later with:  .\snapshot.ps1 -Compare" -ForegroundColor DarkGray
Write-Host ""
exit 0
