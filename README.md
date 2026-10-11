# GitHubCodeCounter

Windows tool for refreshing GitHub repositories and calculating code statistics.

## Usage

Place `GitHubCodeCounter` alongside your local project folders:

```text
Projects/
├─ GitHubCodeCounter/
├─ OCRCaptureTool/
├─ ScreenAssistant/
├─ SlimeLounge/
└─ ...
```

Run `GitHubCodeCounter.bat`.

The tool will:

1. Read the current repository list from GitHub.
2. Refresh existing local Git repositories with `git fetch --prune`.
3. Fast-forward clean working trees when the remote branch has newer commits.
4. Preserve repositories that contain local uncommitted changes instead of using `reset --hard` or `clean`.
5. Clone GitHub repositories that do not yet exist locally.
6. Run `cloc` only after repository refresh is complete.

Markdown files are excluded from statistics.

## Requirements

- Git
- cloc
- GitHub CLI (`gh`) is recommended for authenticated/private repository discovery.

```powershell
winget install --id Git.Git -e
winget install --id AlDanial.Cloc -e
winget install --id GitHub.cli -e
gh auth login
```

Without an authenticated GitHub CLI session, public repositories are discovered through the GitHub Public API.

## Local files

The tool can create these files/directories while running:

```text
GitHubCodeCounter.config.json
logs/
```

They are excluded by `.gitignore` and should not be committed.
