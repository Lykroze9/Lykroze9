# Rebuilds the project tables in README.md from the owner's public repos.
# A repo lands in a section by its topic: claude-skill -> skills, windows-app -> apps.
# Works on Windows PowerShell 5.1 and pwsh. Needs the GitHub CLI (gh), logged in or GH_TOKEN set.
param([string]$Owner = $(if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { 'Lykroze9' }),
      [string]$Readme = (Join-Path $PSScriptRoot '..\..\README.md'))

$ErrorActionPreference = 'Stop'
$json = gh api "users/$Owner/repos?per_page=100&type=owner&sort=pushed"
if ($LASTEXITCODE) { throw "gh api failed" }
# PS 5.1 emits a JSON array as one object: ForEach-Object unrolls it.
$repos = @(($json -join "`n") | ConvertFrom-Json | ForEach-Object { $_ }) | Where-Object {
    -not $_.fork -and -not $_.archived -and -not $_.private -and $_.name -ne $Owner
}

# Optional per-section overrides (.github/projects.json), keyed "<repo>|<topic>": { "url": ..., "description": ... }.
# Lets one repo show a different link and text in each section (e.g. a skill folder vs the app download).
$overridesFile = Join-Path $PSScriptRoot '..\projects.json'
$overrides = if (Test-Path $overridesFile) { [IO.File]::ReadAllText((Resolve-Path $overridesFile).Path, [Text.Encoding]::UTF8) | ConvertFrom-Json } else { $null }

function Get-Table($topic, $empty) {
    $list = @($repos | Where-Object { $_.topics -contains $topic } | Sort-Object name)
    if (-not $list.Count) { return $empty }
    $rows = @('| Project | What it does |', '|---|---|')
    foreach ($r in $list) {
        $o = if ($overrides) { $overrides."$($r.name)|$topic" } else { $null }
        $url = if ($o -and $o.url) { $o.url } else { $r.html_url }
        $text = if ($o -and $o.description) { $o.description } elseif ($r.description) { $r.description } else { '' }
        $rows += "| [**$($r.name)**]($url) | $($text -replace '\|', '\|') |"
    }
    return ($rows -join "`n")
}

$soon = "*Coming soon. / Bient$([char]0xF4)t.*"   # kept ASCII so PS 5.1 reads the file right
$sections = @{
    'skills' = (Get-Table 'claude-skill' $soon)
    'apps'   = (Get-Table 'windows-app'  $soon)
}

$path = (Resolve-Path $Readme).Path
$text = [IO.File]::ReadAllText($path)
$new = $text
foreach ($k in $sections.Keys) {
    $pattern = "(?s)(<!-- $k`:start -->).*?(<!-- $k`:end -->)"
    $body = $sections[$k]
    $new = [regex]::Replace($new, $pattern, { param($m) $m.Groups[1].Value + "`n" + $body + "`n" + $m.Groups[2].Value })
}
if ($new -ne $text) {
    [IO.File]::WriteAllText($path, $new, (New-Object Text.UTF8Encoding($false)))
    Write-Output 'README updated'
} else {
    Write-Output 'README already up to date'
}
