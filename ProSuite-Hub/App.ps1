# ProSuite-Hub\App.ps1
# Windows SysAdmin ProSuite - Hub UI (PS 5.1 compatible, USA English)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region --- Hide console (best-effort)
try {
    if (-not ([System.Management.Automation.PSTypeName]'Window').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
  [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  public static void Hide(){ var h = GetConsoleWindow(); if(h!=IntPtr.Zero) ShowWindow(h,0); }
}
"@
    }
    [Window]::Hide()
} catch { }
#endregion

Add-Type -AssemblyName System.Windows.Forms | Out-Null
Add-Type -AssemblyName System.Drawing | Out-Null

. (Join-Path $PSScriptRoot "Core\ProSuite.Helpers.ps1")
. (Join-Path $PSScriptRoot "Core\ProSuite.Logging.ps1")
. (Join-Path $PSScriptRoot "Core\ProSuite.Runner.ps1")

$repoRoot   = Get-RepoRoot
$settings   = Read-JsonFile -Path (Join-Path $PSScriptRoot "Settings.json")
$appName    = [string]$settings.appName
$hubLogDir  = [string]$settings.hubLogDir

$manifestPath = Join-Path $PSScriptRoot "Manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Show-MessageBox -Type Warning -Title $appName -Text "Manifest.json not found. Run Generate-Manifest.ps1 first."
    return
}

$manifest = Read-JsonFile -Path $manifestPath
$script:tools = @($manifest.tools)

# -------------------------------
# UI Layout (single screen)
# -------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = $appName
$form.StartPosition = "CenterScreen"
$form.Size = New-Object System.Drawing.Size(1200, 720)
$form.MinimumSize = New-Object System.Drawing.Size(1050, 650)

# Top panel
$top = New-Object System.Windows.Forms.Panel
$top.Dock = "Top"
$top.Height = 44

$lblSearch = New-Object System.Windows.Forms.Label
$lblSearch.Text = "Search:"
$lblSearch.AutoSize = $true
$lblSearch.Location = New-Object System.Drawing.Point(10, 13)

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(70, 10)
$txtSearch.Width = 520

$btnReload = New-Object System.Windows.Forms.Button
$btnReload.Text = "Reload"
$btnReload.Location = New-Object System.Drawing.Point(600, 8)
$btnReload.Size = New-Object System.Drawing.Size(90, 28)

$btnGen = New-Object System.Windows.Forms.Button
$btnGen.Text = "Rebuild Manifest"
$btnGen.Location = New-Object System.Drawing.Point(698, 8)
$btnGen.Size = New-Object System.Drawing.Size(120, 28)

$btnOpenHubLogs = New-Object System.Windows.Forms.Button
$btnOpenHubLogs.Text = "Open Hub Logs"
$btnOpenHubLogs.Location = New-Object System.Drawing.Point(826, 8)
$btnOpenHubLogs.Size = New-Object System.Drawing.Size(120, 28)

$top.Controls.AddRange(@($lblSearch, $txtSearch, $btnReload, $btnGen, $btnOpenHubLogs))
$form.Controls.Add($top)

# Bottom action bar
$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = "Bottom"
$bottom.Height = 44
$form.Controls.Add($bottom)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "Run"
$btnRun.Size = New-Object System.Drawing.Size(100, 28)
$btnRun.Location = New-Object System.Drawing.Point(10, 8)

$btnRunAdmin = New-Object System.Windows.Forms.Button
$btnRunAdmin.Text = "Run as Admin"
$btnRunAdmin.Size = New-Object System.Drawing.Size(120, 28)
$btnRunAdmin.Location = New-Object System.Drawing.Point(118, 8)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "Open Folder"
$btnOpenFolder.Size = New-Object System.Drawing.Size(110, 28)
$btnOpenFolder.Location = New-Object System.Drawing.Point(246, 8)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = "Open Hub Log"
$btnOpenLog.Size = New-Object System.Drawing.Size(120, 28)
$btnOpenLog.Location = New-Object System.Drawing.Point(364, 8)

$status = New-Object System.Windows.Forms.Label
$status.AutoSize = $true
$status.Location = New-Object System.Drawing.Point(500, 12)
$status.Text = "Ready"

$bottom.Controls.AddRange(@($btnRun, $btnRunAdmin, $btnOpenFolder, $btnOpenLog, $status))

# Main split layout (Tree + Right side)
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = "Fill"
# IMPORTANT: Do not set Panel2MinSize here (can throw before layout)
$split.SplitterDistance = 320
$split.Panel1MinSize = 260
$form.Controls.Add($split)

# Left: TreeView
$tree = New-Object System.Windows.Forms.TreeView
$tree.Dock = "Fill"
$tree.HideSelection = $false
$split.Panel1.Controls.Add($tree)

# Right: Nested split (List + Details)
$rightSplit = New-Object System.Windows.Forms.SplitContainer
$rightSplit.Dock = "Fill"
$rightSplit.Orientation = "Horizontal"
$rightSplit.SplitterDistance = 330
$split.Panel2.Controls.Add($rightSplit)

# ListView
$list = New-Object System.Windows.Forms.ListView
$list.Dock = "Fill"
$list.View = "Details"
$list.FullRowSelect = $true
$list.MultiSelect = $false
$list.HideSelection = $false
[void]$list.Columns.Add("Tool", 260)
[void]$list.Columns.Add("Domain", 140)
[void]$list.Columns.Add("Module", 170)
[void]$list.Columns.Add("Type", 55)
[void]$list.Columns.Add("Admin", 60)
[void]$list.Columns.Add("Path", 900)
$rightSplit.Panel1.Controls.Add($list)

# Details tabs (README + Output)
$detailsTabs = New-Object System.Windows.Forms.TabControl
$detailsTabs.Dock = "Fill"

$tabHelp = New-Object System.Windows.Forms.TabPage
$tabHelp.Text = "Help / README"
$txtHelp = New-Object System.Windows.Forms.TextBox
$txtHelp.Dock = "Fill"
$txtHelp.Multiline = $true
$txtHelp.ScrollBars = "Vertical"
$txtHelp.ReadOnly = $true
$tabHelp.Controls.Add($txtHelp)

$tabOutput = New-Object System.Windows.Forms.TabPage
$tabOutput.Text = "Output"
$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Dock = "Fill"
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = "Vertical"
$txtOutput.ReadOnly = $true
$tabOutput.Controls.Add($txtOutput)

$detailsTabs.TabPages.AddRange(@($tabHelp, $tabOutput))
$rightSplit.Panel2.Controls.Add($detailsTabs)

# Runtime state
$script:lastHubLog = $null

# -------------------------------
# Helper functions
# -------------------------------
function Append-Output {
    param([Parameter(Mandatory)][string]$Text)
    if ($txtOutput.InvokeRequired) {
        $null = $txtOutput.BeginInvoke([Action[string]]{ param($t) $txtOutput.AppendText($t) }, $Text)
    } else {
        $txtOutput.AppendText($Text)
    }
}

function Load-ReadmeText {
    param([string]$ReadmeRel)

    $txtHelp.Clear()
    if ([string]::IsNullOrWhiteSpace($ReadmeRel)) { return }

    $abs = Join-Path $repoRoot $ReadmeRel
    if (-not (Test-Path -LiteralPath $abs)) { return }

    try {
        $txtHelp.Text = Get-Content -LiteralPath $abs -Raw -Encoding UTF8
    } catch {
        $txtHelp.Text = ("Failed to read README: {0}" -f $ReadmeRel)
    }
}

function Get-SelectedTool {
    if ($list.SelectedItems.Count -lt 1) { return $null }
    return $list.SelectedItems[0].Tag
}

function Tool-MatchesFilter {
    param(
        [Parameter(Mandatory)]$Tool,
        [string]$Search
    )
    if ([string]::IsNullOrWhiteSpace($Search)) { return $true }
    $s = $Search.Trim().ToLowerInvariant()

    return (
        (($Tool.name     -as [string]).ToLowerInvariant().Contains($s)) -or
        (($Tool.domain   -as [string]).ToLowerInvariant().Contains($s)) -or
        (($Tool.module   -as [string]).ToLowerInvariant().Contains($s)) -or
        (($Tool.path     -as [string]).ToLowerInvariant().Contains($s)) -or
        (($Tool.synopsis -as [string]).ToLowerInvariant().Contains($s))
    )
}

function Populate-Tree {
    $tree.Nodes.Clear()

    # Domain display mapping
    $displayMap = @{}
    foreach ($p in $settings.index.uiDisplayNames.psobject.Properties) {
        $displayMap[$p.Name] = [string]$p.Value
    }

    $domains = $script:tools | Group-Object domain | Sort-Object Name
    foreach ($d in $domains) {
        $domainKey  = $d.Name
        $domainText = if ($displayMap.ContainsKey($domainKey)) { $displayMap[$domainKey] } else { $domainKey }

        $dn = New-Object System.Windows.Forms.TreeNode($domainText)
        $dn.Tag = [pscustomobject]@{ kind="domain"; domain=$domainKey }

        $modules = $d.Group | Group-Object module | Sort-Object Name
        foreach ($m in $modules) {
            $mn = New-Object System.Windows.Forms.TreeNode($m.Name)
            $mn.Tag = [pscustomobject]@{ kind="module"; domain=$domainKey; module=$m.Name }

            # Optional 3rd level: path segment [2] when it adds value
            $sub = $m.Group | ForEach-Object {
                $p = ($_.path -replace '/', '\').Split('\')
                if ($p.Length -ge 3) { $p[2] } else { "" }
            } | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Sort-Object -Unique

            foreach ($s in $sub) {
                $sn = New-Object System.Windows.Forms.TreeNode($s)
                $sn.Tag = [pscustomobject]@{ kind="sub"; domain=$domainKey; module=$m.Name; sub=$s }
                [void]$mn.Nodes.Add($sn)
            }

            [void]$dn.Nodes.Add($mn)
        }

        [void]$tree.Nodes.Add($dn)
    }

    $tree.ExpandAll()
}

function Populate-ListForSelection {
    $list.Items.Clear()

    $node = $tree.SelectedNode
    if (-not $node) { return }

    $tag = $node.Tag
    $search = $txtSearch.Text

    $filtered = $script:tools

    if ($tag.kind -eq "domain") {
        $filtered = $filtered | Where-Object { $_.domain -ieq $tag.domain }
    } elseif ($tag.kind -eq "module") {
        $filtered = $filtered | Where-Object { $_.domain -ieq $tag.domain -and $_.module -ieq $tag.module }
    } elseif ($tag.kind -eq "sub") {
        $filtered = $filtered | Where-Object {
            $_.domain -ieq $tag.domain -and $_.module -ieq $tag.module -and
            (($_.path -replace '/', '\').Split('\').Length -ge 3) -and
            (($_.path -replace '/', '\').Split('\')[2] -ieq $tag.sub)
        }
    }

    $filtered = $filtered | Where-Object { Tool-MatchesFilter -Tool $_ -Search $search } | Sort-Object name

    foreach ($t in $filtered) {
        $admin = if ($t.requiresAdmin -eq $true) { "Yes" } else { "No" }
        $it = New-Object System.Windows.Forms.ListViewItem($t.name)
        [void]$it.SubItems.Add($t.domain)
        [void]$it.SubItems.Add($t.module)
        [void]$it.SubItems.Add($t.type)
        [void]$it.SubItems.Add($admin)
        [void]$it.SubItems.Add($t.path)
        $it.Tag = $t
        [void]$list.Items.Add($it)
    }

    # Node-based README: use first tool README when available
    $readmeRel = $null
    if ($filtered.Count -gt 0) { $readmeRel = $filtered[0].readmePath }
    Load-ReadmeText -ReadmeRel $readmeRel
}

function Run-Tool {
    [CmdletBinding()]
    param([switch]$AsAdmin)

    $t = Get-SelectedTool
    if (-not $t) {
        Show-MessageBox -Type Warning -Title $appName -Text "Select a tool first."
        return
    }

    $txtOutput.Clear()
    Append-Output ("Running: {0}`r`n{1}`r`n`r`n" -f $t.name, $t.path)
    $status.Text = "Running..."

    Invoke-ProSuiteToolProcess -Tool $t -RepoRoot $repoRoot -HubLogDir $hubLogDir -RunAsAdmin:$AsAdmin `
        -OnOutput { param($line) Append-Output $line } `
        -OnCompleted {
            param($ok, $hubLog, $err)

            $script:lastHubLog = $hubLog

            if ($ok) {
                $status.Text = "Completed."
                Append-Output "`r`n[OK] Completed.`r`n"
            } else {
                $status.Text = "Completed with errors."

                $errMsg = if ([string]::IsNullOrWhiteSpace($err)) { "Errors occurred." } else { $err }
                Append-Output ("`r`n[FAIL] {0}`r`n" -f $errMsg)

                $hubLogMsg = if ($hubLog) { $hubLog } else { "N/A" }
                Show-MessageBox -Type Error -Title $appName -Text ("Tool finished with errors.`r`n`r`nHub log:`r`n{0}" -f $hubLogMsg)
            }
        }
}

# -------------------------------
# Events
# -------------------------------
$tree.Add_AfterSelect({ Populate-ListForSelection })
$txtSearch.Add_TextChanged({ Populate-ListForSelection })

$list.Add_SelectedIndexChanged({
    $t = Get-SelectedTool
    if ($t -and $t.readmePath) {
        Load-ReadmeText -ReadmeRel $t.readmePath
    }
})

$btnOpenHubLogs.Add_Click({
    try { Start-Process explorer.exe ('"{0}"' -f $hubLogDir) | Out-Null } catch { }
})

$btnOpenFolder.Add_Click({
    $t = Get-SelectedTool
    if (-not $t) { return }
    $abs = Join-Path $repoRoot $t.path
    if (Test-Path -LiteralPath $abs) {
        $folder = Split-Path -Parent $abs
        Start-Process explorer.exe ('"{0}"' -f $folder) | Out-Null
    }
})

$btnOpenLog.Add_Click({
    if ($script:lastHubLog -and (Test-Path -LiteralPath $script:lastHubLog)) {
        Start-Process notepad.exe ('"{0}"' -f $script:lastHubLog) | Out-Null
    } else {
        Show-MessageBox -Type Warning -Title $appName -Text "No hub log is available yet."
    }
})

$btnReload.Add_Click({
    try {
        $script:manifest = Read-JsonFile -Path $manifestPath
        $script:tools = @($script:manifest.tools)

        Populate-Tree
        if ($tree.Nodes.Count -gt 0) { $tree.SelectedNode = $tree.Nodes[0] }
        $status.Text = "Manifest reloaded."
    } catch {
        Show-MessageBox -Type Error -Title $appName -Text "Failed to reload Manifest.json."
    }
})

$btnGen.Add_Click({
    try {
        $status.Text = "Rebuilding manifest..."
        $gen = Join-Path $PSScriptRoot "Generate-Manifest.ps1"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gen | Out-Null

        $script:manifest = Read-JsonFile -Path $manifestPath
        $script:tools = @($script:manifest.tools)

        Populate-Tree
        if ($tree.Nodes.Count -gt 0) { $tree.SelectedNode = $tree.Nodes[0] }
        $status.Text = "Manifest rebuilt."
    } catch {
        $status.Text = "Failed."
        Show-MessageBox -Type Error -Title $appName -Text "Failed to rebuild manifest."
    }
})

$btnRun.Add_Click({ Run-Tool })
$btnRunAdmin.Add_Click({ Run-Tool -AsAdmin })

# One-time: apply SplitContainer constraints AFTER layout + focus search box
$form.Add_Shown({
    try {
        $minLeft  = 260
        $minRight = 520

        $split.Panel1MinSize = $minLeft
        $split.Panel2MinSize = $minRight

        $maxSplitter = [Math]::Max($minLeft, $split.Width - $minRight)
        $split.SplitterDistance = [Math]::Min([Math]::Max($split.SplitterDistance, $minLeft), $maxSplitter)
    } catch {
        # Do not hard-fail on layout constraints
    }

    try { $txtSearch.Focus() } catch { }
})

# Init
Populate-Tree
if ($tree.Nodes.Count -gt 0) { $tree.SelectedNode = $tree.Nodes[0] }

[void]$form.ShowDialog()
