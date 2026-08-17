<#
.SYNOPSIS
    Validates Logi Options+ profile folders and reports missing plugin dependencies.

.DESCRIPTION
    A profile that references a plugin you do not have installs cleanly and leaves
    dead slots, with nothing in the Options+ UI to indicate it. This script finds
    that case, along with structural problems that stop a profile loading at all.

    Read-only. It never writes, moves, or deletes anything, and never touches the
    Options+ services.

.PARAMETER Path
    A profile folder (containing ProfileInfo.json), or a directory to search
    recursively for profiles. Defaults to the local Options+ profile tree.

.PARAMETER Json
    Emit a machine-readable object instead of a formatted report.

.PARAMETER Quiet
    Report only profiles with errors or warnings.

.EXAMPLE
    .\verify.ps1
    Check every profile installed locally.

.EXAMPLE
    .\verify.ps1 -Path ..\profiles\loupedeck72\myapp\my-profile
    Check a single profile before publishing or installing it.

.LINK
    https://github.com/ssurmacz2-arch/logi-options-profiles
#>

[CmdletBinding()]
param(
    [string] $Path,
    [switch] $Json,
    [switch] $Quiet
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Profile display names are UTF-8 and routinely non-ASCII. Windows PowerShell 5.1
# defaults the console to a legacy code page and would mangle them.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Actions provided by the host rather than an installed plugin package.
$NativeProviders = @('@Generic', 'DefaultWin', 'DefaultMac')

# From the DeviceType enum in PluginApi.dll. See docs/device-types.md.
$KnownDeviceTypes = @{
    'Loupedeck10' = 'Loupedeck Original'; 'Loupedeck15' = 'Loupedeck+'
    'Loupedeck20' = 'Loupedeck CT';       'Loupedeck30' = 'Loupedeck Live'
    'Loupedeck40' = 'Razer Stream Controller'
    'Loupedeck50' = 'Loupedeck Live S';   'Loupedeck60' = 'Razer Stream Controller X'
    'Loupedeck70' = 'MX Creative Keypad'; 'Loupedeck71' = 'MX Creative Dialpad'
    'Loupedeck72' = 'Actions Ring'
}

function Get-InstalledPlugin {
    $dir = Join-Path $env:LOCALAPPDATA 'Logi\LogiPluginService\Plugins'
    if (Test-Path $dir) { return @(Get-ChildItem $dir -Directory | ForEach-Object { $_.Name }) }
    return @()
}

function Find-Profile {
    param([string] $Root)
    if (-not (Test-Path -LiteralPath $Root)) { throw "Path not found: $Root" }

    $rootItem = Get-Item -LiteralPath $Root
    if (-not $rootItem.PSIsContainer) { throw "Path is not a directory: $Root" }
    if (Test-Path -LiteralPath (Join-Path $Root 'ProfileInfo.json')) { return @($rootItem) }

    $profiles = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter 'ProfileInfo.json' -File -ErrorAction SilentlyContinue |
                  ForEach-Object { $_.Directory })

    # An explicitly supplied directory with no ProfileInfo.json is itself an
    # invalid profile candidate. Returning no results used to produce warning
    # text and exit 0, which was a false green for automation.
    if ($profiles.Count -eq 0) { return @($rootItem) }
    return $profiles
}

function Test-Profile {
    param([System.IO.DirectoryInfo] $Dir, [string[]] $Installed)

    $errors = New-Object System.Collections.ArrayList
    $warnings = New-Object System.Collections.ArrayList
    $result = [ordered]@{
        Path = $Dir.FullName; Name = $null; DisplayName = '(unreadable profile)'
        DeviceType = $null; Application = $null
        Slots = 0; Dependencies = @(); MissingPlugins = @()
        Errors = @(); Warnings = @(); Ok = $false
    }

    $infoPath = Join-Path $Dir.FullName 'ProfileInfo.json'
    if (-not (Test-Path $infoPath)) {
        [void]$errors.Add('ProfileInfo.json is missing')
        $result.Errors = $errors.ToArray(); return [pscustomobject]$result
    }

    # -Encoding UTF8 matters on Windows PowerShell 5.1, which otherwise reads
    # the file in the system code page and corrupts non-ASCII display names.
    $raw = Get-Content $infoPath -Raw -Encoding UTF8
    try { $json = $raw | ConvertFrom-Json }
    catch {
        [void]$errors.Add("ProfileInfo.json is not valid JSON: $($_.Exception.Message)")
        $result.Errors = $errors.ToArray(); return [pscustomobject]$result
    }

    foreach ($f in 'name', 'deviceType') {
        if (-not ($json.PSObject.Properties.Name -contains $f)) { [void]$errors.Add("Missing required field '$f'") }
    }

    $result.Name = if ($json.PSObject.Properties.Name -contains 'name') { $json.name } else { $null }
    $result.DeviceType = if ($json.PSObject.Properties.Name -contains 'deviceType') { $json.deviceType } else { $null }
    $result.Application = if ($json.PSObject.Properties.Name -contains 'applicationName') { $json.applicationName } else { $null }
    $display = if ($json.PSObject.Properties.Name -contains 'displayName') { $json.displayName } else { '(no display name)' }

    # The folder name must equal the name field, or Options+ will not adopt it.
    if ($result.Name -and $Dir.Name -ne $result.Name) {
        [void]$errors.Add("Folder name '$($Dir.Name)' does not match the 'name' field '$($result.Name)'")
    }
    if ($result.DeviceType -and -not $KnownDeviceTypes.ContainsKey($result.DeviceType)) {
        [void]$warnings.Add("Unrecognised deviceType '$($result.DeviceType)'")
    }

    # Collect every action reference and group by the provider prefix.
    $actions = [regex]::Matches($raw, '"(?:pressAction|rotateAction)":\s*"\$([^"]+)"') |
               ForEach-Object { $_.Groups[1].Value }
    $result.Slots = @($actions).Count

    $providers = @{}
    foreach ($a in $actions) {
        $p = if ($a -match '^([^_]+)___') { $Matches[1] } else { $a }
        $providers[$p] = $true
    }

    $deps = @(); $missing = @()
    foreach ($p in $providers.Keys) {
        if ($NativeProviders -contains $p) { continue }
        $deps += $p
        if ($Installed -notcontains $p) { $missing += $p }
    }
    $result.Dependencies = @($deps | Sort-Object)
    $result.MissingPlugins = @($missing | Sort-Object)
    foreach ($m in $result.MissingPlugins) {
        [void]$warnings.Add("Plugin '$m' is referenced but not installed - those slots will be dead")
    }

    # Every @Macro___<GUID> reference should have a definition in this same file.
    foreach ($g in ([regex]::Matches($raw, '@Macro___([A-F0-9]{32})') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)) {
        if (-not ($raw -match ('"name":\s*"' + $g + '"'))) {
            [void]$errors.Add("Macro $g is referenced but not defined in this profile")
        }
    }

    # Absolute drive and UNC paths are a portability and privacy smell. The
    # JSON source escapes backslashes, so both patterns accept repeated slashes.
    $pathPatterns = @(
        '[A-Za-z]:\\\\[^"]{3,}',
        '(?i)(?<![A-Za-z0-9_:\\/])(?:\\{2,}|/{2,})[^\\/\x00\r\n"''<>|]+[\\/]+[^\\/\x00\r\n"''<>|]+'
    )
    $abs = @($pathPatterns | ForEach-Object {
        [regex]::Matches($raw, $_) | ForEach-Object { $_.Value }
    } | Select-Object -Unique)
    foreach ($a in @($abs)) { [void]$warnings.Add("Absolute path found: $a") }

    $result.Errors = $errors.ToArray()
    $result.Warnings = $warnings.ToArray()
    $result.Ok = ($errors.Count -eq 0)
    $result.DisplayName = $display
    return [pscustomobject]$result
}

# ---- run ----

if (-not $Path) { $Path = Join-Path $env:LOCALAPPDATA 'Logi\LogiPluginService\Applications' }

$installed = Get-InstalledPlugin
$dirs = Find-Profile -Root $Path

$results = foreach ($d in $dirs) { Test-Profile -Dir $d -Installed $installed }
$failed = @($results | Where-Object { -not $_.Ok }).Count

if ($Json) { $results | ConvertTo-Json -Depth 5; exit ([int]($failed -gt 0)) }

Write-Host ""
Write-Host "Logi Options+ profile check" -ForegroundColor Cyan
Write-Host "Source:            $Path"
Write-Host "Profiles found:    $(@($results).Count)"
Write-Host "Plugins installed: $(@($installed).Count)"
Write-Host ""

foreach ($r in $results) {
    if ($Quiet -and $r.Ok -and @($r.Warnings).Count -eq 0) { continue }

    $status, $colour = if (-not $r.Ok) { 'FAIL', 'Red' }
                       elseif (@($r.Warnings).Count -gt 0) { 'WARN', 'Yellow' }
                       else { 'OK  ', 'Green' }

    $device = if ($r.DeviceType -and $KnownDeviceTypes.ContainsKey($r.DeviceType)) { $KnownDeviceTypes[$r.DeviceType] } else { $r.DeviceType }
    Write-Host "[$status] " -ForegroundColor $colour -NoNewline
    Write-Host "$($r.DisplayName)" -NoNewline
    Write-Host "  ($device / $($r.Application), $($r.Slots) assigned)" -ForegroundColor DarkGray

    foreach ($e in $r.Errors)   { Write-Host "        error:   $e" -ForegroundColor Red }
    foreach ($w in $r.Warnings) { Write-Host "        warning: $w" -ForegroundColor Yellow }
    if (@($r.Dependencies).Count -gt 0 -and -not $Quiet) {
        Write-Host "        plugins: $($r.Dependencies -join ', ')" -ForegroundColor DarkGray
    }
}

$warned = @($results | Where-Object { $_.Ok -and @($_.Warnings).Count -gt 0 }).Count
$allMissing = @($results | ForEach-Object { $_.MissingPlugins } | Sort-Object -Unique)

Write-Host ""
Write-Host "$(@($results).Count) checked, $failed failed, $warned with warnings"
if (@($allMissing).Count -gt 0) {
    Write-Host "Missing plugins across all profiles: $($allMissing -join ', ')" -ForegroundColor Yellow
}
Write-Host ""

exit ([int]($failed -gt 0))
