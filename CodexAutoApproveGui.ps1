param(
    [switch]$StartMinimized,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $script:AppRoot 'ApproveForSessionClicker.ps1')

function New-IntervalComboItem {
    param([Parameter(Mandatory)][object]$Option)

    [pscustomobject]@{
        Text = [string]$Option.Label
        Seconds = [int]$Option.Seconds
    }
}

function Get-SelectedIntervalSeconds {
    param([Parameter(Mandatory)][object]$ComboBox)

    if ($null -eq $ComboBox.SelectedItem) {
        return 30
    }

    return [int]$ComboBox.SelectedItem.Seconds
}

function Start-CodexAutoApproveGui {
    param([switch]$StartMinimized)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Codex Auto Approve'
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $form.MaximizeBox = $false
    $form.MinimizeBox = $true
    $form.ClientSize = New-Object System.Drawing.Size(420, 230)
    $form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = 'Codex Auto Approve'
    $titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $titleLabel.Location = New-Object System.Drawing.Point(18, 16)
    $titleLabel.Size = New-Object System.Drawing.Size(360, 26)
    $form.Controls.Add($titleLabel)

    $intervalLabel = New-Object System.Windows.Forms.Label
    $intervalLabel.Text = 'Check interval'
    $intervalLabel.Location = New-Object System.Drawing.Point(20, 60)
    $intervalLabel.Size = New-Object System.Drawing.Size(120, 22)
    $form.Controls.Add($intervalLabel)

    $intervalCombo = New-Object System.Windows.Forms.ComboBox
    $intervalCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
    $intervalCombo.Location = New-Object System.Drawing.Point(145, 57)
    $intervalCombo.Size = New-Object System.Drawing.Size(180, 26)
    foreach ($option in Get-ApproveIntervalOptions) {
        [void]$intervalCombo.Items.Add((New-IntervalComboItem -Option $option))
    }
    $intervalCombo.DisplayMember = 'Text'
    $intervalCombo.ValueMember = 'Seconds'
    $intervalCombo.SelectedIndex = 0
    $form.Controls.Add($intervalCombo)

    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Text = 'Stopped'
    $statusLabel.Location = New-Object System.Drawing.Point(20, 103)
    $statusLabel.Size = New-Object System.Drawing.Size(370, 44)
    $form.Controls.Add($statusLabel)

    $startButton = New-Object System.Windows.Forms.Button
    $startButton.Text = 'Start'
    $startButton.Location = New-Object System.Drawing.Point(22, 165)
    $startButton.Size = New-Object System.Drawing.Size(82, 32)
    $form.Controls.Add($startButton)

    $stopButton = New-Object System.Windows.Forms.Button
    $stopButton.Text = 'Stop'
    $stopButton.Enabled = $false
    $stopButton.Location = New-Object System.Drawing.Point(116, 165)
    $stopButton.Size = New-Object System.Drawing.Size(82, 32)
    $form.Controls.Add($stopButton)

    $trayButton = New-Object System.Windows.Forms.Button
    $trayButton.Text = 'Hide to tray'
    $trayButton.Location = New-Object System.Drawing.Point(210, 165)
    $trayButton.Size = New-Object System.Drawing.Size(100, 32)
    $form.Controls.Add($trayButton)

    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Text = 'Exit'
    $exitButton.Location = New-Object System.Drawing.Point(322, 165)
    $exitButton.Size = New-Object System.Drawing.Size(70, 32)
    $form.Controls.Add($exitButton)

    $timer = New-Object System.Windows.Forms.Timer

    $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
    $notifyIcon.Text = 'Codex Auto Approve'
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Shield
    $notifyIcon.Visible = $true

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $showItem = $trayMenu.Items.Add('Show')
    $startItem = $trayMenu.Items.Add('Start')
    $stopItem = $trayMenu.Items.Add('Stop')
    [void]$trayMenu.Items.Add('-')
    $exitItem = $trayMenu.Items.Add('Exit')
    $notifyIcon.ContextMenuStrip = $trayMenu

    $script:isRunning = $false
    $script:allowExit = $false

    $updateUi = {
        $intervalCombo.Enabled = -not $script:isRunning
        $startButton.Enabled = -not $script:isRunning
        $startItem.Enabled = -not $script:isRunning
        $stopButton.Enabled = $script:isRunning
        $stopItem.Enabled = $script:isRunning
    }

    $scanOnce = {
        try {
            $result = Invoke-ApproveScanIteration
            $stamp = Get-Date -Format 'HH:mm:ss'
            if ($result.Clicked) {
                $statusLabel.Text = "Last scan ${stamp}: clicked Approve for session."
                $notifyIcon.Text = 'Codex Auto Approve - clicked'
            } else {
                $statusLabel.Text = "Last scan ${stamp}: no approval notification found."
                $notifyIcon.Text = 'Codex Auto Approve - running'
            }
        } catch {
            $statusLabel.Text = "Last scan error: $($_.Exception.Message)"
            $notifyIcon.Text = 'Codex Auto Approve - scan error'
        }
    }

    $startAction = {
        if ($script:isRunning) {
            return
        }

        $seconds = Get-SelectedIntervalSeconds -ComboBox $intervalCombo
        $timer.Interval = [Math]::Max(1000, $seconds * 1000)
        $script:isRunning = $true
        & $updateUi
        $statusLabel.Text = "Running. Checking every $($intervalCombo.SelectedItem.Text)."
        $timer.Start()
        & $scanOnce
    }

    $stopAction = {
        if (-not $script:isRunning) {
            return
        }

        $timer.Stop()
        $script:isRunning = $false
        $statusLabel.Text = 'Stopped'
        $notifyIcon.Text = 'Codex Auto Approve - stopped'
        & $updateUi
    }

    $showAction = {
        $form.Show()
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $form.Activate()
    }

    $hideAction = {
        $form.Hide()
        $notifyIcon.Visible = $true
    }

    $exitAction = {
        $script:allowExit = $true
        $timer.Stop()
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
        $form.Close()
    }

    $timer.Add_Tick($scanOnce)
    $startButton.Add_Click($startAction)
    $stopButton.Add_Click($stopAction)
    $trayButton.Add_Click($hideAction)
    $exitButton.Add_Click($exitAction)
    $showItem.Add_Click($showAction)
    $startItem.Add_Click($startAction)
    $stopItem.Add_Click($stopAction)
    $exitItem.Add_Click($exitAction)
    $notifyIcon.Add_DoubleClick($showAction)

    $form.Add_Resize({
        if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            & $hideAction
        }
    })

    $form.Add_FormClosing({
        param($Sender, $EventArgs)
        if (-not $script:allowExit -and $script:isRunning) {
            $EventArgs.Cancel = $true
            & $hideAction
        }
    })

    $form.Add_FormClosed({
        $timer.Stop()
        $notifyIcon.Visible = $false
        $notifyIcon.Dispose()
    })

    & $updateUi
    if ($StartMinimized) {
        $form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized
        $form.Add_Shown({ & $hideAction })
    }

    [void][System.Windows.Forms.Application]::Run($form)
}

if ($SelfTest) {
    $options = @(Get-ApproveIntervalOptions)
    if ($options.Count -ne 5 -or $options[0].Seconds -ne 30 -or $options[4].Seconds -ne 3600) {
        throw 'GUI interval options are not valid.'
    }
    Write-Host 'GUI self-test passed.'
    exit 0
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-CodexAutoApproveGui -StartMinimized:$StartMinimized
}
