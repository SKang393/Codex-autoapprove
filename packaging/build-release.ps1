param(
    [string]$Version = 'v1.2.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$distRoot = Join-Path $repoRoot 'dist'
$workRoot = Join-Path $distRoot 'work'
$commonFiles = @(
    'ApproveForSessionClicker.ps1',
    'CodexAutoApproveGui.ps1',
    'README.md',
    'RELEASE.md',
    'LICENSE',
    'NOTICE'
)

if (Test-Path $workRoot) {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null

function New-ReleasePackage {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$LauncherFiles
    )

    $packageRoot = Join-Path $workRoot $Name
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    foreach ($file in ($commonFiles + $LauncherFiles)) {
        Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $packageRoot $file) -Force
    }

    $zipPath = Join-Path $distRoot "$Name.zip"
    if (Test-Path $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath
}

New-ReleasePackage -Name "CodexAutoApprove-$Version-wrapped" -LauncherFiles @('Start Codex Auto Approve GUI.vbs')
New-ReleasePackage -Name "CodexAutoApprove-$Version-unwrapped" -LauncherFiles @('Start Codex Auto Approve GUI.cmd', 'Click Approve For Session.cmd')

Remove-Item -LiteralPath $workRoot -Recurse -Force
Write-Host "Created wrapped and unwrapped release packages in $distRoot"
