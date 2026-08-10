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
    $items = Get-ChildItem $Root -Recurse -File -Force
    $out = New-Object System.Collections.ArrayList
    foreach ($f in $items) {
        [void]$out.Add([pscustomobject]@{
            Path = $f.FullName.Substring($Root.Length).TrimStart('\')
            Size = $f.Length
            Hash = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
        })
    }
    return $out
}

function Get-Snapshot {
    if (-not (Test-Path $Destination)) { return @() }
    return @(Get-ChildItem $Destination -Directory |
             Where-Object { Test-Path (Join-Path $_.FullName 'manifest.json') } |
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

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$target = Join-Path $Destination $stamp
New-Item -ItemType Directory -Force -Path $target | Out-Null

Copy-Item $Source -Destination (Join-Path $target 'Applications') -Recurse -Force

$manifest = Get-Manifest -Root (Join-Path $target 'Applications')
$profileCount = @(Get-ChildItem (Join-Path $target 'Applications') -Recurse -Filter 'ProfileInfo.json').Count

[pscustomobject]@{
    takenAt      = (Get-Date).ToString('o')
    source       = $Source
    profileCount = $profileCount
    fileCount    = @($manifest).Count
    files        = $manifest
} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $target 'manifest.json') -Encoding UTF8

# Verify the copy rather than assuming it worked.
$srcManifest = Get-Manifest -Root $Source
$srcHashes = @($srcManifest | ForEach-Object { $_.Hash } | Sort-Object)
$dstHashes = @($manifest    | ForEach-Object { $_.Hash } | Sort-Object)
$identical = (@($srcHashes).Count -eq @($dstHashes).Count) -and
             (-not (Compare-Object $srcHashes $dstHashes))

Write-Host ""
Write-Host "Snapshot $stamp" -ForegroundColor Cyan
Write-Host "  location: $target"
Write-Host "  profiles: $profileCount"
Write-Host "  files:    $(@($manifest).Count)"
if ($identical) {
    Write-Host "  verified: every file hash matches the source" -ForegroundColor Green
} else {
    Write-Host "  VERIFY FAILED - copy does not match source" -ForegroundColor Red
    Write-Host ""
    exit 1
}
Write-Host ""
Write-Host "  Compare later with:  .\snapshot.ps1 -Compare" -ForegroundColor DarkGray
Write-Host ""
exit 0
