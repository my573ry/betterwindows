#Requires -Version 5.1
<#
.SYNOPSIS
    BetterWindows - Clean Modern GUI
.DESCRIPTION
    Select tweaks and run them with progress. Self-elevating.
#>

# ---------- Self-Elevation ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    try {
        $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
        Start-Process powershell.exe -ArgumentList $arg -Verb RunAs -ErrorAction Stop
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show("Administrator rights are required.`nPlease run this script as Administrator.", "Elevation Required", "OK", "Warning") | Out-Null
    }
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------- Helpers ----------
function Write-Log {
    param(
        [string]$Message,
        [string]$Color = "Gray"
    )
    $ts = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$ts] $Message`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
    # Also write to the PowerShell console (like Chris Titus Tech)
    try {
        $hostColor = switch ($Color) {
            "Green"  { "Green" }
            "Yellow" { "Yellow" }
            "Red"    { "Red" }
            "Cyan"   { "Cyan" }
            "White"  { "White" }
            default  { "Gray" }
        }
        Write-Host ("[$ts] $Message") -ForegroundColor $hostColor
    } catch {}
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Status {
    param([string]$Text)
    $statusLabel.Text = $Text
    [System.Windows.Forms.Application]::DoEvents()
}

# Runs an external command and streams its output live (keeps UI responsive)
function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [string]$Label
    )
    Write-Log ("  Running: $FilePath $($ArgumentList -join ' ')") -Color "Cyan"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $ArgumentList -join " "
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    while (-not $proc.HasExited) {
        while (-not $proc.StandardOutput.EndOfStream) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line) { Write-Log ("    " + $line.Trim()) }
        }
        while (-not $proc.StandardError.EndOfStream) {
            $line = $proc.StandardError.ReadLine()
            if ($line) { Write-Log ("    " + $line.Trim()) -Color "Yellow" }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }
    # Drain remaining
    $rest = $proc.StandardOutput.ReadToEnd()
    if ($rest) { $rest.Split("`n") | ForEach-Object { if ($_.Trim()) { Write-Log ("    " + $_.Trim()) } } }
    $restErr = $proc.StandardError.ReadToEnd()
    if ($restErr) { $restErr.Split("`n") | ForEach-Object { if ($_.Trim()) { Write-Log ("    " + $_.Trim()) -Color "Yellow" } } }
    Write-Log ("  Finished (exit $($proc.ExitCode))") -Color "Green"
}

function Confirm-Yes {
    param([string]$Msg)
    return ([System.Windows.Forms.MessageBox]::Show($Msg, "Confirm", "YesNo", "Question") -eq "Yes")
}

# Tooltip helper
$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 10000
$toolTip.InitialDelay = 300
$toolTip.ReshowDelay = 100

function Add-ListWithTooltips {
    param(
        [System.Windows.Forms.CheckedListBox]$List,
        [hashtable]$Descriptions
    )
    # Store descriptions on the control so the event handler can always reach them
    $List.Tag = $Descriptions

    $List.Add_MouseMove({
        param($sender, $e)
        if ($null -eq $sender) { return }
        try {
            $descs = $sender.Tag
            if ($null -eq $descs) { return }
            $index = $sender.IndexFromPoint($e.Location)
            if ($index -ge 0 -and $index -lt $sender.Items.Count) {
                $item = $sender.Items[$index].ToString()
                $desc = if ($descs.ContainsKey($item)) { $descs[$item] } else { "" }
                if ($desc) {
                    Set-Status $desc
                    # Show a real tooltip near the cursor
                    $screenPt = $sender.PointToScreen($e.Location)
                    $toolTip.Show($desc, $sender, $e.Location.X + 16, $e.Location.Y + 20, 8000)
                } else {
                    Set-Status "Hover any option for a description"
                    $toolTip.Hide($sender)
                }
            } else {
                Set-Status "Hover any option for a description"
                $toolTip.Hide($sender)
            }
        } catch {}
    })

    $List.Add_MouseLeave({
        param($sender, $e)
        Set-Status "Hover any option for a description"
        if ($null -ne $sender) { $toolTip.Hide($sender) }
    })
}

# ---------- Colors (Black + Windows 11 Blue accents, white text) ----------
$bgBlack   = [System.Drawing.Color]::FromArgb(0, 0, 0)
$bgPanel   = [System.Drawing.Color]::FromArgb(18, 18, 18)
$accentBlue = [System.Drawing.Color]::FromArgb(0, 120, 212)   # Windows 11 blue
$textWhite = [System.Drawing.Color]::FromArgb(255, 255, 255)
$textGray  = [System.Drawing.Color]::FromArgb(180, 180, 180)

# ---------- Main Form ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "BetterWindows"
$form.Size = New-Object System.Drawing.Size(1100, 800)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false
$form.BackColor = $bgBlack
$form.ForeColor = $textWhite
$form.Font = New-Object System.Drawing.Font("Segoe UI", 12)

# TableLayoutPanel for reliable layout (Header / Tabs / Bottom)
$table = New-Object System.Windows.Forms.TableLayoutPanel
$table.Dock = "Fill"
$table.RowCount = 3
$table.ColumnCount = 1
$table.BackColor = $bgBlack
$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 60)))
$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$table.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 190)))
$form.Controls.Add($table)

# Header
$header = New-Object System.Windows.Forms.Label
$header.Text = "BetterWindows"
$header.Font = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold)
$header.ForeColor = $textWhite
$header.Dock = "Fill"
$header.TextAlign = "MiddleLeft"
$header.Padding = New-Object System.Windows.Forms.Padding(16, 0, 0, 0)
$table.Controls.Add($header, 0, 0)

# TabControl (middle row)
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$tabControl.Padding = New-Object System.Drawing.Point(8, 4)
$table.Controls.Add($tabControl, 0, 1)

# Bottom panel (status + progress + log)
$bottomPanel = New-Object System.Windows.Forms.Panel
$bottomPanel.Dock = "Fill"
$bottomPanel.BackColor = $bgBlack
$table.Controls.Add($bottomPanel, 0, 2)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = "Top"
$progressBar.Height = 8
$progressBar.Style = "Continuous"
$bottomPanel.Controls.Add($progressBar)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Hover any option to see its description"
$statusLabel.Dock = "Top"
$statusLabel.Height = 36
$statusLabel.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
$statusLabel.ForeColor = $textWhite
$statusLabel.TextAlign = "MiddleLeft"
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(14, 0, 0, 0)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$bottomPanel.Controls.Add($statusLabel)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.Dock = "Fill"
$logBox.BackColor = [System.Drawing.Color]::FromArgb(12, 12, 12)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$logBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$logBox.BorderStyle = "None"
$bottomPanel.Controls.Add($logBox)

# ---------- Shared Run Engine ----------
function Invoke-Selected {
    param(
        [System.Windows.Forms.CheckedListBox]$List,
        [hashtable]$Actions
    )
    $selected = @()
    for ($i = 0; $i -lt $List.Items.Count; $i++) {
        if ($List.GetItemChecked($i)) { $selected += $List.Items[$i] }
    }
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one item.", "Nothing Selected") | Out-Null
        return
    }

    $cleanupItems = @("Empty Recycle Bin", "Clean Temporary Files", "Clear Thumbnail Cache", "Clear Prefetch Cache", "Clear Windows Update Download Cache")
    $needsWarn = $false
    foreach ($item in $selected) {
        if ($cleanupItems -contains $item) { $needsWarn = $true; break }
    }
    if ($needsWarn) {
        $msg = "Some selected cleanup options permanently delete data (Recycle Bin, temp files, caches).`n`nContinue?"
        if (-not (Confirm-Yes $msg)) { return }
    }

    $progressBar.Value = 0
    $progressBar.Maximum = $selected.Count
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Host "  BetterWindows - Running Tasks" -ForegroundColor Cyan
    Write-Host "===========================================" -ForegroundColor Cyan
    Write-Log ("===== Starting " + $selected.Count + " selected item(s) =====") -Color "Cyan"

    $i = 0
    foreach ($name in $selected) {
        $i++
        Set-Status ("Running ($i/$($selected.Count)): $name")
        Write-Host ""
        Write-Host ("[$i/$($selected.Count)] $name") -ForegroundColor Yellow
        Write-Log ("-> $name") -Color "Yellow"
        try {
            if ($Actions.ContainsKey($name)) {
                & $Actions[$name]
                Write-Log "  Done" -Color "Green"
            } else {
                Write-Log "  No action defined" -Color "Red"
            }
        }
        catch {
            Write-Log ("  Error: " + $_.Exception.Message) -Color "Red"
        }
        $progressBar.Value = $i
        [System.Windows.Forms.Application]::DoEvents()
    }

    $progressBar.Value = $progressBar.Maximum
    Set-Status "Finished"
    Write-Host ""
    Write-Host "===========================================" -ForegroundColor Green
    Write-Host "  All selected items finished" -ForegroundColor Green
    Write-Host "===========================================" -ForegroundColor Green
    Write-Log "===== All selected items finished =====" -Color "Green"
    $form.Cursor = [System.Windows.Forms.Cursors]::Default
    [System.Windows.Forms.MessageBox]::Show("Selected items completed.`nSome changes may require a reboot.", "Done") | Out-Null
}

# ========== TAB 1: System Maintenance ==========
$tabMaint = New-Object System.Windows.Forms.TabPage
$tabMaint.Text = "System Maintenance"
$tabMaint.BackColor = $bgBlack
$tabControl.Controls.Add($tabMaint)

$maintList = New-Object System.Windows.Forms.CheckedListBox
$maintList.Dock = "Fill"
$maintList.CheckOnClick = $true
$maintList.BackColor = $bgPanel
$maintList.ForeColor = $textWhite
$maintList.Font = New-Object System.Drawing.Font("Segoe UI", 11.5)
$maintList.BorderStyle = "None"
$maintList.ItemHeight = 32
$maintItems = @(
    'System File Checker (SFC /scannow)',
    'DISM Image Repair (RestoreHealth)',
    'Windows Component Store Cleanup',
    'Optimize All Drives (TRIM / Defrag)'
)
$maintItems | ForEach-Object { [void]$maintList.Items.Add($_) }
$tabMaint.Controls.Add($maintList)

$btnMaint = New-Object System.Windows.Forms.Button
$btnMaint.Text = "Run Selected"
$btnMaint.Dock = "Bottom"
$btnMaint.Height = 54
$btnMaint.BackColor = $accentBlue
$btnMaint.ForeColor = $textWhite
$btnMaint.FlatStyle = "Flat"
$btnMaint.FlatAppearance.BorderSize = 0
$btnMaint.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$tabMaint.Controls.Add($btnMaint)

$maintDescriptions = @{
    'System File Checker (SFC /scannow)' = 'Scans and repairs protected Windows system files. Safe to run regularly.'
    'DISM Image Repair (RestoreHealth)' = 'Repairs the Windows component store and system image. Fixes many update and corruption issues.'
    'Windows Component Store Cleanup' = 'Removes superseded components after updates to free space (DISM /StartComponentCleanup /ResetBase).'
    'Optimize All Drives (TRIM / Defrag)' = 'Runs the correct optimize command for every fixed drive (TRIM for SSDs, defrag for HDDs).'
}
Add-ListWithTooltips $maintList $maintDescriptions

$maintActions = @{
    'System File Checker (SFC /scannow)' = { Invoke-External "sfc" @("/scannow") }
    'DISM Image Repair (RestoreHealth)' = { Invoke-External "DISM" @("/Online","/Cleanup-Image","/RestoreHealth") }
    'Windows Component Store Cleanup' = { Invoke-External "DISM" @("/Online","/Cleanup-Image","/StartComponentCleanup","/ResetBase") }
    'Optimize All Drives (TRIM / Defrag)' = {
        Get-Volume | Where-Object DriveType -eq 'Fixed' | ForEach-Object {
            Write-Log ("  Optimizing " + $_.DriveLetter + ":") -Color "Cyan"
            Invoke-External "defrag" @(($_.DriveLetter + ":"), "/O", "/U", "/V")
        }
    }
}
$btnMaint.Add_Click({ Invoke-Selected $maintList $maintActions })

# ========== TAB 2: Windows Cleanup ==========
$tabClean = New-Object System.Windows.Forms.TabPage
$tabClean.Text = "Windows Cleanup"
$tabClean.BackColor = $bgBlack
$tabControl.Controls.Add($tabClean)

$cleanList = New-Object System.Windows.Forms.CheckedListBox
$cleanList.Dock = "Fill"
$cleanList.CheckOnClick = $true
$cleanList.BackColor = $bgPanel
$cleanList.ForeColor = $textWhite
$cleanList.Font = New-Object System.Drawing.Font("Segoe UI", 11.5)
$cleanList.BorderStyle = "None"
$cleanList.ItemHeight = 32
$cleanItems = @(
    'Clean Temporary Files',
    'Empty Recycle Bin',
    'Clear Thumbnail Cache',
    'Clear Prefetch Cache',
    'Clear Windows Update Download Cache',
    'Run Disk Cleanup Utility',
    'Clear Delivery Optimization Cache',
    'Flush DNS Cache'
)
$cleanItems | ForEach-Object { [void]$cleanList.Items.Add($_) }
$tabClean.Controls.Add($cleanList)

$btnClean = New-Object System.Windows.Forms.Button
$btnClean.Text = "Run Selected"
$btnClean.Dock = "Bottom"
$btnClean.Height = 54
$btnClean.BackColor = $accentBlue
$btnClean.ForeColor = $textWhite
$btnClean.FlatStyle = "Flat"
$btnClean.FlatAppearance.BorderSize = 0
$btnClean.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$tabClean.Controls.Add($btnClean)

$cleanDescriptions = @{
    'Clean Temporary Files' = 'Deletes files from user and Windows Temp folders. Safe. Files are recreated as needed.'
    'Empty Recycle Bin' = 'Permanently deletes everything currently in the Recycle Bin.'
    'Clear Thumbnail Cache' = 'Removes stored folder thumbnail images. Windows rebuilds them automatically.'
    'Clear Prefetch Cache' = 'Deletes Prefetch files used to speed up app launches. Windows rebuilds them.'
    'Clear Windows Update Download Cache' = 'Removes downloaded update files. Can free significant space after updates.'
    'Run Disk Cleanup Utility' = 'Opens the classic Disk Cleanup tool for Drive C:.'
    'Clear Delivery Optimization Cache' = 'Deletes Delivery Optimization download cache (peer-to-peer update files).'
    'Flush DNS Cache' = 'Clears the local DNS resolver cache (ipconfig /flushdns).'
}
Add-ListWithTooltips $cleanList $cleanDescriptions

$cleanActions = @{
    'Clean Temporary Files' = {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    'Empty Recycle Bin' = { Clear-RecycleBin -Force -ErrorAction SilentlyContinue }
    'Clear Thumbnail Cache' = { Remove-Item "$env:LocalAppData\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue }
    'Clear Prefetch Cache' = { Remove-Item "C:\Windows\Prefetch\*" -Force -ErrorAction SilentlyContinue }
    'Clear Windows Update Download Cache' = {
        Invoke-External 'net' @('stop','wuauserv')
        Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
        Invoke-External 'net' @('start','wuauserv')
    }
    'Run Disk Cleanup Utility' = { Invoke-External 'cleanmgr.exe' @('/d','C:') }
    'Clear Delivery Optimization Cache' = { Remove-Item "C:\Windows\SoftwareDistribution\DeliveryOptimization\*" -Recurse -Force -ErrorAction SilentlyContinue }
    'Flush DNS Cache' = { ipconfig /flushdns | Out-Null }
}
$btnClean.Add_Click({ Invoke-Selected $cleanList $cleanActions })

# ========== TAB 3: Standard Tweaks ==========
$tabStd = New-Object System.Windows.Forms.TabPage
$tabStd.Text = "Standard Tweaks"
$tabStd.BackColor = $bgBlack
$tabControl.Controls.Add($tabStd)

$stdList = New-Object System.Windows.Forms.CheckedListBox
$stdList.Dock = "Fill"
$stdList.CheckOnClick = $true
$stdList.BackColor = $bgPanel
$stdList.ForeColor = $textWhite
$stdList.Font = New-Object System.Drawing.Font("Segoe UI", 11.5)
$stdList.BorderStyle = "None"
$stdList.ItemHeight = 32
$stdItems = @(
    'Disable Activity History',
    'Disable Consumer Features',
    'Disable Delivery Optimization',
    'Disable Fast Startup',
    'Disable GameDVR',
    'Disable Location Tracking',
    'Disable Startup Delay',
    'Disable Telemetry',
    'Disable Windows Tips and Suggestions',
    'Disable WPBT',
    'Enable End Task on Taskbar',
    'Remove Temporary Files',
    'Set Services to Manual'
)
$stdItems | ForEach-Object { [void]$stdList.Items.Add($_) }
$tabStd.Controls.Add($stdList)

$btnStd = New-Object System.Windows.Forms.Button
$btnStd.Text = "Run Selected"
$btnStd.Dock = "Bottom"
$btnStd.Height = 54
$btnStd.BackColor = $accentBlue
$btnStd.ForeColor = $textWhite
$btnStd.FlatStyle = "Flat"
$btnStd.FlatAppearance.BorderSize = 0
$btnStd.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$tabStd.Controls.Add($btnStd)

$stdDescriptions = @{
    'Disable Activity History' = 'Stops Windows from publishing or uploading user activities. Low-risk privacy improvement. Clipboard history is preserved.'
    'Disable Consumer Features' = 'Stops promoted app installs and reduces Microsoft Store suggestions.'
    'Disable Delivery Optimization' = 'Stops Windows from using your bandwidth to upload updates to other PCs.'
    'Disable Fast Startup' = 'Disables Fast Startup so shutdowns are full and clean. Helps with driver stability (especially GPU).'
    'Disable GameDVR' = 'Disables Xbox GameDVR and background recording. Can improve frame times and reduce overhead.'
    'Disable Location Tracking' = 'Disables the location service and related tracking.'
    'Disable Startup Delay' = 'Removes the artificial delay before startup apps launch after login.'
    'Disable Telemetry' = 'Disables Microsoft diagnostic data collection, error reporting, and related services.'
    'Disable Windows Tips and Suggestions' = 'Stops Windows tips, suggestions, and promotional notifications.'
    'Disable WPBT' = 'Disables Windows Platform Binary Table (prevents certain firmware-level executions).'
    'Enable End Task on Taskbar' = 'Adds an End Task option when right-clicking a taskbar icon.'
    'Remove Temporary Files' = 'Deletes temporary files from user and Windows Temp folders.'
    'Set Services to Manual' = 'Sets several non-essential services to Manual startup to reduce background load.'
}
Add-ListWithTooltips $stdList $stdDescriptions

$stdActions = @{
    'Disable Activity History' = {
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "EnableActivityFeed" -Value 1 -Type DWord
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "PublishUserActivities" -Value 0 -Type DWord
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "UploadUserActivities" -Value 0 -Type DWord
    }
    'Disable Consumer Features' = {
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord
    }
    'Disable Delivery Optimization' = {
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0 -Type DWord
    }
    'Enable End Task on Taskbar' = {
        New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name "TaskbarEndTask" -Value 1 -Type DWord
    }
    'Disable Location Tracking' = {
        Stop-Service lfsvc -Force -ErrorAction SilentlyContinue
        Set-Service lfsvc -StartupType Disabled -ErrorAction SilentlyContinue
    }
    'Set Services to Manual' = {
        @("DiagTrack","dmwappushservice","MapsBroker","lfsvc","SharedAccess","WSearch","SysMain","WMPNetworkSvc") | ForEach-Object {
            if (Get-Service $_ -ErrorAction SilentlyContinue) { Set-Service $_ -StartupType Manual -ErrorAction SilentlyContinue }
        }
    }
    'Disable Telemetry' = {
        Stop-Service diagtrack -Force -ErrorAction SilentlyContinue
        Set-Service diagtrack -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service WerSvc -Force -ErrorAction SilentlyContinue
        Set-Service WerSvc -StartupType Disabled -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable("POWERSHELL_TELEMETRY_OPTOUT", "1", "Machine")
    }
    'Remove Temporary Files' = {
        Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    'Disable WPBT' = {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "DisableWpbtExecution" -Value 1 -Type DWord
    }
    'Disable Fast Startup' = {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    'Disable GameDVR' = {
        New-Item "HKCU:\System\GameConfigStore" -Force | Out-Null
        Set-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWord
        Set-ItemProperty "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehavior" -Value 2 -Type DWord
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -Type DWord
    }
    'Disable Startup Delay' = {
        New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0 -Type DWord
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "WaitForIdleState" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    'Disable Windows Tips and Suggestions' = {
        New-Item "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Force | Out-Null
        Set-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SubscribedContent-338389Enabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableSoftLanding" -Value 1 -Type DWord -ErrorAction SilentlyContinue
    }
}
$btnStd.Add_Click({ Invoke-Selected $stdList $stdActions })

# ========== TAB 4: Advanced Tweaks ==========
$tabAdv = New-Object System.Windows.Forms.TabPage
$tabAdv.Text = "Advanced Tweaks"
$tabAdv.BackColor = $bgBlack
$tabControl.Controls.Add($tabAdv)

$advList = New-Object System.Windows.Forms.CheckedListBox
$advList.Dock = "Fill"
$advList.CheckOnClick = $true
$advList.BackColor = $bgPanel
$advList.ForeColor = $textWhite
$advList.Font = New-Object System.Drawing.Font("Segoe UI", 11.5)
$advList.BorderStyle = "None"
$advList.ItemHeight = 32
$advItems = @(
    'Block Logitech Download Assistant',
    'Debloat Brave Browser',
    'Debloat Microsoft Edge',
    'Disable and Remove Windows AI',
    'Disable Background Apps',
    'Disable File Explorer Home and Gallery',
    'Disable Hibernation',
    'Disable News and Interests / Widgets',
    'Disable Razer Software Auto-Install',
    'Disable Storage Sense',
    'Disable System Tray Notifications and Calendar',
    'Enable Hibernation',
    'Remove Microsoft Edge',
    'Remove Microsoft OneDrive',
    'Restore Classic Right-Click Menu',
    'Set Visual Effects to Best Performance'
)
$advItems | ForEach-Object { [void]$advList.Items.Add($_) }
$tabAdv.Controls.Add($advList)

$btnAdv = New-Object System.Windows.Forms.Button
$btnAdv.Text = "Run Selected"
$btnAdv.Dock = "Bottom"
$btnAdv.Height = 54
$btnAdv.BackColor = $accentBlue
$btnAdv.ForeColor = $textWhite
$btnAdv.FlatStyle = "Flat"
$btnAdv.FlatAppearance.BorderSize = 0
$btnAdv.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$tabAdv.Controls.Add($btnAdv)

$advDescriptions = @{
    'Block Logitech Download Assistant' = 'Prevents Logitech Download Assistant from installing automatically.'
    'Debloat Brave Browser' = 'Disables Brave Rewards, Wallet, VPN, News, and other optional features via policy.'
    'Debloat Microsoft Edge' = 'Disables Edge telemetry, first-run experience, and recommendations via policy.'
    'Disable and Remove Windows AI' = 'Full AI cleanup: removes AI Appx packages, disables Copilot/Recall/Input Insights/Voice Access/Paint/Notepad/Edge AI, hides AI Components, removes Recall tasks and leftover AI files.'
    'Disable Background Apps' = 'Prevents apps from running in the background.'
    'Disable File Explorer Home and Gallery' = 'Removes the Home and Gallery entries from File Explorer.'
    'Disable Hibernation' = 'Turns off hibernation and deletes hiberfil.sys to free disk space.'
    'Disable News and Interests / Widgets' = 'Disables the News and Interests / Widgets feed on the taskbar.'
    'Disable Razer Software Auto-Install' = 'Blocks automatic installation of Razer software.'
    'Disable Storage Sense' = 'Turns off automatic Storage Sense cleanup.'
    'Disable System Tray Notifications and Calendar' = 'Disables notification center and calendar pop-ups.'
    'Enable Hibernation' = 'Re-enables hibernation if you previously disabled it.'
    'Remove Microsoft Edge' = 'Attempts a full uninstall of Microsoft Edge.'
    'Remove Microsoft OneDrive' = 'Uninstalls Microsoft OneDrive. Local files remain.'
    'Restore Classic Right-Click Menu' = 'Restores the full classic right-click context menu in Windows 11.'
    'Set Visual Effects to Best Performance' = 'Disables most visual effects for lower resource use.'
}
Add-ListWithTooltips $advList $advDescriptions

$advActions = @{
    'Enable Adobe URL Block List' = {
        $hosts = Invoke-RestMethod "https://github.com/Ruddernation-Designs/Adobe-URL-Block-List/raw/refs/heads/master/hosts" -ErrorAction Stop
        Add-Content "$env:SystemRoot\System32\drivers\etc\hosts" $hosts
        ipconfig /flushdns | Out-Null
    }
    'Disable Background Apps' = {
        New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -Type DWord
    }
    'Debloat Brave Browser' = {
        $p = "HKLM:\SOFTWARE\Policies\BraveSoftware\Brave"
        New-Item $p -Force | Out-Null
        @("BraveRewardsDisabled","BraveWalletDisabled","BraveVPNDisabled","BraveNewsDisabled","BraveTalkDisabled","TorDisabled") | ForEach-Object { Set-ItemProperty $p -Name $_ -Value 1 -Type DWord }
        @("BraveAIChatEnabled","BraveStatsPingEnabled","BraveP3AEnabled") | ForEach-Object { Set-ItemProperty $p -Name $_ -Value 0 -Type DWord }
    }
    'Set Date and Time to UTC' = {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation" -Name "RealTimeIsUniversal" -Value 1 -Type QWord
    }
    'Disable Reserved Storage' = { DISM /Online /Set-ReservedStorageState /State:Disabled }
    'Disable File Explorer Home and Gallery' = {
        New-Item "HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord
        New-Item "HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" -Name "System.IsPinnedToNameSpaceTree" -Value 0 -Type DWord
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1 -Type DWord
    }
    'Disable IPv6' = {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 255 -Type DWord
        Disable-NetAdapterBinding -Name * -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
    }
    'Prefer IPv4 over IPv6' = {
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 32 -Type DWord
    }
    'Block Logitech Download Assistant' = {
        Stop-Process -Name "logi_download_assistant" -Force -ErrorAction SilentlyContinue
        $path = "$env:ProgramW6432\LogiDownloadAssistant"
        if (-not (Test-Path $path)) { New-Item $path -ItemType Directory -Force | Out-Null }
        icacls $path /deny "*S-1-1-0:(W)" | Out-Null
    }
    'Debloat Microsoft Edge' = {
        $e = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        New-Item $e -Force | Out-Null
        Set-ItemProperty $e -Name "PersonalizationReportingEnabled" -Value 0 -Type DWord
        Set-ItemProperty $e -Name "ShowRecommendationsEnabled" -Value 0 -Type DWord
        Set-ItemProperty $e -Name "HideFirstRunExperience" -Value 1 -Type DWord
        Set-ItemProperty $e -Name "UserFeedbackAllowed" -Value 0 -Type DWord
        Set-ItemProperty $e -Name "DiagnosticData" -Value 0 -Type DWord
    }
    'Remove Microsoft Edge' = {
        $edgeDir = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
        $setup = Get-ChildItem "$edgeDir\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -Last 1
        if ($setup) { Start-Process $setup.FullName -ArgumentList "--uninstall --system-level --force-uninstall --delete-profile" -Wait }
    }
    'Remove Microsoft OneDrive' = {
        Start-Process "$env:SystemRoot\System32\OneDriveSetup.exe" -ArgumentList "/uninstall" -Wait -ErrorAction SilentlyContinue
    }
    'Disable Razer Software Auto-Install' = {
        $path = "$env:SystemRoot\Installer\Razer"
        if (-not (Test-Path $path)) { New-Item $path -ItemType Directory -Force | Out-Null }
        icacls $path /deny "*S-1-1-0:(W)" | Out-Null
    }
    'Disable RDP Unsigned File Warnings' = {
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services\Client" -Name "RedirectionWarningDialogVersion" -Value 1 -Type DWord
    }
    'Restore Classic Right-Click Menu' = {
        New-Item "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" -Force | Out-Null
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }
    'Disable Storage Sense' = {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    'Disable svchost.exe Splitting' = {
        $mem = (Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Value $mem -Type DWord
    }
    'Disable System Tray Notifications and Calendar' = {
        New-Item "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableNotificationCenter" -Value 1 -Type DWord
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 0 -Type DWord
    }
    'Disable Teredo' = {
        netsh interface teredo set state disabled
        Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -Name "DisabledComponents" -Value 1 -Type DWord
    }
    'Set Visual Effects to Best Performance' = {
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "DragFullWindows" -Value "0" -Type String
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "200" -Type String
    }
    'Disable and Remove Windows AI' = {
        Write-Log "  Removing AI Appx packages..." -Color "Cyan"
        $aiPatterns = @(
            '*Copilot*',
            '*MicrosoftWindows.Client.AIX*',
            '*MicrosoftWindows.Client.CoPilot*',
            '*Microsoft.Windows.Ai.Copilot.Provider*',
            '*Microsoft.Copilot*',
            '*MicrosoftWindows.Client.CoreAI*',
            '*Microsoft.Edge.GameAssist*',
            '*Microsoft.Office.ActionsServer*',
            '*aimgr*',
            '*Microsoft.WritingAssistant*',
            '*Clipchamp.Clipchamp*',
            '*WindowsWorkload.Data.Analysis*',
            '*WindowsWorkload.Manager.*',
            '*WindowsWorkload.PSOnnxRuntime*',
            '*WindowsWorkload.SemanticText*',
            '*WindowsWorkload.ImageSearch*',
            '*WindowsWorkload.TextRecognition*',
            '*WindowsWorkload.LanguageModel*',
            '*WindowsWorkload.SessionManager*',
            '*WindowsWorkload.TextContentModeration*',
            '*WindowsWorkload.WinMLShared*',
            '*MicrosoftCorporationII.WinML*'
        )
        $removed = 0
        foreach ($pattern in $aiPatterns) {
            $pkgs = Get-AppxPackage -AllUsers $pattern -ErrorAction SilentlyContinue
            foreach ($pkg in $pkgs) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    Write-Log "    Removed: $($pkg.Name)" -Color "Green"
                    $removed++
                } catch {
                    Write-Log "    Could not remove: $($pkg.Name)" -Color "Yellow"
                }
            }
            $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $pattern }
            foreach ($p in $prov) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $p.PackageName -ErrorAction Stop | Out-Null
                    Write-Log "    Deprovisioned: $($p.DisplayName)" -Color "Green"
                } catch {}
            }
        }
        Write-Log "  Removed $removed AI packages." -Color "Green"

        Write-Log "  Disabling AI registry keys..." -Color "Cyan"
        # Notepad AI
        New-Item "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\WindowsNotepad" -Name "DisableAIFeatures" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        # Paint AI
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint" -Name "DisableImageCreator" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Paint" -Name "DisableAIFeatures" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        # Copilot / Recall style policies
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        New-Item "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        # Edge Copilot
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "HubsSidebarEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "CopilotEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Name "AIFeaturesEnabled" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        # Input Insights / typing data
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization" -Name "AllowInputPersonalization" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        New-Item "HKCU:\Software\Microsoft\InputPersonalization" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitTextCollection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty "HKCU:\Software\Microsoft\InputPersonalization" -Name "RestrictImplicitInkCollection" -Value 1 -Type DWord -ErrorAction SilentlyContinue
        # Voice Access / AI Voice
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Speech" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Speech" -Name "AllowSpeechModelUpdate" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        # AI Fabric service
        if (Get-Service WSAIFabricSvc -ErrorAction SilentlyContinue) {
            Set-Service WSAIFabricSvc -StartupType Disabled -ErrorAction SilentlyContinue
            Stop-Service WSAIFabricSvc -Force -ErrorAction SilentlyContinue
            Write-Log "  Disabled AI Fabric service." -Color "Green"
        }
        # Hide AI Components in Settings
        New-Item "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "SettingsPageVisibility" -Value "hide:aicomponents" -Type String -ErrorAction SilentlyContinue

        Write-Log "  Removing Recall scheduled tasks..." -Color "Cyan"
        Get-ScheduledTask | Where-Object { $_.TaskName -like "*Recall*" -or $_.TaskName -like "*CoreAI*" } | ForEach-Object {
            try {
                Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction Stop
                Write-Log "    Removed task: $($_.TaskName)" -Color "Green"
            } catch {
                Write-Log "    Could not remove task: $($_.TaskName)" -Color "Yellow"
            }
        }

        Write-Log "  Cleaning leftover AI files..." -Color "Cyan"
        $aiPaths = @(
            "$env:LOCALAPPDATA\CoreAIPlatform*",
            "$env:LOCALAPPDATA\Packages\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\LocalState",
            "$env:OneDrive\Microsoft Copilot Chat Files"
        )
        foreach ($p in $aiPaths) {
            if (Test-Path $p) {
                Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "    Cleaned: $p" -Color "Green"
            }
        }

        # Disable Recall optional feature if present
        try {
            $recall = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
            if ($recall -and $recall.State -eq "Enabled") {
                Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction SilentlyContinue | Out-Null
                Write-Log "  Disabled Recall optional feature." -Color "Green"
            }
        } catch {}

        Write-Log "  AI disable complete. Restart recommended." -Color "Green"
    }
    'Disable Hibernation' = { powercfg -h off }
    'Enable Hibernation' = { powercfg -h on }
    'Reset Winsock Catalog' = { netsh winsock reset }
    'Disable News and Interests / Widgets' = {
        New-Item "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Force | Out-Null
        Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0 -Type DWord -ErrorAction SilentlyContinue
        New-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Force | Out-Null
        Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds" -Name "ShellFeedsTaskbarViewMode" -Value 2 -Type DWord -ErrorAction SilentlyContinue
    }
}

$btnAdv.Add_Click({
    $msg = "Advanced Tweaks make deeper system changes.`nCreate a restore point first if you have not already.`n`nContinue?"
    if (-not (Confirm-Yes $msg)) { return }
    Invoke-Selected $advList $advActions
})


# ========== TAB: Power Plan ==========
$tabPower = New-Object System.Windows.Forms.TabPage
$tabPower.Text = "Power Plan"
$tabPower.BackColor = $bgBlack
$tabControl.Controls.Add($tabPower)

$powerList = New-Object System.Windows.Forms.CheckedListBox
$powerList.Dock = "Fill"
$powerList.CheckOnClick = $true
$powerList.BackColor = $bgPanel
$powerList.ForeColor = $textWhite
$powerList.Font = New-Object System.Drawing.Font("Segoe UI", 11.5)
$powerList.BorderStyle = "None"
$powerList.ItemHeight = 32
$powerItems = @(
    'Import and Enable Atlas Power Scheme',
    'Remove Atlas Power Scheme'
)
$powerItems | ForEach-Object { [void]$powerList.Items.Add($_) }
$tabPower.Controls.Add($powerList)

$btnPower = New-Object System.Windows.Forms.Button
$btnPower.Text = "Run Selected"
$btnPower.Dock = "Bottom"
$btnPower.Height = 54
$btnPower.BackColor = $accentBlue
$btnPower.ForeColor = $textWhite
$btnPower.FlatStyle = "Flat"
$btnPower.FlatAppearance.BorderSize = 0
$btnPower.Font = New-Object System.Drawing.Font("Segoe UI", 13.5, [System.Drawing.FontStyle]::Bold)
$tabPower.Controls.Add($btnPower)

$powerDescriptions = @{
    'Import and Enable Atlas Power Scheme' = 'Imports the embedded Atlas Power Scheme and sets it as the active power plan. Latency-oriented plan used by Atlas OS.'
    'Remove Atlas Power Scheme' = 'Deletes the Atlas Power Scheme if it is installed. Falls back to Balanced if it was active.'
}
Add-ListWithTooltips $powerList $powerDescriptions

$atlasPowBase64 = @'
cmVnZgEAAAABAAAANTyw3kBv3QEBAAAAAwAAAAAAAAABAAAAIAAAAAAgAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANZn6y8y2/ERmkHaO+1ddGLWZ+svMtvxEZpB2jvtXXRiAAAAANdn6y8y2/ERmkHaO+1ddGJybXRtAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAMXbyrMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGhiaW4AAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAiP///25rLAC2CAuuwMvcAQAAAAD/////BQAAAAAAAAAQEwAA/////wIAAAAIAwAAmAAAAP////9IAAAAAAAAABgAAAB4AAAAAAAAACQAAAAxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEAAAAAGP///3NrAAAABQAAAAUAAAQAAADQAAAAAQAEiLgAAADEAAAAAAAAABQAAAACAKQABwAAAAAQGAAZAAIAAQIAAAAAAAUgAAAAIQIAAAAaGAAAAACAAQIAAAAAAAUgAAAAIQIAAAAQGAAZAAIAAQIAAAAAAAUgAAAAIAIAAAAaGAAAAACAAQIAAAAAAAUgAAAAIAIAAAAQFAA/AA8AAQEAAAAAAAUSAAAAABoUAAAAABABAQAAAAAABRIAAAAAGhQAAAAAgAEBAAAAAAADAAAAAAEBAAAAAAAFEgAAAAEBAAAAAAAFEgAAANj///92awsAeAAAAKgBAAACAAAAAQBqAERlc2NyaXB0aW9uAIgoagBI////UABvAHcAZQByACAAcwBjAGgAZQBtAGUAIABvAHAAdABpAG0AaQB6AGUAZAAgAGYAbwByACAAbwBwAHQAaQBtAGEAbAAgAGwAYQB0AGUAbgBjAHkAIABhAG4AZAAgAHAAZQByAGYAbwByAG0AYQBuAGMAZQAuAAAAcgBmAG8AcgBtAGEAbgBjAGUAIABvAG4AIABoAGkAZwBoAGUAcgAgAGUAbgBkACAAUABDAHMALgAAAEQA2P///3ZrDAAmAAAAiAIAAAIAAAABAHQARnJpZW5kbHlOYW1ldQBuAID///9BAHQAbABhAHMAIABQAG8AdwBlAHIAIABTAGMAaABlAG0AZQAAAG0AMwAyAFwAcABvAHcAcgBwAHIAbwBmAC4AZABsAGwALAAtADEAOQAsAFUAbAB0AGkAbQBhAHQAZQAgAFAAZQByAGYAbwByAG0AYQBuAGMAZQAAAC0A8P///4ABAABgAgAAAAAAAIj///9uayAArZYGrsDL3AEAAAAAIAAAAAQAAAAAAAAAuAYAAP////8AAAAA/////5gAAAD/////SAAAAAAAAAAAAAAAAAAAAAAAAAAkAAAAMDAxMmVlNDctOTA0MS00YjVkLTliNzctNTM1ZmJhOGIxNDQyAAAAAPD///84CAAAYAgAADAwMTKI////bmsgAAfM+a3Ay9wBAAAAABgDAAAAAAAAAAAAAP//////////AgAAAHgEAACYAAAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAADY3MzhlMmM0LWU4YTUtNGE0Mi1iMTZhLWUwNDBlNzY5NzU2ZQAAAAD4////GAYAAPj////gBgAA2P///3ZrDgAEAACAAAAAAAQAAAABABu2QUNTZXR0aW5nSW5kZXhAadj///92aw4ABAAAgAAAAAAEAAAAAQBpAERDU2V0dGluZ0luZGV4CwDw////KAQAAFAEAAAAAAAAiP///25rIACtlgauwMvcAQAAAAAYAwAAAAAAAAAAAAD//////////wEAAAAYBAAAAAUAAP////8AAAAAAAAAABwAAAAEAAAAAAAAACQAAABkM2Q1NWVmZC1jMWZmLTQyNGUtOWRjMy00NDFiZTc4MzMwMTAAAAAAAP///3NrAACYAAAAmAAAABMAAADkAAAAAQAEiMwAAADYAAAAAAAAABQAAAACALgACAAAAAAAGAAZAAIAAQIAAAAAAAUgAAAAIQIAAAAaGAAAAACAAQIAAAAAAAUgAAAAIQIAAAAAGAAZAAIAAQIAAAAAAAUgAAAAIAIAAAAaGAAAAACAAQIAAAAAAAUgAAAAIAIAAAAAFAA/AA8AAQEAAAAAAAUSAAAAABoUAAAAABABAQAAAAAABRIAAAAAABQAGQACAAEBAAAAAAAFEgAAAAAaFAAAAACAAQEAAAAAAAMAAAAAAQEAAAAAAAUSAAAAAQEAAAAAAAUSAAAAAAAAAPj///+ABwAA+P///1gKAAD4////IAsAANj///92aw4ABAAAgAAAAAAEAAAAAQCyAEFDU2V0dGluZ0luZGV4bGyI////bmsgAK2WBq7Ay9wBAAAAABgDAAAAAAAAAAAAAP//////////AQAAACAEAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAAGQ2Mzk1MThhLWU1NmQtNDM0NS04YWYyLWI5ZjMyZmIyNjEwOQAAAADY////bGYEAKADAAA2NzM4iAQAAGQzZDVABgAAZDYzOQgHAABmYzcz2P///3ZrDgAEAACAAAAAAAQAAAABAAAAQUNTZXR0aW5nSW5kZXiyAIj///9uayAArZYGrsDL3AEAAAAAGAMAAAAAAAAAAAAA//////////8BAAAAAAYAAAAFAAD/////AAAAAAAAAAAcAAAABAAAAAAAAAAkAAAAZmM3MzcyYjYtYWIyZC00M2VlLTg3OTctMTVlOTg0MWYyY2NhAAAAANj///92aw4ABAAAgAAAAAAEAAAAAQAPAEFDU2V0dGluZ0luZGV4bwCI////bmsgAAfM+a3Ay9wBAAAAACAAAAAAAAAAAAAAAP//////////AgAAAJADAACYAAAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAADI0NWQ4NTQxLTM5NDMtNDQyMi1iMDI1LTEzYTc4NGY2NzliNwAAAAD4////oAkAAPj///8YDQAA+P///+ANAADY////dmsOAAQAAIABAAAABAAAAAEAAABBQ1NldHRpbmdJbmRleAAA2P///3ZrDgAEAACAAgAAAAQAAAABAAAARENTZXR0aW5nSW5kZXgYAIj///9uayAAi1cIrsDL3AEAAAAAIAAAAAMAAAAAAAAA+AoAAP////8AAAAA/////wAFAAD/////SAAAAAAAAAAAAAAAAAAAAAAAAAAkAAAAMmE3Mzc0NDEtMTkzMC00NDAyLThkNzctYjJiZWJiYTMwOGEzAAAAAPj///+AFAAACAAAADE3YWH4////yBMAABAAAAAyYTczSAsAADU0NTOI////bmsgAItXCK7Ay9wBAAAAAIgIAAAAAAAAAAAAAP//////////AQAAACAIAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAADA4NTNhNjgxLTI3YzgtNDEwMC1hMmZkLTgyMDEzZTk3MDY4MwAAAADY////dmsOAAQAAIAAAAAABAAAAAEAZG5BQ1NldHRpbmdJbmRleLIAiP///25rIACLVwiuwMvcAQAAAACICAAAAAAAAAAAAAD//////////wEAAAAIBgAAAAUAAP////8AAAAAAAAAABwAAAAEAAAAAAAAACQAAAA0OGU2YjdhNi01MGY1LTQ3ODItYTVkNC01M2JiOGYwN2UyMjYAAAAA8P///zgMAABgDAAAMDg1MwgAAAA0OGU22P///3ZrDgAEAACAAAAAAAQAAAABAAAAQUNTZXR0aW5nSW5kZXgtNYj///9uayAAi1cIrsDL3AEAAAAAiAgAAAAAAAAAAAAA//////////8BAAAAEAYAAAAFAAD/////AAAAAAAAAAAcAAAABAAAAAAAAAAkAAAAZDRlOThmMzEtNWZmZS00Y2UxLWJlMzEtMWIzOGIzODRjMDA5AAAAANj///9sZgMAKAkAADA4NTPICQAANDhlNoAKAABkNGU5AAAAAAAAAADY////dmsOAAQAAIAAAAAABAAAAAEAbnlBQ1NldHRpbmdJbmRleAAAiP///25rIACyWlzUYczcAQAAAAAgAAAACAAAAAAAAAAQEgAA/////wAAAAD/////AAUAAP////9IAAAAAAAAAAAAAAAAAAAAAAAAACQAAAA1NDUzMzI1MS04MmJlLTQ4MjQtOTZjMS00N2I2MGI3NDBkMDAAAAAAiP///25rIACRDFzUYczcAQAAAABICwAAAAAAAAAAAAD//////////wIAAABACgAAAAUAAP////8AAAAAAAAAABwAAAAEAAAAAAAAACQAAAAwY2M1YjY0Ny1jMWRmLTQ2MzctODkxYS1kZWMzNWMzMTg1ODMAAAAA2P///3ZrDgAEAACAZAAAAAQAAAABAAAAQUNTZXR0aW5nSW5kZXgAANj///92aw4ABAAAgAQAAAAEAAAAAQAAAERDU2V0dGluZ0luZGV4ZgCI////bmsgAItXCK7Ay9wBAAAAAEgLAAAAAAAAAAAAAP//////////AQAAACgIAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAADNiMDRkNGZkLTFjYzctNGYyMy1hYjFjLWQxMzM3ODE5YzRiYgAAAADw////gA4AAKgOAAAwY2M1CAAAADNiMDTY////dmsOAAQAAIAAAAAABAAAAAEAAABBQ1NldHRpbmdJbmRleLIAiP///25rIAC2CAuuwMvcAQAAAABICwAAAAAAAAAAAAD//////////wEAAAAwCAAAAAUAAP////8AAAAAAAAAABwAAAAEAAAAAAAAACQAAAA0ZDJiMDE1Mi03ZDVjLTQ5OGItODhlMi0zNDM0NTM5MmEyYzUAAAAA2P///3ZrDgAEAACAZAAAAAQAAAABAAAAQUNTZXR0aW5nSW5kZXgAANj///92aw4ABAAAgMgAAAAEAAAAAQBMokFDU2V0dGluZ0luZGV4A/WI////bmsgAEAKW9RhzNwBAAAAAEgLAAAAAAAAAAAAAP//////////AgAAAAANAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAADdmMmY1Y2ZhLWYxMGMtNDgyMy1iNWUxLWU5M2FlODVmNDZiNQAAAADY////dmsOAAQAAIAAAAAABAAAAAEAQfFBQ1NldHRpbmdJbmRleOIA2P///3ZrDgAEAACAAAAAAAQAAAABAKAWRENTZXR0aW5nSW5kZXgAAIj///9uayAAHalc1GHM3AEAAAAASAsAAAAAAAAAAAAA//////////8CAAAAsA8AAAAFAAD/////AAAAAAAAAAAcAAAABAAAAAAAAAAkAAAAODkzZGVlOGUtMmJlZi00MWUwLTg5YzYtYjU1ZDA5Mjk5NjRjAAAAANj///92aw4ABAAAgGQAAAAEAAAAAQAAAEFDU2V0dGluZ0luZGV4AADw////SA8AAHASAAA5M2I4CAAAAGJhZTDY////dmsOAAQAAIAFAAAABAAAAAEAAABEQ1NldHRpbmdJbmRleAAA8P///7gNAACIDwAAAAAAANj///92aw4ABAAAgAUAAAAEAAAAAQBrcEFDU2V0dGluZ0luZGV4bmbw////wA8AAJgQAAAAAAAACAAAAAAAAABoYmluABAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIj///9uayAAUDFb1GHM3AEAAAAASAsAAAAAAAAAAAAA//////////8CAAAA6A8AAAAFAAD/////AAAAAAAAAAAcAAAABAAAAAAAAAAkAAAAOTNiOGI2ZGMtMDY5OC00ZDFjLTllZTQtMDY0NGU5MDBjODVkAAAAANj///92aw4ABAAAgAUAAAAEAAAAAQAAAERDU2V0dGluZ0luZGV4AACI////bmsgAEAKW9RhzNwBAAAAAEgLAAAAAAAAAAAAAP//////////AgAAAIgRAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAAGJhZTA4YjgxLTJkNWUtNDY4OC1hZDZhLTEzMjQzMzU2NjU0YgAAAADY////dmsOAAQAAIAFAAAABAAAAAEAAABBQ1NldHRpbmdJbmRleA8A2P///3ZrDgAEAACABQAAAAQAAAABAG9sRENTZXR0aW5nSW5kZXgYAPD///84EQAAYBEAAAAAAACI////bmsgAKkfXdRhzNwBAAAAAEgLAAAAAAAAAAAAAP//////////AgAAAHAPAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAAGJjNTAzOGY3LTIzZTAtNDk2MC05NmRhLTMzYWJhZjU5MzVlYwAAAACg////bGYIAMALAAAwY2M1iAwAADNiMDRADQAANGQyYggOAAA3ZjJm0A4AADg5M2QgEAAAOTNiOMAQAABiYWUwmBEAAGJjNTAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAADY////dmsOAAQAAIBkAAAABAAAAAEAAABEQ1NldHRpbmdJbmRleAAAiP///25rIAC2CAuuwMvcAQAAAAAgAAAAAgAAAAAAAABoFAAA/////wAAAAD/////AAUAAP////9IAAAAAAAAAAAAAAAAAAAAAAAAACQAAAA3NTE2Yjk1Zi1mNzc2LTQ0NjQtOGM1My0wNjE2N2Y0MGNjOTkAAAAAwP///2xmBQAYAwAAMDAxMqgHAAAyNDVkiAgAADJhNzNICwAANTQ1M5gSAAA3NTE2AAAAAAAAAAAAAAAAAAAAAIj///9uayAAtggLrsDL3AEAAAAAmBIAAAAAAAAAAAAA//////////8BAAAAEAkAAAAFAAD/////AAAAAAAAAAAcAAAABAAAAAAAAAAkAAAAMTdhYWEyOWItOGI0My00Yjk0LWFhZmUtMzVmNjRkYWFmMWVlAAAAANj///92aw4ABAAAgAAAAAAEAAAAAQBj6kFDU2V0dGluZ0luZGV47E6I////bmsgAEr6qR6i0dwBAAAAAJgSAAAAAAAAAAAAAP//////////AQAAAAAJAAAABQAA/////wAAAAAAAAAAHAAAAAQAAAAAAAAAJAAAADNjMGJjMDIxLWM4YTgtNGUwNy1hOTczLTZiMTRjYmNiMmI3ZQAAAADo////bGYCAFATAAAxN2Fh8BMAADNjMGLY////dmsOAAQAAIAIBwAABAAAAAEAAABBQ1NldHRpbmdJbmRleExlWAsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
'@

$powerActions = @{
    'Import and Enable Atlas Power Scheme' = {
        $temp = Join-Path $env:TEMP "AtlasPowerScheme.pow"
        try {
            $bytes = [Convert]::FromBase64String($atlasPowBase64)
            [IO.File]::WriteAllBytes($temp, $bytes)
            Write-Log "  Importing Atlas Power Scheme..."
            $importOut = powercfg /import $temp 2>&1 | Out-String
            Write-Log $importOut.Trim()
            $guid = $null
            if ($importOut -match "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") {
                $guid = $matches[1]
            }
            if (-not $guid) { $guid = "11111111-1111-1111-1111-111111111111" }
            powercfg /setactive $guid 2>&1 | Out-Null
            Write-Log ("  Atlas Power Scheme set as active (" + $guid + ").")
        }
        catch {
            Write-Log ("  Failed to import: " + $_.Exception.Message)
        }
        finally {
            if (Test-Path $temp) { Remove-Item $temp -Force -ErrorAction SilentlyContinue }
        }
    }
    'Remove Atlas Power Scheme' = {
        Write-Log "  Looking for Atlas Power Scheme..."
        $list = powercfg /list 2>&1 | Out-String
        $guids = [regex]::Matches($list, "([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})") | ForEach-Object { $_.Groups[1].Value }
        $atlasGuids = @()
        foreach ($g in $guids) {
            $q = powercfg /query $g 2>&1 | Out-String
            if ($q -match "Atlas") { $atlasGuids += $g }
        }
        if ($atlasGuids.Count -eq 0 -and $list -match "11111111-1111-1111-1111-111111111111") {
            $atlasGuids += "11111111-1111-1111-1111-111111111111"
        }
        if ($atlasGuids.Count -eq 0) {
            Write-Log "  Atlas Power Scheme not found."
            return
        }
        foreach ($g in $atlasGuids) {
            powercfg /delete $g 2>&1 | Out-Null
            Write-Log ("  Deleted scheme " + $g)
        }
        $active = powercfg /getactivescheme
        if ($active -match "11111111|Atlas") {
            powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
            Write-Log "  Switched active plan to Balanced."
        }
        Write-Log "  Done."
    }
}
$btnPower.Add_Click({ Invoke-Selected $powerList $powerActions })

# Launch - Ask about System Restore Point first
$restoreMsg = "Would you like to create a System Restore Point before making any changes?`n`nThis is recommended and takes a few moments."
$createRestore = [System.Windows.Forms.MessageBox]::Show($restoreMsg, "Create System Restore Point?", "YesNo", "Question") -eq "Yes"

if ($createRestore) {
    Write-Log "Creating System Restore Point..."
    Set-Status "Creating System Restore Point..."
    try {
        Enable-ComputerRestore -Drive $env:SystemDrive -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "BetterWindows - Before Changes" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Log "System Restore Point created successfully."
        [System.Windows.Forms.MessageBox]::Show("System Restore Point created.", "Success", "OK", "Information") | Out-Null
    }
    catch {
        Write-Log ("Could not create Restore Point: " + $_.Exception.Message)
        [System.Windows.Forms.MessageBox]::Show("Could not create a Restore Point.`nYou can continue anyway.", "Warning", "OK", "Warning") | Out-Null
    }
}

Write-Log "BetterWindows ready."
Write-Log "Hover any option for a description. Select items and click Run Selected."
[void]$form.ShowDialog()
