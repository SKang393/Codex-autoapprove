param(
    [ValidateRange(1, 3600)]
    [int]$IntervalSeconds = 30,

    [ValidateSet('Invoke', 'Mouse')]
    [string]$ClickMode = 'Invoke',

    [ValidateRange(0, 1000000)]
    [int]$MaxScans = 0,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedButtonName {
    param([AllowNull()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ''
    }

    return (($Name -replace '\s+', ' ').Trim())
}

function Test-ApproveSessionButtonName {
    param([AllowNull()][string]$Name)

    $normalized = Get-NormalizedButtonName -Name $Name
    return ($normalized -eq 'Approve for session' -or $normalized -like 'Approve for sessi*')
}

function Select-ApproveButtonCandidate {
    param([AllowEmptyCollection()][object[]]$ButtonInfos)

    $matches = @(
        $ButtonInfos | Where-Object {
            $enabled = $true
            if ($null -ne $_.PSObject.Properties['IsEnabled']) {
                $enabled = [bool]$_.IsEnabled
            }

            $name = ''
            if ($null -ne $_.PSObject.Properties['Name']) {
                $name = [string]$_.Name
            }

            $enabled -and (Test-ApproveSessionButtonName -Name $name)
        }
    )

    if ($matches.Count -eq 0) {
        return $null
    }

    $exactMatches = @(
        $matches | Where-Object {
            (Get-NormalizedButtonName -Name ([string]$_.Name)) -eq 'Approve for session'
        }
    )

    if ($exactMatches.Count -gt 0) {
        return $exactMatches[0]
    }

    return $matches[0]
}

function Get-RectangleCenter {
    param([Parameter(Mandatory)][object]$Bounds)

    $left = [double]$Bounds.Left
    $top = [double]$Bounds.Top
    $width = [double]$Bounds.Width
    $height = [double]$Bounds.Height

    [pscustomobject]@{
        X = [int][Math]::Round($left + ($width / 2))
        Y = [int][Math]::Round($top + ($height / 2))
    }
}

function Import-NotificationLayoutScannerApi {
    Add-Type -AssemblyName System.Drawing

    if (-not ('AutoApproveClicker.NotificationLayoutScanner' -as [type])) {
        Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Linq;
using System.Runtime.InteropServices;

namespace AutoApproveClicker
{
    public static class NotificationLayoutScanner
    {
        private sealed class ButtonRun
        {
            public int Left;
            public int Right;
            public int Width { get { return Right - Left + 1; } }
        }

        private sealed class RowMatch
        {
            public int GroupLeft;
            public int GroupRight;
            public int ThirdLeft;
            public int ThirdRight;
            public int Y;
        }

        private sealed class CandidateGroup
        {
            public int GroupLeft;
            public int GroupRight;
            public int ThirdLeft;
            public int ThirdRight;
            public int MinY;
            public int MaxY;
        }

        public static Rectangle[] FindApproveSessionButtonRects(Bitmap bitmap, int screenLeft, int screenTop)
        {
            Rectangle imageBounds = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
            Bitmap scanBitmap = bitmap.Clone(imageBounds, PixelFormat.Format32bppArgb);
            BitmapData data = scanBitmap.LockBits(imageBounds, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);

            try
            {
                int bitsPerPixel = Image.GetPixelFormatSize(data.PixelFormat);
                int bytesPerPixel = bitsPerPixel / 8;
                if (bytesPerPixel < 3)
                {
                    return new Rectangle[0];
                }

                int rowBytes = bitmap.Width * bytesPerPixel;
                int byteCount = rowBytes * bitmap.Height;
                byte[] pixels = new byte[byteCount];
                for (int y = 0; y < bitmap.Height; y++)
                {
                    IntPtr sourceRow = IntPtr.Add(data.Scan0, y * data.Stride);
                    Marshal.Copy(sourceRow, pixels, y * rowBytes, rowBytes);
                }

                List<RowMatch> rowMatches = new List<RowMatch>();
                for (int y = 0; y < bitmap.Height; y++)
                {
                    List<ButtonRun> runs = GetButtonRunsForRow(pixels, rowBytes, bytesPerPixel, bitmap.Width, y);
                    if (runs.Count < 4)
                    {
                        continue;
                    }

                    for (int index = 0; index <= runs.Count - 4; index++)
                    {
                        ButtonRun first = runs[index];
                        ButtonRun second = runs[index + 1];
                        ButtonRun third = runs[index + 2];
                        ButtonRun fourth = runs[index + 3];

                        int gap1 = second.Left - first.Right - 1;
                        int gap2 = third.Left - second.Right - 1;
                        int gap3 = fourth.Left - third.Right - 1;
                        if (!IsValidGap(gap1) || !IsValidGap(gap2) || !IsValidGap(gap3))
                        {
                            continue;
                        }

                        int maxWidth = Math.Max(Math.Max(first.Width, second.Width), Math.Max(third.Width, fourth.Width));
                        int minWidth = Math.Min(Math.Min(first.Width, second.Width), Math.Min(third.Width, fourth.Width));
                        int groupLeft = first.Left;
                        int groupRight = fourth.Right;
                        int groupWidth = groupRight - groupLeft + 1;

                        if ((maxWidth - minWidth) > 20 || groupWidth < 280 || groupWidth > 390)
                        {
                            continue;
                        }

                        if (!HasNotificationCardContext(pixels, rowBytes, bytesPerPixel, bitmap.Width, bitmap.Height, groupLeft, groupRight, y))
                        {
                            continue;
                        }

                        rowMatches.Add(new RowMatch
                        {
                            GroupLeft = groupLeft,
                            GroupRight = groupRight,
                            ThirdLeft = third.Left,
                            ThirdRight = third.Right,
                            Y = y
                        });
                    }
                }

                List<CandidateGroup> groups = GroupRowMatches(rowMatches);
                return groups
                    .Where(group => group.MaxY - group.MinY + 1 >= 1)
                    .Select(group => new Rectangle(
                        screenLeft + group.ThirdLeft,
                        screenTop + group.MinY,
                        group.ThirdRight - group.ThirdLeft + 1,
                        group.MaxY - group.MinY + 1))
                    .OrderBy(rect => rect.Top)
                    .ThenBy(rect => rect.Left)
                    .ToArray();
            }
            finally
            {
                scanBitmap.UnlockBits(data);
                scanBitmap.Dispose();
            }
        }

        private static List<ButtonRun> GetButtonRunsForRow(byte[] pixels, int stride, int bytesPerPixel, int width, int y)
        {
            List<ButtonRun> runs = new List<ButtonRun>();
            bool inRun = false;
            int start = 0;

            for (int x = 0; x < width; x++)
            {
                bool isButtonPixel = IsButtonPixel(pixels, stride, bytesPerPixel, x, y);
                if (isButtonPixel && !inRun)
                {
                    start = x;
                    inRun = true;
                }

                if ((!isButtonPixel || x == width - 1) && inRun)
                {
                    int end = isButtonPixel ? x : x - 1;
                    int runWidth = end - start + 1;
                    if (runWidth >= 45 && runWidth <= 110)
                    {
                        runs.Add(new ButtonRun { Left = start, Right = end });
                    }
                    inRun = false;
                }
            }

            return runs;
        }

        private static List<CandidateGroup> GroupRowMatches(List<RowMatch> matches)
        {
            List<CandidateGroup> groups = new List<CandidateGroup>();
            foreach (RowMatch match in matches)
            {
                CandidateGroup existing = null;
                foreach (CandidateGroup group in groups)
                {
                    if (Math.Abs(group.ThirdLeft - match.ThirdLeft) <= 3 &&
                        Math.Abs(group.ThirdRight - match.ThirdRight) <= 3 &&
                        Math.Abs(group.GroupLeft - match.GroupLeft) <= 3 &&
                        match.Y <= group.MaxY + 3)
                    {
                        existing = group;
                        break;
                    }
                }

                if (existing == null)
                {
                    groups.Add(new CandidateGroup
                    {
                        GroupLeft = match.GroupLeft,
                        GroupRight = match.GroupRight,
                        ThirdLeft = match.ThirdLeft,
                        ThirdRight = match.ThirdRight,
                        MinY = match.Y,
                        MaxY = match.Y
                    });
                }
                else
                {
                    existing.MinY = Math.Min(existing.MinY, match.Y);
                    existing.MaxY = Math.Max(existing.MaxY, match.Y);
                }
            }

            return groups;
        }

        private static bool HasNotificationCardContext(byte[] pixels, int stride, int bytesPerPixel, int width, int height, int groupLeft, int groupRight, int rowY)
        {
            int sampleY = rowY - 70;
            if (sampleY < 0 || sampleY >= height)
            {
                return false;
            }

            int midX = (groupLeft + groupRight) / 2;
            int[] sampleXs = new int[]
            {
                Clamp(groupLeft + 8, 0, width - 1),
                Clamp(midX, 0, width - 1),
                Clamp(groupRight - 8, 0, width - 1)
            };

            int darkSamples = 0;
            foreach (int x in sampleXs)
            {
                if (IsCardPixel(pixels, stride, bytesPerPixel, x, sampleY))
                {
                    darkSamples++;
                }
            }

            return darkSamples >= 2;
        }

        private static bool IsValidGap(int gap)
        {
            return gap >= 5 && gap <= 24;
        }

        private static bool IsButtonPixel(byte[] pixels, int stride, int bytesPerPixel, int x, int y)
        {
            int red;
            int green;
            int blue;
            GetRgb(pixels, stride, bytesPerPixel, x, y, out red, out green, out blue);
            int maxDelta = Math.Max(Math.Abs(red - green), Math.Abs(red - blue));
            return red >= 42 && red <= 62 &&
                green >= 42 && green <= 62 &&
                blue >= 42 && blue <= 62 &&
                maxDelta <= 4;
        }

        private static bool IsCardPixel(byte[] pixels, int stride, int bytesPerPixel, int x, int y)
        {
            int red;
            int green;
            int blue;
            GetRgb(pixels, stride, bytesPerPixel, x, y, out red, out green, out blue);
            int maxDelta = Math.Max(Math.Abs(red - green), Math.Abs(red - blue));
            return red >= 24 && red <= 42 &&
                green >= 24 && green <= 42 &&
                blue >= 24 && blue <= 42 &&
                maxDelta <= 5;
        }

        private static void GetRgb(byte[] pixels, int stride, int bytesPerPixel, int x, int y, out int red, out int green, out int blue)
        {
            int offset = y * stride + x * bytesPerPixel;
            blue = pixels[offset];
            green = pixels[offset + 1];
            red = pixels[offset + 2];
        }

        private static int Clamp(int value, int min, int max)
        {
            if (value < min) return min;
            if (value > max) return max;
            return value;
        }
    }
}
'@
    }
}

function Find-ApproveSessionButtonsFromBitmap {
    param(
        [Parameter(Mandatory)][System.Drawing.Bitmap]$Bitmap,
        [int]$ScreenLeft = 0,
        [int]$ScreenTop = 0
    )

    Import-NotificationLayoutScannerApi
    $rectangles = [AutoApproveClicker.NotificationLayoutScanner]::FindApproveSessionButtonRects($Bitmap, $ScreenLeft, $ScreenTop)
    $candidates = @()
    foreach ($rectangle in $rectangles) {
        $candidates += [pscustomobject]@{
            Name = 'Approve for session'
            IsEnabled = $true
            Bounds = [pscustomobject]@{
                Left = $rectangle.Left
                Top = $rectangle.Top
                Width = $rectangle.Width
                Height = $rectangle.Height
            }
            WindowName = 'screenshot fallback'
            Source = 'ScreenshotLayout'
        }
    }

    return @($candidates | Sort-Object @{ Expression = { $_.Bounds.Top } }, @{ Expression = { $_.Bounds.Left } })
}

function Import-ScreenCaptureApi {
    Add-Type -AssemblyName System.Drawing

    if (-not ('AutoApproveClicker.ScreenCapture' -as [type])) {
        Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Drawing;
using System.Runtime.InteropServices;

namespace AutoApproveClicker
{
    public static class ScreenCapture
    {
        private const int Srccopy = 0x00CC0020;

        [DllImport("user32.dll")]
        private static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleDC(IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteDC(IntPtr hDC);

        [DllImport("gdi32.dll")]
        private static extern IntPtr CreateCompatibleBitmap(IntPtr hDC, int width, int height);

        [DllImport("gdi32.dll")]
        private static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);

        [DllImport("gdi32.dll")]
        private static extern bool DeleteObject(IntPtr hObject);

        [DllImport("gdi32.dll")]
        private static extern bool BitBlt(IntPtr hdcDest, int xDest, int yDest, int width, int height, IntPtr hdcSrc, int xSrc, int ySrc, int rasterOperation);

        public static Bitmap Capture(int left, int top, int width, int height)
        {
            IntPtr sourceDc = GetDC(IntPtr.Zero);
            if (sourceDc == IntPtr.Zero)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "GetDC failed.");
            }

            IntPtr targetDc = IntPtr.Zero;
            IntPtr targetBitmap = IntPtr.Zero;
            IntPtr previousObject = IntPtr.Zero;

            try
            {
                targetDc = CreateCompatibleDC(sourceDc);
                if (targetDc == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateCompatibleDC failed.");
                }

                targetBitmap = CreateCompatibleBitmap(sourceDc, width, height);
                if (targetBitmap == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateCompatibleBitmap failed.");
                }

                previousObject = SelectObject(targetDc, targetBitmap);
                if (previousObject == IntPtr.Zero)
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "SelectObject failed.");
                }

                if (!BitBlt(targetDc, 0, 0, width, height, sourceDc, left, top, Srccopy))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "BitBlt failed.");
                }

                return Image.FromHbitmap(targetBitmap);
            }
            finally
            {
                if (previousObject != IntPtr.Zero && targetDc != IntPtr.Zero)
                {
                    SelectObject(targetDc, previousObject);
                }
                if (targetBitmap != IntPtr.Zero)
                {
                    DeleteObject(targetBitmap);
                }
                if (targetDc != IntPtr.Zero)
                {
                    DeleteDC(targetDc);
                }
                ReleaseDC(IntPtr.Zero, sourceDc);
            }
        }
    }
}
'@
    }
}

function Find-ApproveButtonCandidateByScreenshot {
    Add-Type -AssemblyName System.Windows.Forms
    Import-ScreenCaptureApi

    $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = [AutoApproveClicker.ScreenCapture]::Capture($bounds.Left, $bounds.Top, $bounds.Width, $bounds.Height)

    try {
        $candidates = @(Find-ApproveSessionButtonsFromBitmap -Bitmap $bitmap -ScreenLeft $bounds.Left -ScreenTop $bounds.Top)
        if ($candidates.Count -gt 0) {
            return $candidates[0]
        }
    } finally {
        $bitmap.Dispose()
    }

    return $null
}

function Import-UiAutomation {
    if (-not ('System.Windows.Automation.AutomationElement' -as [type])) {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
    }
}

function Get-AncestorWindowName {
    param([Parameter(Mandatory)][object]$Element)

    Import-UiAutomation
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $node = $Element

    while ($null -ne $node) {
        try {
            if ($node.Current.ControlType -eq [System.Windows.Automation.ControlType]::Window) {
                return [string]$node.Current.Name
            }
            $node = $walker.GetParent($node)
        } catch {
            return ''
        }
    }

    return ''
}

function Find-ApproveButtonCandidateByUiAutomation {
    Import-UiAutomation

    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $buttonCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )

    $elements = $root.FindAll([System.Windows.Automation.TreeScope]::Subtree, $buttonCondition)
    $buttonInfos = for ($index = 0; $index -lt $elements.Count; $index++) {
        $element = $elements.Item($index)

        try {
            $current = $element.Current
            $name = [string]$current.Name
            if (-not (Test-ApproveSessionButtonName -Name $name)) {
                continue
            }

            [pscustomobject]@{
                Element = $element
                Name = $name
                IsEnabled = [bool]$current.IsEnabled
                Bounds = $current.BoundingRectangle
                ProcessId = [int]$current.ProcessId
                AutomationId = [string]$current.AutomationId
                ClassName = [string]$current.ClassName
                WindowName = Get-AncestorWindowName -Element $element
            }
        } catch {
            continue
        }
    }

    return Select-ApproveButtonCandidate -ButtonInfos @($buttonInfos)
}

function Find-ApproveButtonCandidateWithFallback {
    param(
        [scriptblock]$UiAutomationFinder = { Find-ApproveButtonCandidateByUiAutomation },
        [scriptblock]$ScreenshotFinder = { Find-ApproveButtonCandidateByScreenshot }
    )

    try {
        $uiaCandidate = & $UiAutomationFinder
        if ($null -ne $uiaCandidate) {
            return $uiaCandidate
        }
    } catch {
        Write-Warning ("UI Automation scan failed. Trying screenshot fallback. {0}" -f $_.Exception.Message)
    }

    try {
        return (& $ScreenshotFinder)
    } catch {
        Write-Warning ("Screenshot fallback failed. {0}" -f $_.Exception.Message)
        return $null
    }
}

function Find-ApproveButtonCandidate {
    return Find-ApproveButtonCandidateWithFallback
}

function Import-MouseApi {
    if (-not ('AutoApproveClicker.NativeMouse' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace AutoApproveClicker
{
    public static class NativeMouse
    {
        [DllImport("user32.dll")]
        public static extern bool SetCursorPos(int x, int y);

        [DllImport("user32.dll")]
        public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);

        public const uint LeftDown = 0x0002;
        public const uint LeftUp = 0x0004;
    }
}
'@
    }
}

function Click-ButtonCenter {
    param([Parameter(Mandatory)][object]$Candidate)

    Import-MouseApi
    $center = Get-RectangleCenter -Bounds $Candidate.Bounds

    [AutoApproveClicker.NativeMouse]::SetCursorPos($center.X, $center.Y) | Out-Null
    Start-Sleep -Milliseconds 50
    [AutoApproveClicker.NativeMouse]::mouse_event([AutoApproveClicker.NativeMouse]::LeftDown, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [AutoApproveClicker.NativeMouse]::mouse_event([AutoApproveClicker.NativeMouse]::LeftUp, 0, 0, 0, [UIntPtr]::Zero)
}

function Invoke-ApproveButtonCandidate {
    param(
        [Parameter(Mandatory)][object]$Candidate,
        [ValidateSet('Invoke', 'Mouse')][string]$Mode = 'Invoke',
        [switch]$DryRun
    )

    $center = Get-RectangleCenter -Bounds $Candidate.Bounds
    $windowName = ''
    if ($null -ne $Candidate.PSObject.Properties['WindowName']) {
        $windowName = [string]$Candidate.WindowName
    }

    Write-Host ("Found '{0}' at X={1}, Y={2}. Window='{3}'." -f $Candidate.Name, $center.X, $center.Y, $windowName)

    if ($DryRun) {
        Write-Host 'Dry run enabled. No click was sent.'
        return $true
    }

    if ($Mode -eq 'Invoke' -and $null -ne $Candidate.PSObject.Properties['Element']) {
        try {
            $pattern = $null
            if ($Candidate.Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
                $pattern.Invoke()
                Write-Host 'Invoked the approval button through Windows UI Automation.'
                return $true
            }
        } catch {
            Write-Warning ("UI Automation invoke failed. Falling back to a mouse click. {0}" -f $_.Exception.Message)
        }
    }

    Click-ButtonCenter -Candidate $Candidate
    Write-Host 'Clicked the center of the approval button.'
    return $true
}

function Invoke-ApproveScanIteration {
    param(
        [scriptblock]$FindCandidate = { Find-ApproveButtonCandidate },
        [scriptblock]$ClickCandidate = {
            param($Candidate, $Mode, $IsDryRun)
            Invoke-ApproveButtonCandidate -Candidate $Candidate -Mode $Mode -DryRun:$IsDryRun
        },
        [ValidateSet('Invoke', 'Mouse')][string]$ClickMode = 'Invoke',
        [switch]$DryRun
    )

    $candidate = & $FindCandidate
    if ($null -eq $candidate) {
        Write-Host ("{0} No 'Approve for session' button found." -f (Get-Date -Format 'HH:mm:ss'))
        return [pscustomobject]@{
            Clicked = $false
            Candidate = $null
        }
    }

    & $ClickCandidate $candidate $ClickMode ([bool]$DryRun) | Out-Null
    return [pscustomobject]@{
        Clicked = $true
        Candidate = $candidate
    }
}

function Start-ApproveForSessionClicker {
    param(
        [ValidateRange(1, 3600)][int]$IntervalSeconds = 30,
        [ValidateSet('Invoke', 'Mouse')][string]$ClickMode = 'Invoke',
        [ValidateRange(0, 1000000)][int]$MaxScans = 0,
        [scriptblock]$FindCandidate = { Find-ApproveButtonCandidate },
        [scriptblock]$ClickCandidate = {
            param($Candidate, $Mode, $IsDryRun)
            Invoke-ApproveButtonCandidate -Candidate $Candidate -Mode $Mode -DryRun:$IsDryRun
        },
        [switch]$DryRun
    )

    Write-Host ("Running until stopped. Checking every {0}s for an 'Approve for session' button across all monitors." -f $IntervalSeconds)
    Write-Host 'Close this window or press Ctrl+C to stop.'

    $scanCount = 0
    do {
        $scanCount++
        Invoke-ApproveScanIteration `
            -FindCandidate $FindCandidate `
            -ClickCandidate $ClickCandidate `
            -ClickMode $ClickMode `
            -DryRun:$DryRun | Out-Null

        if ($MaxScans -gt 0 -and $scanCount -ge $MaxScans) {
            return 0
        }

        Start-Sleep -Seconds $IntervalSeconds
    } while ($true)

    return 0
}

if ($MyInvocation.InvocationName -ne '.') {
    exit (Start-ApproveForSessionClicker @PSBoundParameters)
}
