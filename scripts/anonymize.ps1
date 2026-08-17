<#
.SYNOPSIS
    Strips machine-specific shortcuts from a profile so it can be published.

.DESCRIPTION
    Actions that open a file, folder, or application store an absolute path.
    Published as-is, a profile is a map of the author's drives and projects,
    and those paths are useless to anyone else anyway.

    This removes every path-bearing action while keeping the profile's shape:
    folder containers stay, emptied, as a scaffold for the next person to fill.

    Never writes to the source. Output goes to -Destination.

.PARAMETER Path
    The profile folder to anonymise (must contain ProfileInfo.json).

.PARAMETER Destination
    Where to write the anonymised copy. Created if missing; refuses to
    overwrite a non-empty directory unless -Force is given.

.PARAMETER NewName
    Optional display name for the anonymised profile.

.PARAMETER RegenerateGuid
    Issue a fresh profile GUID and write into a subdirectory named after it.
    Options+ only adopts a profile whose folder name matches its 'name' field,
    so this keeps the output directly installable while letting the repository
    path stay human-readable.

.PARAMETER DropMissingPlugins
    Also remove actions provided by plugins that are not installed locally.
    Publishing a profile with dependencies even the author lacks just ships
    dead slots.

.PARAMETER Force
    Replace a non-empty destination after the staged copy passes validation.

.EXAMPLE
    .\anonymize.ps1 -Path "$env:LOCALAPPDATA\Logi\...\Profiles\<GUID>" -Destination ..\profiles\loupedeck72\general\starter

.LINK
    https://github.com/ssurmacz2-arch/logi-options-profiles
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Path,
    [Parameter(Mandatory = $true)][string] $Destination,
    [string] $NewName,
    [switch] $RegenerateGuid,
    [switch] $DropMissingPlugins,
    [switch] $Force
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Action templates that embed a filesystem location. These get removed.
$PathBearingTemplates = @(
    '$@Generic___@OpenDirectory',   # directoryPath
    '$@Generic___@ShellExecute'     # filePath
)
# Inline action verbs that carry a path in the action string itself.
$PathBearingVerbs = @('@ExecuteApplication', '@OpenDocument', '@OpenFile')

# Containers. Kept, but left empty - they carry the profile's structure.
$ContainerTemplates = @('$@Generic___@OpenFolder')

$DrivePathPattern = '(?i)(?<![A-Za-z0-9])[A-Za-z]:[\\/][^\x00\r\n"''<>|]*'
$UncPathPattern = '(?i)(?<![A-Za-z0-9_:\\/])(?:\\{2,}|/{2,})[^\\/\x00\r\n"''<>|]+[\\/]+[^\\/\x00\r\n"''<>|]+'
$SecretPatterns = @(
    '(?i)\b(?:api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passwd)\b\s*[:=]\s*["'']?[A-Za-z0-9_./+=-]{12,}',
    '(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{12,}',
    '\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b',
    '\bsk-[A-Za-z0-9_-]{20,}\b',
    '\bAKIA[0-9A-Z]{16}\b'
)

function Test-HasPath {
    param([string] $Text)
    return ($Text -match $DrivePathPattern -or $Text -match $UncPathPattern)
}

function Get-NormalizedFileSystemPath {
    param(
        [Parameter(Mandatory = $true)][string] $InputPath,
        [switch] $MustExist
    )

    if ([string]::IsNullOrWhiteSpace($InputPath)) { throw 'Path cannot be empty.' }

    $provider = $null
    $drive = $null
    $providerPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        $InputPath,
        [ref] $provider,
        [ref] $drive
    )
    if ($provider.Name -ne 'FileSystem') { throw "Only filesystem paths are supported: $InputPath" }

    $fullPath = [System.IO.Path]::GetFullPath($providerPath)
    if ($MustExist) {
        if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
            throw "Directory does not exist: $InputPath"
        }
        $fullPath = (Get-Item -LiteralPath $fullPath -Force).FullName
    }

    $root = [System.IO.Path]::GetPathRoot($fullPath)
    while ($fullPath.Length -gt $root.Length -and ($fullPath.EndsWith('\') -or $fullPath.EndsWith('/'))) {
        $fullPath = $fullPath.Substring(0, $fullPath.Length - 1)
    }
    return $fullPath
}

function Test-IsSameOrDescendantPath {
    param(
        [Parameter(Mandatory = $true)][string] $Candidate,
        [Parameter(Mandatory = $true)][string] $Parent
    )

    if ([string]::Equals($Candidate, $Parent, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = $Parent
    if (-not ($prefix.EndsWith('\') -or $prefix.EndsWith('/'))) {
        $prefix += [System.IO.Path]::DirectorySeparatorChar
    }
    return $Candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePointInExistingPath {
    param(
        [Parameter(Mandatory = $true)][string] $InputPath,
        [Parameter(Mandatory = $true)][string] $Label
    )

    $current = $InputPath
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
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $Label
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

function Find-PrivacyLeaks {
    param([Parameter(Mandatory = $true)][string] $Root)

    $found = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -Force -File) {
        $relativePath = ($file.FullName.Substring($Root.Length) -replace '^[\\/]+', '')
        [byte[]] $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $views = @(
            [System.Text.Encoding]::UTF8.GetString($bytes),
            [System.Text.Encoding]::Unicode.GetString($bytes),
            [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
        )

        foreach ($view in $views) {
            $checks = @(
                [pscustomobject]@{ Kind = 'path'; Patterns = @($DrivePathPattern, $UncPathPattern) },
                [pscustomobject]@{ Kind = 'potential-secret'; Patterns = @($SecretPatterns) }
            )
            foreach ($check in $checks) {
                foreach ($pattern in $check.Patterns) {
                    foreach ($match in [regex]::Matches($view, $pattern)) {
                    $value = $match.Value
                    if ($check.Kind -eq 'potential-secret' -and
                        $value -match '(?i)placeholder|replace[_-]?me|your[_-]?(?:api[_-]?key|token|secret)|example|dummy|redacted|changeme') {
                        continue
                    }
                    if ($value.Length -gt 200) { $value = $value.Substring(0, 200) + '...' }
                    $key = $check.Kind + "`0" + $relativePath + "`0" + $value
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        [void] $found.Add([pscustomobject]@{
                            Kind = $check.Kind
                            File = $relativePath
                            Value = $value
                        })
                    }
                    }
                }
            }
        }
    }
    return $found.ToArray()
}

function Publish-StagedDirectory {
    param(
        [Parameter(Mandatory = $true)][string] $Staging,
        [Parameter(Mandatory = $true)][string] $FinalDestination
    )

    $backup = $null
    if (Test-Path -LiteralPath $FinalDestination) {
        Assert-NoReparsePointInExistingPath -InputPath $FinalDestination -Label 'Destination'
        Assert-NoReparsePointInTree -Root $FinalDestination -Label 'Destination'
        $parent = Split-Path -Parent $FinalDestination
        $leaf = Split-Path -Leaf $FinalDestination
        $backup = Join-Path $parent ('.' + $leaf + '.anonymize-backup-' + [guid]::NewGuid().ToString('N'))
        Move-Item -LiteralPath $FinalDestination -Destination $backup
    }

    try {
        Move-Item -LiteralPath $Staging -Destination $FinalDestination
    } catch {
        $promotionError = $_
        if ($backup -and (Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $FinalDestination)) {
            try {
                Move-Item -LiteralPath $backup -Destination $FinalDestination
            } catch {
                throw "Staged promotion failed and rollback also failed. Previous output remains at: $backup"
            }
        }
        throw $promotionError
    }

    if ($backup -and (Test-Path -LiteralPath $backup)) {
        Assert-NoReparsePointInTree -Root $backup -Label 'Previous output backup'
        Remove-Item -LiteralPath $backup -Recurse -Force
    }
}

$newGuid = $null
if ($RegenerateGuid) {
    $newGuid = [guid]::NewGuid().ToString('N').ToUpper()
    $Destination = Join-Path $Destination $newGuid
}

$Path = Get-NormalizedFileSystemPath -InputPath $Path -MustExist
$Destination = Get-NormalizedFileSystemPath -InputPath $Destination

Assert-NoReparsePointInExistingPath -InputPath $Path -Label 'Source'
Assert-NoReparsePointInTree -Root $Path -Label 'Source'
Assert-NoReparsePointInExistingPath -InputPath $Destination -Label 'Destination'
if (Test-Path -LiteralPath $Destination -PathType Container) {
    Assert-NoReparsePointInTree -Root $Destination -Label 'Destination'
}

if ((Test-IsSameOrDescendantPath -Candidate $Destination -Parent $Path) -or
    (Test-IsSameOrDescendantPath -Candidate $Path -Parent $Destination)) {
    throw "Source and destination paths overlap: source=$Path destination=$Destination"
}

$srcInfo = Join-Path $Path 'ProfileInfo.json'
if (-not (Test-Path -LiteralPath $srcInfo -PathType Leaf)) { throw "No ProfileInfo.json in: $Path" }

$installedPlugins = @()
if ($DropMissingPlugins) {
    $pluginDir = Join-Path $env:LOCALAPPDATA 'Logi\LogiPluginService\Plugins'
    if (Test-Path $pluginDir) { $installedPlugins = @(Get-ChildItem $pluginDir -Directory | ForEach-Object { $_.Name }) }
}

if (Test-Path -LiteralPath $Destination) {
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        throw "Destination is not a directory: $Destination"
    }
    if (@(Get-ChildItem -LiteralPath $Destination -Force).Count -gt 0 -and -not $Force) {
        throw "Destination is not empty: $Destination (use -Force to overwrite)"
    }
}

$destinationParent = Split-Path -Parent $Destination
$destinationLeaf = Split-Path -Leaf $Destination
if ([string]::IsNullOrWhiteSpace($destinationParent) -or [string]::IsNullOrWhiteSpace($destinationLeaf)) {
    throw "Destination cannot be a filesystem root: $Destination"
}
if ((Test-Path -LiteralPath $destinationParent) -and -not (Test-Path -LiteralPath $destinationParent -PathType Container)) {
    throw "Destination parent is not a directory: $destinationParent"
}
$stagingPath = Join-Path $destinationParent ('.' + $destinationLeaf + '.anonymize-staging-' + [guid]::NewGuid().ToString('N'))

$json = Get-Content $srcInfo -Raw -Encoding UTF8 | ConvertFrom-Json

$removedIds = New-Object System.Collections.ArrayList
$removedLog = New-Object System.Collections.ArrayList
$keptContainers = 0

function Select-KeptAction {
    param($Items, [string] $IdPrefix)
    $kept = New-Object System.Collections.ArrayList
    foreach ($a in @($Items)) {
        $tpl = if ($a.PSObject.Properties.Name -contains 'templateActionName') { [string]$a.templateActionName } else { '' }
        $name = [string]$a.name
        $label = if ($a.PSObject.Properties.Name -contains 'displayName') { [string]$a.displayName } else { $name }

        if ($ContainerTemplates -contains $tpl) {
            [void]$kept.Add($a); $script:keptContainers++
            continue
        }

        $drop = $false; $why = ''
        if ($PathBearingTemplates -contains $tpl) { $drop = $true; $why = "template $tpl" }
        foreach ($v in $PathBearingVerbs) {
            if ($a.PSObject.Properties.Name -contains 'actions') {
                foreach ($inner in @($a.actions)) { if ([string]$inner -like "*$v*") { $drop = $true; $why = "action $v" } }
            }
        }
        # Catch-all: anything still carrying a drive-letter or UNC path.
        if (-not $drop) {
            $blob = $a | ConvertTo-Json -Depth 20 -Compress
            if (Test-HasPath $blob) { $drop = $true; $why = 'embedded absolute path' }
        }

        if ($drop) {
            # Slot references use the bare name for profile actions and a
            # @Macro___ prefix for macros, so record both forms.
            [void]$removedIds.Add($name)
            [void]$removedIds.Add("$IdPrefix$name")
            [void]$removedLog.Add("  removed: $label  ($why)")
        } else {
            [void]$kept.Add($a)
        }
    }
    return , $kept.ToArray()
}

foreach ($listName in @('profileActions', 'macroCommands', 'profileCommands', 'macroAdjustments', 'profileAdjustments')) {
    if ($json.PSObject.Properties.Name -contains $listName) {
        $prefix = if ($listName -like 'macro*') { '$@Generic___@Macro___' } else { '' }
        $json.$listName = Select-KeptAction -Items $json.$listName -IdPrefix $prefix
    }
}

# Clear slots that pointed at anything removed.
$clearedSlots = 0
function Clear-DeadSlot {
    param($Node)
    if ($null -eq $Node) { return }
    foreach ($prop in @('pressAction', 'rotateAction')) {
        if ($Node.PSObject.Properties.Name -contains $prop) {
            $v = [string]$Node.$prop
            if ($v -and ($removedIds -contains $v)) { $Node.$prop = ''; $script:clearedSlots++ }
        }
    }
    foreach ($p in $Node.PSObject.Properties) {
        $val = $p.Value
        if ($val -is [System.Management.Automation.PSCustomObject]) { Clear-DeadSlot -Node $val }
        elseif ($val -is [System.Object[]]) { foreach ($x in $val) { if ($x -is [System.Management.Automation.PSCustomObject]) { Clear-DeadSlot -Node $x } } }
    }
}
Clear-DeadSlot -Node $json.layout

# Slots pointing at plugins that are not installed. There is nothing to delete
# from the profile - plugin actions are resolved at runtime - so clear the slot.
$droppedPlugins = New-Object System.Collections.ArrayList
if ($DropMissingPlugins) {
    $native = @('@Generic', 'DefaultWin', 'DefaultMac')
    function Clear-MissingPluginSlot {
        param($Node)
        if ($null -eq $Node) { return }
        foreach ($prop in @('pressAction', 'rotateAction')) {
            if ($Node.PSObject.Properties.Name -contains $prop) {
                $v = [string]$Node.$prop
                if ($v -match '^\$([^_]+)___') {
                    $p = $Matches[1]
                    if ($native -notcontains $p -and $installedPlugins -notcontains $p) {
                        $Node.$prop = ''
                        if (-not $droppedPlugins.Contains($p)) { [void]$droppedPlugins.Add($p) }
                    }
                }
            }
        }
        foreach ($pr in $Node.PSObject.Properties) {
            $val = $pr.Value
            if ($val -is [System.Management.Automation.PSCustomObject]) { Clear-MissingPluginSlot -Node $val }
            elseif ($val -is [System.Object[]]) { foreach ($x in $val) { if ($x -is [System.Management.Automation.PSCustomObject]) { Clear-MissingPluginSlot -Node $x } } }
        }
    }
    Clear-MissingPluginSlot -Node $json.layout
}

if ($NewName) { $json.displayName = $NewName }
if ($newGuid) {
    $json.name = $newGuid
    if ($json.PSObject.Properties.Name -contains 'packageName') { $json.packageName = $newGuid }
}

# Build the complete output in a sibling staging directory. The final path is
# only replaced after every copied file passes the leak scan.
$copied = 0; $skipped = 0
$leftover = @()
$published = $false
$stagingOwned = $false
try {
    if (-not (Test-Path -LiteralPath $destinationParent)) {
        [void] [System.IO.Directory]::CreateDirectory($destinationParent)
    }
    Assert-NoReparsePointInExistingPath -InputPath $destinationParent -Label 'Destination parent'
    if (Test-Path -LiteralPath $stagingPath) {
        throw "Refusing to reuse an existing staging directory: $stagingPath"
    }
    $createdStaging = New-Item -ItemType Directory -Path $stagingPath
    if (($createdStaging.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing reparse-point staging directory: $stagingPath"
    }
    $stagingOwned = $true

    # Copy presentation assets, minus those belonging to removed actions.
    foreach ($item in Get-ChildItem -LiteralPath $Path -Recurse -Force -File) {
        $rel = ($item.FullName.Substring($Path.Length) -replace '^[\\/]+', '')
        if ($rel -eq 'ProfileInfo.json') { continue }
        $orphan = $false
        foreach ($id in $removedIds) { if ($id -and $item.Name -like "*$id*") { $orphan = $true; break } }
        if ($orphan) { $skipped++; continue }
        $target = Join-Path $stagingPath $rel
        $dir = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $dir)) { [void] [System.IO.Directory]::CreateDirectory($dir) }
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        $copied++
    }

    $out = Join-Path $stagingPath 'ProfileInfo.json'
    $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $out -Encoding UTF8

    # metadata/LoupedeckPackage.yaml repeats the name and display name, so it
    # has to move in step or the package manifest contradicts the profile.
    $pkg = Join-Path $stagingPath 'metadata\LoupedeckPackage.yaml'
    if (Test-Path -LiteralPath $pkg -PathType Leaf) {
        $y = Get-Content -LiteralPath $pkg -Raw -Encoding UTF8
        if ($newGuid) { $y = $y -replace '(?m)^name:\s*.*$', "name: $newGuid" }
        if ($NewName) { $y = $y -replace '(?m)^displayName:\s*.*$', "displayName: $NewName" }
        Set-Content -LiteralPath $pkg -Value $y.TrimEnd() -Encoding UTF8
    }

    Assert-NoReparsePointInTree -Root $stagingPath -Label 'Staging'
    $leftover = @(Find-PrivacyLeaks -Root $stagingPath)

    Write-Host ""
    Write-Host "Anonymised profile" -ForegroundColor Cyan
    Write-Host "  source:      $Path"
    Write-Host "  destination: $Destination"
    Write-Host ""
    if (@($removedLog).Count -gt 0) { $removedLog | ForEach-Object { Write-Host $_ -ForegroundColor Yellow } }
    else { Write-Host "  nothing to remove - no path-bearing actions found" -ForegroundColor Green }
    Write-Host ""
    if (@($droppedPlugins).Count -gt 0) {
        Write-Host "  dropped slots for uninstalled plugins: $($droppedPlugins -join ', ')" -ForegroundColor Yellow
        Write-Host ""
    }
    Write-Host "  containers kept: $keptContainers"
    Write-Host "  slots cleared:   $clearedSlots"
    Write-Host "  assets copied:   $copied (skipped $skipped orphaned)"
    if ($newGuid) { Write-Host "  new profile GUID: $newGuid" }
    Write-Host ""

    if (@($leftover).Count -gt 0) {
        $leakKinds = @($leftover | ForEach-Object { $_.Kind } | Sort-Object -Unique)
        if ($leakKinds.Count -eq 1 -and $leakKinds[0] -eq 'path') {
            Write-Host "PATHS STILL PRESENT - do not publish:" -ForegroundColor Red
        } elseif ($leakKinds.Count -eq 1 -and $leakKinds[0] -eq 'potential-secret') {
            Write-Host "POTENTIAL SECRETS STILL PRESENT - do not publish:" -ForegroundColor Red
        } else {
            Write-Host "PRIVACY LEAKS STILL PRESENT - do not publish:" -ForegroundColor Red
        }
        # Never echo a discovered path or credential-like value. The file and
        # leak class are enough to locate it without putting private data in CI logs.
        $leftover | ForEach-Object { Write-Host "  [$($_.Kind)] $($_.File)" -ForegroundColor Red }
    } else {
        Publish-StagedDirectory -Staging $stagingPath -FinalDestination $Destination
        $published = $true
        $stagingOwned = $false
    }
} finally {
    if ($stagingOwned -and (Test-Path -LiteralPath $stagingPath)) {
        $stagingItem = Get-Item -LiteralPath $stagingPath -Force
        $isReparse = (($stagingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
        $isDirectChild = [string]::Equals(
            [System.IO.Path]::GetDirectoryName($stagingItem.FullName),
            $destinationParent,
            [System.StringComparison]::OrdinalIgnoreCase)
        $isExpectedName = $stagingItem.Name.StartsWith(
            '.' + $destinationLeaf + '.anonymize-staging-',
            [System.StringComparison]::OrdinalIgnoreCase)
        if ($isDirectChild -and $isExpectedName -and -not $isReparse) {
            Remove-Item -LiteralPath $stagingPath -Recurse -Force
        } else {
            Write-Warning "Refusing to clean unexpected or reparse-point staging path: $stagingPath"
        }
    }
}

if (@($leftover).Count -gt 0) { exit 1 }
if (-not $published) { throw "Anonymised output was not promoted to: $Destination" }

Write-Host "No absolute paths remain." -ForegroundColor Green
Write-Host "Review display names by hand before publishing - product, broker, and client" -ForegroundColor DarkGray
Write-Host "names survive anonymisation because only you know which ones matter." -ForegroundColor DarkGray
Write-Host ""
exit 0
