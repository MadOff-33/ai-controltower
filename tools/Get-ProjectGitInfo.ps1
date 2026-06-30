param(
  [string]$ProjectPath = "."
)

$ErrorActionPreference = "Stop"

function ConvertTo-GitHubUrl {
  param([string]$RemoteUrl)
  if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { return "" }
  $url = $RemoteUrl.Trim()
  if ($url -match "^git@github\.com:(.+?)(\.git)?$") {
    return "https://github.com/" + $Matches[1].TrimEnd(".git")
  }
  if ($url -match "^https://github\.com/(.+?)(\.git)?$") {
    return "https://github.com/" + $Matches[1].TrimEnd(".git")
  }
  return ""
}

$resolved = Resolve-Path -LiteralPath $ProjectPath -ErrorAction Stop
$project = $resolved.ProviderPath

$isRepo = $false
try {
  & git -C $project rev-parse --is-inside-work-tree 2>$null | Out-Null
  $isRepo = ($LASTEXITCODE -eq 0)
} catch {
  $isRepo = $false
}

$result = [ordered]@{
  project_path = $project
  is_git_repo = $isRepo
  branch = ""
  status = "not_git"
  remote_name = ""
  remote_url = ""
  github_url = ""
  head = ""
  head_subject = ""
}

if ($isRepo) {
  $branch = (& git -C $project branch --show-current 2>$null)
  $statusLines = @(& git -C $project status --short 2>$null)
  $remoteUrl = (& git -C $project remote get-url origin 2>$null)
  if ($LASTEXITCODE -ne 0) { $remoteUrl = "" }
  $head = (& git -C $project rev-parse --short HEAD 2>$null)
  $subject = (& git -C $project log -1 --pretty=%s 2>$null)

  $result["branch"] = [string]$branch
  $result["status"] = $(if ($statusLines.Count -eq 0) { "clean" } else { "modified" })
  $result["remote_name"] = $(if ([string]::IsNullOrWhiteSpace($remoteUrl)) { "" } else { "origin" })
  $result["remote_url"] = [string]$remoteUrl
  $result["github_url"] = ConvertTo-GitHubUrl -RemoteUrl $remoteUrl
  $result["head"] = [string]$head
  $result["head_subject"] = [string]$subject
}

$result | ConvertTo-Json -Depth 6
