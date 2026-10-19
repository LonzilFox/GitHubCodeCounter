# GitHubCodeCounter

A Windows command-line tool that refreshes your GitHub repositories and reports source-code statistics separately from data/configuration files.

## Usage

Place this folder alongside your local project folders and run `GitHubCodeCounter.bat`.

The tool refreshes existing Git repositories safely, clones missing repositories, and then reports:

- Source-code lines by language and project.
- JSON, TXT, XML, YAML, CSV, TOML, INI, and other data/configuration files in a separate table.
- File counts and line counts for each data/configuration extension.

Markdown files are excluded completely. Data/configuration files are excluded from the source-code totals. GitHub forks are excluded from statistics by default. `Wand-Enhancer` is also excluded by default.

## Requirements

- Git for Windows
- Windows Package Manager (`winget`) if `cloc` is not already available
- GitHub CLI is optional; it is recommended if private repositories should be included

The launcher checks for `cloc` before running. If it is missing, the tool installs it with:

```powershell
winget install --id AlDanial.Cloc -e
```

Without an authenticated GitHub CLI session, the tool can discover public repositories through the GitHub API only.

## Local settings

The tool creates `GitHubCodeCounter.config.json` on first run. It is ignored by Git and can be edited locally:

- `excludedRepositories`: repository names or `OWNER/REPO` names excluded from all statistics. The default is `Wand-Enhancer`.
- `includeForks`: set to `true` to include GitHub-marked forks in statistics; the default is `false`.
- `workspaceRoot`: the parent directory containing your project folders.

Local logs and configuration are excluded from Git commits.
