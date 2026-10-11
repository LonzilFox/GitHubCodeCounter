$ErrorActionPreference = "Stop"

$AppName = "GitHubCodeCounter"
$Version = "v0.0.2"
$ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $ToolRoot "GitHubCodeCounter.config.json"
$LogDir = Join-Path $ToolRoot "logs"
$ErrorLog = Join-Path $LogDir "latest_error.log"

$ExcludedDirs = ".git,.github,node_modules,bin,obj,build,dist,.vs,.idea,venv,.venv,__pycache__,packages,target,.gradle,.cache,coverage"
$ExcludedLanguages = "Text,Markdown"
$ExcludedExtensions = "md,markdown,mdown,mkdn,mkd"

function Write-Rule {
    param(
        [string]$Char = "=",
        [int]$Length = 96,
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan
    )

    Write-Host ($Char * $Length) -ForegroundColor $Color
}

function Write-Title {
    param(
        [string]$Text,
        [string]$SubText = ""
    )

    Write-Host ""
    Write-Rule "=" 96 Cyan
    Write-Host ("  " + $Text) -ForegroundColor Cyan

    if (-not [string]::IsNullOrWhiteSpace($SubText)) {
        Write-Host ("  " + $SubText) -ForegroundColor DarkGray
    }

    Write-Rule "=" 96 Cyan
    Write-Host ""
}

function Require-Command {
    param(
        [string]$Name,
        [string]$InstallHint
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "$Name was not found. Install it with: $InstallHint"
    }

    return $command
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [switch]$Quiet
    )

    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    if (($exitCode -ne 0) -and ($null -ne $exitCode)) {
        $detail = ($output | ForEach-Object { $_.ToString() }) -join "`n"
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = "No additional output."
        }
        throw "$FilePath failed with exit code $exitCode.`n$detail"
    }

    if (-not $Quiet) {
        foreach ($line in $output) {
            if ($null -ne $line) {
                Write-Host ("    " + $line.ToString()) -ForegroundColor DarkGray
            }
        }
    }

    return @($output)
}

function Invoke-GitAllowFailure {
    param(
        [string[]]$Arguments,
        [ref]$ExitCode
    )

    $output = @(& git @Arguments 2>&1)
    $ExitCode.Value = $LASTEXITCODE
    return @($output)
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        Write-Host "  Config file is invalid; default settings will be used." -ForegroundColor DarkYellow
        return $null
    }
}

function Save-Config {
    param(
        [string]$Owner,
        [string]$WorkspaceRoot
    )

    $config = [ordered]@{
        owner = $Owner
        workspaceRoot = $WorkspaceRoot
    }

    $config | ConvertTo-Json | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Resolve-WorkspaceRoot {
    param($Config)

    $defaultRoot = Split-Path -Parent $ToolRoot

    if (($null -eq $Config) -or [string]::IsNullOrWhiteSpace([string]$Config.workspaceRoot)) {
        return $defaultRoot
    }

    $configured = ([string]$Config.workspaceRoot).Trim()
    if ([System.IO.Path]::IsPathRooted($configured)) {
        return [System.IO.Path]::GetFullPath($configured)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $ToolRoot $configured))
}

function Get-GhSession {
    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        return [pscustomobject]@{
            Installed = $false
            Authenticated = $false
            Login = ""
        }
    }

    try {
        & gh auth status -h github.com *> $null
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{
                Installed = $true
                Authenticated = $false
                Login = ""
            }
        }

        $loginOutput = @(& gh api user --jq ".login" 2>$null)
        if (($LASTEXITCODE -eq 0) -and ($loginOutput.Count -gt 0)) {
            $login = ([string]$loginOutput[0]).Trim()
            if (-not [string]::IsNullOrWhiteSpace($login)) {
                return [pscustomobject]@{
                    Installed = $true
                    Authenticated = $true
                    Login = $login
                }
            }
        }
    }
    catch {
    }

    return [pscustomobject]@{
        Installed = $true
        Authenticated = $false
        Login = ""
    }
}

function Resolve-GitHubOwner {
    param(
        $GhSession,
        $Config,
        [string]$WorkspaceRoot
    )

    if ($GhSession.Authenticated -and (-not [string]::IsNullOrWhiteSpace($GhSession.Login))) {
        Save-Config $GhSession.Login $WorkspaceRoot
        return $GhSession.Login
    }

    if (($null -ne $Config) -and (-not [string]::IsNullOrWhiteSpace([string]$Config.owner))) {
        return ([string]$Config.owner).Trim()
    }

    try {
        $gitUser = @(& git config --global github.user 2>$null)
        if (($LASTEXITCODE -eq 0) -and ($gitUser.Count -gt 0)) {
            $candidate = ([string]$gitUser[0]).Trim()
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                Save-Config $candidate $WorkspaceRoot
                return $candidate
            }
        }
    }
    catch {
    }

    Write-Host ""
    Write-Host "  GitHub CLI is not authenticated, so automatic account detection is unavailable." -ForegroundColor Yellow
    Write-Host "  Enter the GitHub username whose public repositories should be synchronized." -ForegroundColor Gray
    Write-Host ""

    do {
        $owner = (Read-Host "  GitHub username").Trim()
    } while ([string]::IsNullOrWhiteSpace($owner))

    Save-Config $owner $WorkspaceRoot
    return $owner
}

function Expand-ObjectArray {
    param($Value)

    if ($null -eq $Value) {
        return @()
    }

    $result = @()
    foreach ($entry in $Value) {
        if ($entry -is [System.Array]) {
            foreach ($inner in $entry) {
                if ($null -ne $inner) {
                    $result += $inner
                }
            }
        }
        elseif ($null -ne $entry) {
            $result += $entry
        }
    }

    return @($result)
}

function Get-RepositoriesWithGh {
    param([string]$Owner)

    $fields = "name,nameWithOwner,url,isPrivate,isFork,isArchived,defaultBranchRef"
    $rawOutput = @(& gh repo list $Owner --limit 1000 --json $fields 2>&1)

    if ($LASTEXITCODE -ne 0) {
        $detail = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"
        throw "Unable to enumerate repositories with GitHub CLI.`n$detail"
    }

    $raw = ($rawOutput | ForEach-Object { $_.ToString() }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $parsed = ConvertFrom-Json -InputObject $raw
    $items = @(Expand-ObjectArray $parsed)
    $repos = @()

    foreach ($item in $items) {
        $defaultBranch = ""
        if (($null -ne $item.defaultBranchRef) -and (-not [string]::IsNullOrWhiteSpace([string]$item.defaultBranchRef.name))) {
            $defaultBranch = [string]$item.defaultBranchRef.name
        }

        $repos += [pscustomobject]@{
            Name = [string]$item.name
            FullName = [string]$item.nameWithOwner
            CloneUrl = ([string]$item.url).TrimEnd('/') + ".git"
            DefaultBranch = $defaultBranch
            IsPrivate = [bool]$item.isPrivate
            IsFork = [bool]$item.isFork
            IsArchived = [bool]$item.isArchived
        }
    }

    return @($repos | Sort-Object -Property Name)
}

function Get-PublicRepositoriesFromApi {
    param([string]$Owner)

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch {
    }

    $headers = @{
        "Accept" = "application/vnd.github+json"
        "User-Agent" = "GitHubCodeCounter-$Version"
    }

    $repos = @()
    $page = 1

    while ($true) {
        $encodedOwner = [Uri]::EscapeDataString($Owner)
        $uri = "https://api.github.com/users/$encodedOwner/repos?per_page=100&page=$page&type=owner&sort=full_name"
        $rawResponse = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        $response = @(Expand-ObjectArray $rawResponse)

        if ($response.Count -eq 0) {
            break
        }

        foreach ($item in $response) {
            $repos += [pscustomobject]@{
                Name = [string]$item.name
                FullName = [string]$item.full_name
                CloneUrl = [string]$item.clone_url
                DefaultBranch = [string]$item.default_branch
                IsPrivate = [bool]$item.private
                IsFork = [bool]$item.fork
                IsArchived = [bool]$item.archived
            }
        }

        if ($response.Count -lt 100) {
            break
        }

        $page++
    }

    return @($repos | Sort-Object -Property Name)
}

function Get-GitHubRepositories {
    param(
        [string]$Owner,
        $GhSession
    )

    if ($GhSession.Authenticated) {
        return [pscustomobject]@{
            Mode = "GitHub CLI (authenticated; private repositories included when accessible)"
            Repositories = @(Get-RepositoriesWithGh $Owner)
        }
    }

    return [pscustomobject]@{
        Mode = "GitHub public API (public repositories only)"
        Repositories = @(Get-PublicRepositoriesFromApi $Owner)
    }
}

function Get-NormalizedGitHubFullNameFromUrl {
    param([string]$Url)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return ""
    }

    $value = $Url.Trim().TrimEnd('/')
    if ($value.EndsWith(".git", [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }

    if ($value -match '(?i)github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+)$') {
        return (($Matches['owner'] + "/" + $Matches['repo']).ToLowerInvariant())
    }

    return ""
}

function Test-OriginMatchesRepository {
    param(
        [string]$RepositoryPath,
        $Repo
    )

    try {
        $origin = @(& git -C $RepositoryPath remote get-url origin 2>$null)
        if (($LASTEXITCODE -ne 0) -or ($origin.Count -eq 0)) {
            return $false
        }

        $actual = Get-NormalizedGitHubFullNameFromUrl ([string]$origin[0])
        $expected = ([string]$Repo.FullName).ToLowerInvariant()
        return (-not [string]::IsNullOrWhiteSpace($actual)) -and ($actual -eq $expected)
    }
    catch {
        return $false
    }
}

function Get-GitWorkingTreeDirty {
    param([string]$RepositoryPath)

    $status = @(& git -C $RepositoryPath status --porcelain 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read git status for: $RepositoryPath"
    }

    return ($status.Count -gt 0)
}

function Get-CurrentBranch {
    param([string]$RepositoryPath)

    $branch = @(& git -C $RepositoryPath rev-parse --abbrev-ref HEAD 2>$null)
    if (($LASTEXITCODE -ne 0) -or ($branch.Count -eq 0)) {
        return ""
    }

    return ([string]$branch[0]).Trim()
}

function Test-RemoteBranchExists {
    param(
        [string]$RepositoryPath,
        [string]$Branch
    )

    if ([string]::IsNullOrWhiteSpace($Branch)) {
        return $false
    }

    & git -C $RepositoryPath show-ref --verify --quiet ("refs/remotes/origin/" + $Branch)
    return ($LASTEXITCODE -eq 0)
}

function Get-AheadBehind {
    param(
        [string]$RepositoryPath,
        [string]$Branch
    )

    $output = @(& git -C $RepositoryPath rev-list --left-right --count ("HEAD...origin/" + $Branch) 2>$null)
    if (($LASTEXITCODE -ne 0) -or ($output.Count -eq 0)) {
        return [pscustomobject]@{ Ahead = -1; Behind = -1 }
    }

    $parts = ([string]$output[0]).Trim() -split '\s+'
    if ($parts.Count -lt 2) {
        return [pscustomobject]@{ Ahead = -1; Behind = -1 }
    }

    return [pscustomobject]@{
        Ahead = [int]$parts[0]
        Behind = [int]$parts[1]
    }
}

function Clone-Repository {
    param(
        $Repo,
        [string]$Destination,
        $GhSession
    )

    if (Test-Path -LiteralPath $Destination) {
        throw "Target folder already exists but is not the expected Git repository: $Destination"
    }

    if ($GhSession.Authenticated) {
        Invoke-External "gh" @("repo", "clone", $Repo.FullName, $Destination, "--", "--quiet") -Quiet | Out-Null
    }
    else {
        Invoke-External "git" @("clone", "--quiet", $Repo.CloneUrl, $Destination) -Quiet | Out-Null
    }
}

function Update-ExistingRepository {
    param(
        $Repo,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath (Join-Path $Destination ".git"))) {
        throw "Folder exists but is not a Git repository: $Destination"
    }

    if (-not (Test-OriginMatchesRepository $Destination $Repo)) {
        throw "Folder exists, but its origin does not match $($Repo.FullName): $Destination"
    }

    Invoke-External "git" @("-C", $Destination, "fetch", "--prune", "origin") -Quiet | Out-Null

    $branch = Get-CurrentBranch $Destination
    if ([string]::IsNullOrWhiteSpace($branch) -or ($branch -eq "HEAD")) {
        return [pscustomobject]@{
            Status = "fetched-detached"
            Message = "remote refreshed; detached HEAD was left unchanged"
            FullyUpdated = $false
        }
    }

    if (-not (Test-RemoteBranchExists $Destination $branch)) {
        return [pscustomobject]@{
            Status = "fetched-local-branch"
            Message = "remote refreshed; current local branch has no origin/$branch"
            FullyUpdated = $false
        }
    }

    $dirty = Get-GitWorkingTreeDirty $Destination
    $delta = Get-AheadBehind $Destination $branch

    if ($dirty) {
        if (($delta.Behind -gt 0) -and ($delta.Ahead -eq 0)) {
            # A fast-forward is safe to attempt even with local edits: Git aborts rather than
            # overwriting conflicting working-tree changes. Never reset/clean a real project.
            $mergeOutput = @(& git -C $Destination merge --ff-only ("origin/" + $branch) 2>&1)
            if ($LASTEXITCODE -eq 0) {
                return [pscustomobject]@{
                    Status = "updated-dirty"
                    Message = "fast-forwarded by $($delta.Behind) commit(s); local uncommitted changes preserved"
                    FullyUpdated = $true
                }
            }
        }

        $message = "remote refreshed; local uncommitted changes preserved"
        if ($delta.Behind -gt 0) {
            $message += "; safe fast-forward could not be applied, still $($delta.Behind) commit(s) behind origin/$branch"
        }
        elseif (($delta.Ahead -gt 0) -and ($delta.Behind -gt 0)) {
            $message += "; local and remote branches have diverged"
        }

        return [pscustomobject]@{
            Status = "fetched-dirty"
            Message = $message
            FullyUpdated = ($delta.Behind -eq 0)
        }
    }

    if (($delta.Ahead -gt 0) -and ($delta.Behind -gt 0)) {
        return [pscustomobject]@{
            Status = "fetched-diverged"
            Message = "remote refreshed; local branch diverged from origin/$branch, so no destructive reset was performed"
            FullyUpdated = $false
        }
    }

    if ($delta.Behind -gt 0) {
        $mergeOutput = @(& git -C $Destination merge --ff-only ("origin/" + $branch) 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $detail = ($mergeOutput | ForEach-Object { $_.ToString() }) -join " | "
            return [pscustomobject]@{
                Status = "fetched-no-ff"
                Message = "remote refreshed; fast-forward update failed: $detail"
                FullyUpdated = $false
            }
        }

        return [pscustomobject]@{
            Status = "updated"
            Message = "fast-forwarded by $($delta.Behind) commit(s)"
            FullyUpdated = $true
        }
    }

    if ($delta.Ahead -gt 0) {
        $upToDateMessage = "remote refreshed; local branch is $($delta.Ahead) commit(s) ahead"
    }
    else {
        $upToDateMessage = "already current"
    }

    return [pscustomobject]@{
        Status = "up-to-date"
        Message = $upToDateMessage
        FullyUpdated = $true
    }
}

function Sync-Repositories {
    param(
        [object[]]$Repositories,
        $GhSession,
        [string]$WorkspaceRoot
    )

    if (-not (Test-Path -LiteralPath $WorkspaceRoot)) {
        New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
    }

    $results = @()
    $total = $Repositories.Count
    $index = 0

    foreach ($repo in $Repositories) {
        $index++
        $destination = Join-Path $WorkspaceRoot $repo.Name
        $privacy = if ($repo.IsPrivate) { "private" } else { "public" }
        $archive = if ($repo.IsArchived) { ", archived" } else { "" }

        Write-Host ("  [{0}/{1}] {2} ({3}{4})" -f $index, $total, $repo.FullName, $privacy, $archive) -ForegroundColor DarkCyan

        if ([string]::IsNullOrWhiteSpace($repo.DefaultBranch)) {
            Write-Host "        skipped: empty repository" -ForegroundColor DarkGray
            $results += [pscustomobject]@{
                Repo = $repo
                Success = $true
                Countable = $false
                FullyUpdated = $true
                Status = "empty"
                Path = ""
                Message = "Empty repository"
            }
            continue
        }

        try {
            if (Test-Path -LiteralPath $destination) {
                $update = Update-ExistingRepository $repo $destination
                $status = $update.Status
                $message = $update.Message
                $fullyUpdated = [bool]$update.FullyUpdated
            }
            else {
                Clone-Repository $repo $destination $GhSession
                $status = "cloned"
                $message = "new repository cloned"
                $fullyUpdated = $true
            }

            $statusColor = if ($fullyUpdated) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow }
            Write-Host ("        {0}: {1}" -f $status, $message) -ForegroundColor $statusColor

            $results += [pscustomobject]@{
                Repo = $repo
                Success = $true
                Countable = $true
                FullyUpdated = $fullyUpdated
                Status = $status
                Path = $destination
                Message = $message
            }
        }
        catch {
            $message = $_.Exception.Message
            $firstLine = ($message -split "`r?`n")[0]
            Write-Host ("        FAILED: " + $firstLine) -ForegroundColor Red

            $results += [pscustomobject]@{
                Repo = $repo
                Success = $false
                Countable = $false
                FullyUpdated = $false
                Status = "failed"
                Path = ""
                Message = $message
            }
        }
    }

    return @($results)
}

function Get-ClocArguments {
    param([string[]]$TargetPaths)

    $arguments = @()
    foreach ($path in $TargetPaths) {
        $arguments += $path
    }

    $arguments += "--exclude-lang=$ExcludedLanguages"
    $arguments += "--exclude-ext=$ExcludedExtensions"
    $arguments += "--exclude-dir=$ExcludedDirs"
    $arguments += "--quiet"

    return @($arguments)
}

function Show-ClocTable {
    param([string[]]$TargetPaths)

    $arguments = Get-ClocArguments $TargetPaths
    & cloc @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "cloc failed (exit code $LASTEXITCODE)"
    }
}

function Get-CodeTotal {
    param([string[]]$TargetPaths)

    $arguments = Get-ClocArguments $TargetPaths
    $arguments += "--json"

    $output = @(& cloc @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "cloc JSON scan failed (exit code $LASTEXITCODE)"
    }

    $raw = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 0
    }

    $data = $raw | ConvertFrom-Json
    if ($null -eq $data.SUM) {
        return 0
    }

    return [int64]$data.SUM.code
}

try {
    Clear-Host

    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    }
    catch {
    }

    if (-not (Test-Path -LiteralPath $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir | Out-Null
    }

    $config = Get-Config
    $workspaceRoot = Resolve-WorkspaceRoot $config

    Write-Rule "=" 96 Cyan
    Write-Host ("   {0} {1}" -f $AppName.ToUpperInvariant(), $Version) -ForegroundColor Cyan
    Write-Host "   Refresh existing project folders first, clone missing GitHub repositories, then count code." -ForegroundColor DarkGray
    Write-Rule "=" 96 Cyan
    Write-Host ""
    Write-Host ("  Tool root     : " + $ToolRoot) -ForegroundColor Gray
    Write-Host ("  Workspace root: " + $workspaceRoot) -ForegroundColor Gray
    Write-Host "  Markdown      : excluded completely" -ForegroundColor Gray
    Write-Host ""

    Require-Command "git" "winget install --id Git.Git -e" | Out-Null
    Require-Command "cloc" "winget install --id AlDanial.Cloc -e" | Out-Null

    $ghSession = Get-GhSession
    $owner = Resolve-GitHubOwner $ghSession $config $workspaceRoot

    Write-Title "STEP 1 - DISCOVER GITHUB REPOSITORIES" ("Account: " + $owner)

    $discovery = Get-GitHubRepositories $owner $ghSession
    $repositories = @($discovery.Repositories)

    Write-Host ("  Source      : " + $discovery.Mode) -ForegroundColor Gray
    Write-Host ("  Repositories: {0}" -f $repositories.Count) -ForegroundColor Green

    if ((-not $ghSession.Authenticated) -and $ghSession.Installed) {
        Write-Host "  Note        : gh is installed but not authenticated; private repositories cannot be listed." -ForegroundColor DarkYellow
        Write-Host "                Run 'gh auth login' if you want private repositories included." -ForegroundColor DarkYellow
    }
    elseif (-not $ghSession.Installed) {
        Write-Host "  Note        : GitHub CLI is not installed; public repositories are synchronized via GitHub API." -ForegroundColor DarkYellow
    }

    if ($repositories.Count -eq 0) {
        throw "No repositories were found for GitHub account '$owner'."
    }

    Write-Title "STEP 2 - REFRESH PROJECT FOLDERS" "Existing sibling projects are fetched/fast-forwarded; missing repositories are cloned"

    $syncResults = @(Sync-Repositories $repositories $ghSession $workspaceRoot)
    $countable = @($syncResults | Where-Object { $_.Success -and $_.Countable -and (-not [string]::IsNullOrWhiteSpace($_.Path)) })
    $fullyUpdated = @($countable | Where-Object { $_.FullyUpdated })
    $preserved = @($countable | Where-Object { -not $_.FullyUpdated })
    $failed = @($syncResults | Where-Object { -not $_.Success })
    $empty = @($syncResults | Where-Object { $_.Status -eq "empty" })
    $cloned = @($syncResults | Where-Object { $_.Status -eq "cloned" })
    $updated = @($syncResults | Where-Object { ($_.Status -eq "updated") -or ($_.Status -eq "updated-dirty") })
    $upToDate = @($syncResults | Where-Object { $_.Status -eq "up-to-date" })

    Write-Host ""
    Write-Host ("  Cloned         : {0}" -f $cloned.Count) -ForegroundColor Gray
    Write-Host ("  Updated        : {0}" -f $updated.Count) -ForegroundColor Gray
    Write-Host ("  Already current: {0}" -f $upToDate.Count) -ForegroundColor Gray
    Write-Host ("  Fetch-only/warn : {0}" -f $preserved.Count) -ForegroundColor $(if ($preserved.Count -gt 0) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Gray })
    Write-Host ("  Empty          : {0}" -f $empty.Count) -ForegroundColor Gray
    Write-Host ("  Failed         : {0}" -f $failed.Count) -ForegroundColor $(if ($failed.Count -gt 0) { [ConsoleColor]::Red } else { [ConsoleColor]::Gray })

    if ($preserved.Count -gt 0) {
        Write-Host ""
        Write-Host "  These repositories were fetched but not destructively overwritten:" -ForegroundColor DarkYellow
        foreach ($item in $preserved) {
            Write-Host ("    - {0}: {1}" -f $item.Repo.FullName, $item.Message) -ForegroundColor Yellow
        }
    }

    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "  Failed repositories are excluded from statistics:" -ForegroundColor DarkYellow
        foreach ($item in $failed) {
            Write-Host ("    - " + $item.Repo.FullName) -ForegroundColor Red
        }
    }

    if ($countable.Count -eq 0) {
        throw "No non-empty GitHub repositories are available for statistics."
    }

    $targetPaths = @($countable | ForEach-Object { $_.Path })

    Write-Title "STEP 3 - ALL REPOSITORIES - TOTAL" "Markdown/Text/dependencies/build output excluded"
    Show-ClocTable -TargetPaths $targetPaths

    Write-Title "STEP 4 - PROJECT RANKING" "Sorted by source code lines"

    $projectStats = @()
    $count = $countable.Count
    $current = 0

    foreach ($item in $countable) {
        $current++
        $folder = Get-Item -LiteralPath $item.Path
        Write-Host ("  Scanning [{0}/{1}] {2}" -f $current, $count, $folder.Name) -ForegroundColor DarkCyan

        $codeCount = Get-CodeTotal -TargetPaths @($folder.FullName)
        $projectStats += [pscustomobject]@{
            Name = $folder.Name
            Path = $folder.FullName
            Code = $codeCount
        }
    }

    $projectStats = @($projectStats | Sort-Object -Property Code -Descending)

    $maxCode = 0
    if ($projectStats.Count -gt 0) {
        $maxCode = [int64]$projectStats[0].Code
    }

    $rank = 0
    foreach ($project in $projectStats) {
        $rank++
        $barWidth = 30
        $filled = 0

        if ($maxCode -gt 0) {
            $filled = [int][Math]::Round(($project.Code / $maxCode) * $barWidth)
        }

        if (($project.Code -gt 0) -and ($filled -lt 1)) {
            $filled = 1
        }

        if ($filled -gt $barWidth) {
            $filled = $barWidth
        }

        $bar = ("#" * $filled) + ("-" * ($barWidth - $filled))
        $rankColor = if ($rank -le 3) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Gray }

        Write-Host (
            "  #{0,-3} {1,-38} {2,12:N0}  [{3}]" -f
            $rank,
            $project.Name,
            $project.Code,
            $bar
        ) -ForegroundColor $rankColor
    }

    Write-Title "STEP 5 - EACH PROJECT" "Full cloc table for every GitHub repository"

    foreach ($project in $projectStats) {
        Write-Title ("PROJECT - " + $project.Name) ("Code lines: {0:N0}" -f $project.Code)
        Show-ClocTable -TargetPaths @($project.Path)
    }

    $grandTotal = Get-CodeTotal -TargetPaths $targetPaths

    Write-Title "DONE" "Refresh and statistics completed"
    Write-Host ("  GitHub account : {0}" -f $owner) -ForegroundColor Gray
    Write-Host ("  Remote repos   : {0}" -f $repositories.Count) -ForegroundColor Gray
    Write-Host ("  Counted repos  : {0}" -f $projectStats.Count) -ForegroundColor Gray
    Write-Host ("  Fully refreshed: {0}" -f $fullyUpdated.Count) -ForegroundColor Gray
    Write-Host ("  Code lines     : {0:N0}" -f $grandTotal) -ForegroundColor Green
    Write-Host ""

    if (($failed.Count -gt 0) -or ($preserved.Count -gt 0)) {
        Write-Host "  Completed with warnings. Review the repository refresh messages above." -ForegroundColor Yellow
        exit 2
    }
}
catch {
    Write-Host ""
    Write-Rule "!" 96 Red
    Write-Host "  ERROR" -ForegroundColor Red
    Write-Rule "!" 96 Red
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    try {
        if (-not (Test-Path -LiteralPath $LogDir)) {
            New-Item -ItemType Directory -Path $LogDir | Out-Null
        }

        @(
            "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "Version: $Version"
            "ToolRoot: $ToolRoot"
            ""
            $_.Exception.ToString()
        ) | Set-Content -LiteralPath $ErrorLog -Encoding UTF8

        Write-Host ("  Error log: " + $ErrorLog) -ForegroundColor Yellow
        Write-Host ""
    }
    catch {
    }

    exit 1
}
