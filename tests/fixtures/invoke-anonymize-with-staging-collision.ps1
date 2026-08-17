[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $AnonymizeScript,
    [Parameter(Mandatory = $true)][string] $Source,
    [Parameter(Mandatory = $true)][string] $Destination
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function New-Item {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)][string[]] $Path,
        [string] $ItemType,
        [switch] $Force
    )

    if ($ItemType -eq 'Directory' -and
        $Path.Count -eq 1 -and
        $Path[0] -match '\.anonymize-staging-[A-Fa-f0-9]{32}$') {
        Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path $Path[0] | Out-Null
        Set-Content -LiteralPath (Join-Path $Path[0] 'keep.txt') -Value 'not-owned' -Encoding ASCII
        throw 'SIMULATED_STAGING_CREATE_COLLISION'
    }

    return Microsoft.PowerShell.Management\New-Item `
        -ItemType $ItemType `
        -Path $Path `
        -Force:$Force
}

. $AnonymizeScript -Path $Source -Destination $Destination -Force
