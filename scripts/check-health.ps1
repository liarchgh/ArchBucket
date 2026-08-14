#Requires -Version 5.1
<#
.SYNOPSIS
    Check all bucket manifests for broken download URLs, stale versions, and upstream maintenance status.

.DESCRIPTION
    For each manifest under <bucket>/:
      - HEAD-checks every download URL (top-level "url" and each "architecture.*.url").
      - Runs checkver ("github" style or url+regex/re) to find the latest upstream version.
      - Fetches GitHub repo metadata (archived, last push, latest release) when the homepage is a
        GitHub repo, and classifies upstream as active / dormant / archived.
    Prints a per-app table and a summary, and exits 1 if any URL is broken or any manifest is stale.

.EXAMPLE
    powershell -File scripts\check-health.ps1
    powershell -File scripts\check-health.ps1 -BucketDir .\bucket

.NOTES
    Uses the unauthenticated GitHub API (60 req/hr per IP). Set GITHUB_TOKEN to raise the limit:
        $env:GITHUB_TOKEN = 'ghp_...'
#>
[CmdletBinding()]
param(
    [string]$BucketDir = '',
    [switch]$UpdateReadme
)

if (-not $BucketDir) { $BucketDir = Join-Path $PSScriptRoot '..\bucket' }
$BucketDir = (Resolve-Path $BucketDir).Path

$ErrorActionPreference = 'Stop'
$Today = Get-Date

function Invoke-GhApi {
    param([string]$Uri)
    $h = @{ 'User-Agent' = 'scoop-archbucket-health-check' }
    if ($env:GITHUB_TOKEN) { $h['Authorization'] = "token $($env:GITHUB_TOKEN)" }
    try { return Invoke-RestMethod -Uri $Uri -Headers $h -TimeoutSec 30 }
    catch { return $null }
}

function Test-Url {
    # Returns the HTTP status code for a download URL. Scoop fragment (e.g. "#/dl.7z") is stripped.
    # Some servers reject HEAD (403/405); a tiny Range GET is retried to confirm reachability.
    param([string]$Url)
    $u = ($Url -split '#')[0]
    $h = @{ 'User-Agent' = 'Mozilla/5.0' }
    try {
        $r = Invoke-WebRequest -Uri $u -Method Head -MaximumRedirection 10 -Headers $h -TimeoutSec 30 -UseBasicParsing
        return $r.StatusCode
    }
    catch {
        $code = if ($_.Exception.Response.StatusCode) { [int]$_.Exception.Response.StatusCode } else { -1 }
        if ($code -in 400, 403, 405, 501) {
            try {
                $h['Range'] = 'bytes=0-0'
                $r = Invoke-WebRequest -Uri $u -Method Get -MaximumRedirection 10 -Headers $h -TimeoutSec 30 -UseBasicParsing
                return $r.StatusCode
            }
            catch {
                if ($_.Exception.Response.StatusCode) { return [int]$_.Exception.Response.StatusCode }
                return -1
            }
        }
        return $code
    }
}

function Get-LatestVersion {
    # Returns @{ Version; Released } for a manifest, or $null when checkver can't run.
    param($Manifest)
    $cv = $Manifest.checkver

    if ($cv -is [string] -and $cv -eq 'github') {
        if ($Manifest.homepage -match 'github\.com/([^/]+)/([^/]+)') {
            $owner = $Matches[1]; $repo = ($Matches[2] -replace '\.git$', '')
            $rel = Invoke-GhApi "https://api.github.com/repos/$owner/$repo/releases/latest"
            if ($rel -and $rel.tag_name) {
                return @{ Version = ($rel.tag_name -replace '^[vV]', ''); Released = $rel.published_at }
            }
        }
        return $null
    }

    if ($cv -is [psobject] -and $cv.url) {
        try {
            $html = (Invoke-WebRequest -Uri $cv.url -Headers @{ 'User-Agent' = 'Mozilla/5.0' } `
                -TimeoutSec 30 -UseBasicParsing).Content
            $re = if ($cv.regex) { $cv.regex } elseif ($cv.re) { $cv.re } else { $null }
            if ($re) {
                $m = [regex]::Match($html, $re)
                if ($m.Success) {
                    $v = if ($m.Groups.Count -gt 1) { $m.Groups[1].Value } else { $m.Value }
                    return @{ Version = $v; Released = $null }
                }
            }
        }
        catch { return $null }
    }
    return $null
}

function Get-VersionParts {
    param([string]$v)
    ($v -replace '^[vV]', '').Split('.') | ForEach-Object {
        if ($_ -match '^\d+$') { [int]$_ } else { -1 }
    }
}

function Compare-Versions {
    # 1 if $a > $b, 0 if equal, -1 if $a < $b
    param([string]$a, [string]$b)
    $pa = @(Get-VersionParts $a); $pb = @(Get-VersionParts $b)
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}

function Update-Readme {
    # Regenerates the "<!-- STATUS:START --> ... <!-- STATUS:END -->" block in the repo README
    # from the health-check results. Reuses existing 用途 text per app to preserve curation.
    param($Results)
    $readmePath = Join-Path $PSScriptRoot '..\README.md'
    if (-not (Test-Path $readmePath)) { Write-Warning "README not found: $readmePath"; return }

    $raw = [System.IO.File]::ReadAllText($readmePath)
    $startMarker = '<!-- STATUS:START -->'
    $endMarker = '<!-- STATUS:END -->'
    $si = $raw.IndexOf($startMarker)
    $ei = $raw.IndexOf($endMarker)
    if ($si -lt 0 -or $ei -le $si) {
        Write-Warning 'README STATUS markers not found; add <!-- STATUS:START -->/<!-- STATUS:END --> around the table.'
        return
    }

    # Preserve the curated 用途 column and last-known status from the existing table, keyed by app name.
    $existingDesc = @{}
    $existingStatus = @{}
    $block = $raw.Substring($si + $startMarker.Length, $ei - $si - $startMarker.Length)
    foreach ($line in ($block -split "\r?\n")) {
        $t = $line.Trim()
        if ($t.StartsWith('|') -and $t -notmatch '\| *--- *\|') {
            $cells = $t.Trim('|').Split('|') | ForEach-Object { $_.Trim() }
            if ($cells.Count -ge 4 -and $cells[0] -ne '软件') {
                $existingDesc[$cells[0]] = $cells[2]
                $existingStatus[$cells[0]] = $cells[3]
            }
        }
    }

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add($startMarker)
    $lines.Add("> 维护状态于 $today 检查。")
    $lines.Add('')
    $lines.Add('| 软件 | 安装命令 | 用途 | 维护状态 |')
    $lines.Add('| --- | --- | --- | --- |')
    foreach ($r in ($Results | Sort-Object App)) {
        $desc = if ($existingDesc.ContainsKey($r.App)) { $existingDesc[$r.App] } else { $r.Desc }
        # When upstream status couldn't be resolved (API failure / unknown), keep the last-known status.
        $st = if (($r.Upstream -in 'n/a', 'unknown') -and $existingStatus.ContainsKey($r.App)) {
            $existingStatus[$r.App]
        }
        else { $r.StatusCn }
        $lines.Add("| $($r.App) | ``scoop install Arch/$($r.App)`` | $desc | $st |")
    }
    $lines.Add($endMarker)
    $newBlock = $lines -join "`r`n"

    $new = $raw.Substring(0, $si) + $newBlock + $raw.Substring($ei + $endMarker.Length)
    if ($new -ne $raw) {
        [System.IO.File]::WriteAllText($readmePath, $new)
        Write-Host "README updated: $readmePath"
    }
    else {
        Write-Host 'README status unchanged.'
    }
}

$broken = 0; $stale = 0

$results = @(
Get-ChildItem (Join-Path $BucketDir '*.json') | Sort-Object Name | ForEach-Object {
    $m = Get-Content $_.FullName -Raw | ConvertFrom-Json
    $name = $_.BaseName

    # --- download URLs ---
    $urls = @()
    if ($m.url) { $urls += [string]$m.url }
    if ($m.architecture) {
        foreach ($arch in $m.architecture.PSObject.Properties.Value) {
            if ($arch.url) { $urls += [string]$arch.url }
        }
    }
    $codes = @($urls | ForEach-Object { Test-Url $_ })
    $urlOk = $urls.Count -gt 0 -and ($codes | Where-Object { $_ -ne 200 }).Count -eq 0
    $urlLabel = if ($urls.Count -eq 0) { 'no-url' }
                elseif ($urlOk) { 'OK' }
                else { ($codes | Sort-Object -Unique) -join ',' }
    if (-not $urlOk) { $script:broken++ }

    # --- checkver / latest version ---
    $lv = Get-LatestVersion $m
    $latest = if ($lv) { $lv.Version } else { $null }
    $upToDate = $null
    if ($latest) {
        $cmp = Compare-Versions $latest $m.version
        $upToDate = ($cmp -le 0)
        if (-not $upToDate) { $script:stale++ }
    }

    # --- upstream maintenance ---
    # Prefer homepage as the GitHub repo source; fall back to checkver.url for non-GitHub homepages.
    $status = 'n/a'
    $ghUrl = if ($m.homepage -match 'github\.com/([^/]+)/([^/]+)') { $m.homepage }
             elseif ($m.checkver.url -match 'github\.com/([^/]+)/([^/]+)') { [string]$m.checkver.url }
             else { $null }
    if ($ghUrl) {
        $owner = $Matches[1]; $repo = ($Matches[2] -replace '\.git$', '')
        $repoInfo = Invoke-GhApi "https://api.github.com/repos/$owner/$repo"
        if ($repoInfo) {
            if ($repoInfo.archived) { $status = 'archived' }
            elseif ($repoInfo.pushed_at) {
                $ageDays = ($Today - ([datetime]$repoInfo.pushed_at)).TotalDays
                $status = if ($ageDays -gt 365) { 'dormant' } else { 'active' }
            }
            elseif ($lv -and $lv.Released) {
                $ageDays = ($Today - ([datetime]$lv.Released)).TotalDays
                $status = if ($ageDays -gt 730) { 'dormant' } else { 'active' }
            }
            else { $status = 'active' }
        }
    }
    elseif ($latest) {
        $status = if ($upToDate -eq $false) { 'active' } else { 'unknown' }
    }

    # --- Chinese status text for the README table ---
    $lastActive = if ($lv -and $lv.Released) { [datetime]$lv.Released }
                  elseif ($repoInfo -and $repoInfo.pushed_at) { [datetime]$repoInfo.pushed_at }
                  else { $null }
    $lastActiveShort = if ($lastActive) { $lastActive.ToString('yyyy-MM') } else { $null }
    $statusCn = switch ($status) {
        'archived' { '已归档' }
        'dormant'  { if ($lastActiveShort) { "停滞（$lastActiveShort 后无更新）" } else { '停滞（长期无更新）' } }
        'active'   { if ($upToDate -eq $false) { "维护中（新版 $latest 待自动更新）" } else { '维护中' } }
        default    { if ($upToDate -eq $false) { "维护中（新版 $latest 待自动更新）" } else { '未知' } }
    }

    [pscustomobject]@{
        App       = $name
        Version   = [string]$m.version
        Latest    = if ($latest) { $latest } else { '-' }
        UpToDate  = if ($null -eq $upToDate) { '?' } elseif ($upToDate) { 'yes' } else { 'NO' }
        URL       = $urlLabel
        Upstream  = $status
        Desc      = [string]$m.description
        StatusCn  = $statusCn
    }
}
)

$results | Format-Table -AutoSize | Out-Host

Write-Host "Summary: $($results.Count) manifests, $stale stale, $broken with broken URL(s)."
Write-Host 'Upstream legend: active = maintained, dormant = >1y no commits/release, archived = repo read-only, n/a = non-GitHub.'
if ($UpdateReadme) { Update-Readme $results }
if (($stale -gt 0 -or $broken -gt 0) -and -not $UpdateReadme) { exit 1 }
