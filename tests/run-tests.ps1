Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repoRoot 'ApproveForSessionClicker.ps1')

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

$buttons = @(
    [pscustomobject]@{ Name = 'Approve'; IsEnabled = $true; Bounds = [pscustomobject]@{ Left = 100; Top = 100; Width = 60; Height = 30 } },
    [pscustomobject]@{ Name = 'Approve for session'; IsEnabled = $true; Bounds = [pscustomobject]@{ Left = 200; Top = 100; Width = 120; Height = 50 } },
    [pscustomobject]@{ Name = 'Decline'; IsEnabled = $true; Bounds = [pscustomobject]@{ Left = 340; Top = 100; Width = 70; Height = 30 } }
)

$selected = Select-ApproveButtonCandidate -ButtonInfos $buttons
Assert-Equal $selected.Name 'Approve for session' 'Should prefer the exact session approval button.'

$wrappedButtons = @(
    [pscustomobject]@{ Name = 'Approve for sessi'; IsEnabled = $true; Bounds = [pscustomobject]@{ Left = 10; Top = 10; Width = 100; Height = 50 } }
)

$selectedWrapped = Select-ApproveButtonCandidate -ButtonInfos $wrappedButtons
Assert-Equal $selectedWrapped.Name 'Approve for sessi' 'Should accept a visibly wrapped or truncated session approval name.'

$disabledButtons = @(
    [pscustomobject]@{ Name = 'Approve for session'; IsEnabled = $false; Bounds = [pscustomobject]@{ Left = 10; Top = 10; Width = 100; Height = 50 } },
    [pscustomobject]@{ Name = 'Approve for session'; IsEnabled = $true; Bounds = [pscustomobject]@{ Left = -1280; Top = 220; Width = 180; Height = 48 } }
)

$selectedEnabled = Select-ApproveButtonCandidate -ButtonInfos $disabledButtons
Assert-Equal $selectedEnabled.Bounds.Left -1280 'Should ignore disabled approval buttons.'

$center = Get-RectangleCenter -Bounds $selectedEnabled.Bounds
Assert-Equal $center.X -1190 'Should calculate center X correctly on a secondary monitor with negative coordinates.'
Assert-Equal $center.Y 244 'Should calculate center Y correctly.'

$scanClicks = @()
$scanCandidate = [pscustomobject]@{
    Name = 'Approve for session'
    IsEnabled = $true
    Bounds = [pscustomobject]@{ Left = 40; Top = 80; Width = 120; Height = 40 }
}

$scanResult = Invoke-ApproveScanIteration `
    -FindCandidate { $scanCandidate } `
    -ClickCandidate { param($Candidate) $script:scanClicks += $Candidate.Name; return $true }

Assert-Equal $scanResult.Clicked $true 'A scan should click when the session approval button exists.'
Assert-Equal $scanClicks.Count 1 'A scan should send exactly one click for one matching button.'
Assert-Equal $scanClicks[0] 'Approve for session' 'A scan should click the session approval button by button name.'

$noButtonResult = Invoke-ApproveScanIteration `
    -FindCandidate { $null } `
    -ClickCandidate { param($Candidate) $script:scanClicks += $Candidate.Name; return $true }

Assert-Equal $noButtonResult.Clicked $false 'A scan should not click when no session approval button exists.'
Assert-Equal $scanClicks.Count 1 'A scan without a matching button should not add another click.'

$fallbackCandidate = [pscustomobject]@{
    Name = 'Approve for session'
    IsEnabled = $true
    Source = 'ScreenshotLayout'
    Bounds = [pscustomobject]@{ Left = 300; Top = 400; Width = 76; Height = 20 }
}

$fallbackResult = Find-ApproveButtonCandidateWithFallback `
    -UiAutomationFinder { throw 'UI Automation tree changed' } `
    -ScreenshotFinder { $fallbackCandidate }

Assert-Equal $fallbackResult.Source 'ScreenshotLayout' 'UI Automation failures should fall back to screenshot layout detection.'
Assert-Equal $fallbackResult.Bounds.Left 300 'Fallback candidate should be returned when UI Automation throws.'

Add-Type -AssemblyName System.Drawing
$bitmap = New-Object System.Drawing.Bitmap(500, 260)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.Clear([System.Drawing.Color]::Black)
$cardBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(33, 33, 33))
$buttonBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(46, 46, 46))
$graphics.FillRectangle($cardBrush, 80, 40, 370, 180)
foreach ($left in @(110, 196, 282, 368)) {
    $graphics.FillRectangle($buttonBrush, $left, 165, 76, 48)
}

$layoutCandidates = @(Find-ApproveSessionButtonsFromBitmap -Bitmap $bitmap -ScreenLeft -200 -ScreenTop 100)
Assert-Equal $layoutCandidates.Count 1 'Screenshot fallback should find one four-button notification layout.'
Assert-Equal $layoutCandidates[0].Name 'Approve for session' 'Screenshot fallback should target the third button as approve for session.'
Assert-Equal $layoutCandidates[0].Bounds.Left 82 'Screenshot fallback should translate the third button X to screen coordinates.'
Assert-Equal $layoutCandidates[0].Bounds.Top 265 'Screenshot fallback should translate the button Y to screen coordinates.'

$graphics.Dispose()
$cardBrush.Dispose()
$buttonBrush.Dispose()
$bitmap.Dispose()

Write-Host 'All tests passed.'
