[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SnapshotScript,

    [Parameter(Mandatory = $true)]
    [string] $Destination,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Corrupt', 'Swap', 'GuardProbe', 'StagingCollision')]
    [string] $Mode,

    [string] $MarkerPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:CopyFaultMode = $Mode
$script:CopyFaultMarker = $MarkerPath

function New-Item {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]] $Path,

        [string] $ItemType,
        [switch] $Force
    )

    if ($script:CopyFaultMode -eq 'StagingCollision' -and
        $ItemType -eq 'Directory' -and
        -not $Force -and
        $Path.Count -eq 1 -and
        $Path[0].EndsWith('.partial', [System.StringComparison]::OrdinalIgnoreCase)) {
        Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path $Path[0] | Out-Null
        Set-Content -LiteralPath (Join-Path $Path[0] 'keep.txt') -Value 'not-owned' -Encoding ASCII
        throw 'SIMULATED_STAGING_CREATE_COLLISION'
    }

    return Microsoft.PowerShell.Management\New-Item `
        -ItemType $ItemType `
        -Path $Path `
        -Force:$Force
}

function Copy-Item {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string[]] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Destination,

        [switch] $Recurse,
        [switch] $Force
    )

    if ($script:CopyFaultMode -eq 'GuardProbe') {
        if ($script:CopyFaultMarker) {
            Set-Content -LiteralPath $script:CopyFaultMarker -Value 'copy-called' -Encoding ASCII
        }
        throw 'COPY_CALLED_BEFORE_CONTAINMENT_GUARD'
    }

    Microsoft.PowerShell.Management\Copy-Item `
        -Path $Path `
        -Destination $Destination `
        -Recurse:$Recurse `
        -Force:$Force

    $copiedFiles = @(Get-ChildItem -LiteralPath $Destination -Recurse -File -Force | Sort-Object FullName)

    if ($script:CopyFaultMode -eq 'Corrupt') {
        if ($copiedFiles.Count -eq 0) { throw 'The copy fault fixture needs at least one copied file.' }
        [System.IO.File]::Delete($copiedFiles[0].FullName)
        return
    }

    if ($script:CopyFaultMode -eq 'Swap') {
        if ($copiedFiles.Count -ne 2) { throw 'The swap fixture needs exactly two copied files.' }

        $firstBytes = [System.IO.File]::ReadAllBytes($copiedFiles[0].FullName)
        $secondBytes = [System.IO.File]::ReadAllBytes($copiedFiles[1].FullName)
        [System.IO.File]::WriteAllBytes($copiedFiles[0].FullName, $secondBytes)
        [System.IO.File]::WriteAllBytes($copiedFiles[1].FullName, $firstBytes)
    }
}

. $SnapshotScript -Destination $Destination

# `exit` from the dot-sourced script returns control to this fixture under
# Windows PowerShell 5.1. Preserve the script's exit status for the parent test.
exit $LASTEXITCODE
