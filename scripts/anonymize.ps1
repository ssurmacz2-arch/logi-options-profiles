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
    Allow writing into a non-empty destination.

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

function Test-HasPath {
    param([string] $Text)
    return ($Text -match '[A-Za-z]:\\')
}

$srcInfo = Join-Path $Path 'ProfileInfo.json'
if (-not (Test-Path $srcInfo)) { throw "No ProfileInfo.json in: $Path" }

$newGuid = $null
if ($RegenerateGuid) {
    $newGuid = [guid]::NewGuid().ToString('N').ToUpper()
    $Destination = Join-Path $Destination $newGuid
}

$installedPlugins = @()
if ($DropMissingPlugins) {
    $pluginDir = Join-Path $env:LOCALAPPDATA 'Logi\LogiPluginService\Plugins'
    if (Test-Path $pluginDir) { $installedPlugins = @(Get-ChildItem $pluginDir -Directory | ForEach-Object { $_.Name }) }
}

if (Test-Path $Destination) {
    if (@(Get-ChildItem $Destination -Force).Count -gt 0 -and -not $Force) {
        throw "Destination is not empty: $Destination (use -Force to overwrite)"
    }
} else {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
}

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
        # Catch-all: anything still carrying a drive-letter path.
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

# Copy presentation assets, minus those belonging to removed actions.
$copied = 0; $skipped = 0
foreach ($item in Get-ChildItem $Path -Recurse -File) {
    $rel = $item.FullName.Substring($Path.Length).TrimStart('\')
    if ($rel -eq 'ProfileInfo.json') { continue }
    $orphan = $false
    foreach ($id in $removedIds) { if ($id -and $item.Name -like "*$id*") { $orphan = $true; break } }
    if ($orphan) { $skipped++; continue }
    $target = Join-Path $Destination $rel
    $dir = Split-Path $target -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item $item.FullName $target -Force
    $copied++
}

$out = Join-Path $Destination 'ProfileInfo.json'
$json | ConvertTo-Json -Depth 100 | Set-Content $out -Encoding UTF8

# metadata/LoupedeckPackage.yaml repeats the name and display name, so it has
# to move in step or the package manifest contradicts the profile.
$pkg = Join-Path $Destination 'metadata\LoupedeckPackage.yaml'
if (Test-Path $pkg) {
    $y = Get-Content $pkg -Raw -Encoding UTF8
    if ($newGuid) { $y = $y -replace '(?m)^name:\s*.*$', "name: $newGuid" }
    if ($NewName) { $y = $y -replace '(?m)^displayName:\s*.*$', "displayName: $NewName" }
    Set-Content $pkg -Value $y.TrimEnd() -Encoding UTF8
}

$check = Get-Content $out -Raw -Encoding UTF8
$leftover = [regex]::Matches($check, '[A-Za-z]:\\\\[^"]{3,}') | ForEach-Object { $_.Value } | Select-Object -Unique

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
    Write-Host "PATHS STILL PRESENT - do not publish:" -ForegroundColor Red
    $leftover | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "No absolute paths remain." -ForegroundColor Green
Write-Host "Review display names by hand before publishing - product, broker, and client" -ForegroundColor DarkGray
Write-Host "names survive anonymisation because only you know which ones matter." -ForegroundColor DarkGray
Write-Host ""
exit 0
