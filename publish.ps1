# ============================================================
# Quartz Publish Automation v2
# Sync -> Build -> Log -> Commit -> Push
# -> Wait GitHub Actions -> Open Website
# ============================================================


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$QuartzPath = "D:\Program Files\Obsidian\quartz-5"

$Source = "D:\Program Files\Obsidian\Wenqiang_files\public"

$Target = "$QuartzPath\content"

$LogFile = "$QuartzPath\publish-log.md"

$Website = "https://dadishu123.github.io/quartz-notes/"

$GitHubOwner = "dadishu123"

$GitHubRepo = "quartz-notes"

$WorkflowName = "Deploy Quartz to GitHub Pages"

$PushRetries = 3

$NetworkRetrySeconds = 10

$ActionPollSeconds = 15

$ActionDiscoveryTimeoutMinutes = 2

$ActionCompletionTimeoutMinutes = 10


# ------------------------------------------------------------
# Local runtime log
# This log is NOT inside the Git repository.
# ------------------------------------------------------------

$RuntimeLogDir = Join-Path $env:LOCALAPPDATA "QuartzPublish"

if (!(Test-Path $RuntimeLogDir))
{
    New-Item -ItemType Directory -Path $RuntimeLogDir -Force | Out-Null
}

$RuntimeLog = Join-Path $RuntimeLogDir "publish-runtime.log"


# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------

function Write-RuntimeLog($Text)
{
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Add-Content `
        -Path $RuntimeLog `
        -Value "[$timestamp] $Text" `
        -Encoding UTF8
}


function Error-Exit($step, $msg)
{
    Write-Host ""
    Write-Host "========================================"
    Write-Host " PUBLISH FAILED"
    Write-Host " Step: $step"
    Write-Host " Reason:"
    Write-Host $msg
    Write-Host "========================================"

    Write-RuntimeLog "FAILED | Step=$step | Reason=$msg"

    exit 1
}


function Write-ReleaseLog($content)
{
    Add-Content `
        -Path $LogFile `
        -Value $content `
        -Encoding UTF8
}


function Get-RemoteMainSha
{
    param(
        [int]$Attempts = 3
    )

    for ($i = 1; $i -le $Attempts; $i++)
    {
        Write-Host "Checking GitHub connection ($i/$Attempts)..."

        $result = (
            & git ls-remote origin refs/heads/main 2>&1 |
            Out-String
        ).Trim()

        if (($LASTEXITCODE -eq 0) -and $result)
        {
            $sha = ($result -split "\s+")[0]

            return $sha
        }

        if ($i -lt $Attempts)
        {
            Write-Host "GitHub connection failed. Retrying in $NetworkRetrySeconds seconds..."

            Start-Sleep -Seconds $NetworkRetrySeconds
        }
    }

    return $null
}


function Invoke-GitHubApi
{
    param(
        [string]$Uri
    )

    $Headers = @{
        "User-Agent" = "Quartz-Publish-Script"
        "Accept"     = "application/vnd.github+json"
    }

    # Reuse the proxy configured for Git when possible.
    $GitProxy = (
        git config --global --get https.proxy 2>$null
    )

    if ($GitProxy)
    {
        return Invoke-RestMethod `
            -Uri $Uri `
            -Headers $Headers `
            -Method Get `
            -Proxy $GitProxy `
            -TimeoutSec 30
    }
    else
    {
        return Invoke-RestMethod `
            -Uri $Uri `
            -Headers $Headers `
            -Method Get `
            -TimeoutSec 30
    }
}


function Wait-GitHubWorkflow
{
    param(
        [string]$CommitSha
    )

    Write-Host ""
    Write-Host "[7/8] Wait for GitHub Pages deployment"
    Write-Host "Commit: $CommitSha"
    Write-Host ""

    $ApiUrl =
        "https://api.github.com/repos/$GitHubOwner/$GitHubRepo/actions/runs?head_sha=$CommitSha&event=push&per_page=20"


    # --------------------------------------------------------
    # Phase A: wait until GitHub creates the workflow run
    # --------------------------------------------------------

    $DiscoveryDeadline =
        (Get-Date).AddMinutes($ActionDiscoveryTimeoutMinutes)

    $Run = $null


    while ((Get-Date) -lt $DiscoveryDeadline)
    {
        try
        {
            $Response = Invoke-GitHubApi $ApiUrl

            $Run = @(
                $Response.workflow_runs |
                Where-Object {
                    $_.name -eq $WorkflowName
                } |
                Sort-Object created_at -Descending
            ) | Select-Object -First 1


            if ($Run)
            {
                Write-Host "GitHub Actions run detected."
                Write-Host "Run URL: $($Run.html_url)"
                break
            }
        }
        catch
        {
            Write-Host "GitHub API temporarily unavailable:"
            Write-Host $_.Exception.Message
        }


        Write-Host "Waiting for GitHub Actions to start..."

        Start-Sleep -Seconds $ActionPollSeconds
    }


    if (!$Run)
    {
        Error-Exit `
            "GitHub Actions" `
            "No '$WorkflowName' workflow run was found for commit $CommitSha within $ActionDiscoveryTimeoutMinutes minutes."
    }


    # --------------------------------------------------------
    # Phase B: wait until workflow completes
    # --------------------------------------------------------

    $CompletionDeadline =
        (Get-Date).AddMinutes($ActionCompletionTimeoutMinutes)


    while ((Get-Date) -lt $CompletionDeadline)
    {
        try
        {
            $Response = Invoke-GitHubApi $ApiUrl

            $Run = @(
                $Response.workflow_runs |
                Where-Object {
                    $_.name -eq $WorkflowName
                } |
                Sort-Object created_at -Descending
            ) | Select-Object -First 1


            if (!$Run)
            {
                Write-Host "Workflow temporarily not visible. Retrying..."

                Start-Sleep -Seconds $ActionPollSeconds

                continue
            }


            Write-Host (
                "GitHub Actions: status={0}, conclusion={1}" `
                -f $Run.status, $Run.conclusion
            )


            if ($Run.status -eq "completed")
            {
                if ($Run.conclusion -eq "success")
                {
                    Write-Host ""
                    Write-Host "GitHub Pages deployment completed successfully."

                    Write-RuntimeLog `
                        "SUCCESS | Commit=$CommitSha | Workflow=$($Run.html_url)"

                    return $Run.html_url
                }
                else
                {
                    Error-Exit `
                        "GitHub Actions" `
                        "Workflow finished with conclusion '$($Run.conclusion)'. Check: $($Run.html_url)"
                }
            }
        }
        catch
        {
            Write-Host "GitHub API check failed:"
            Write-Host $_.Exception.Message
            Write-Host "Will retry..."
        }


        Start-Sleep -Seconds $ActionPollSeconds
    }


    Error-Exit `
        "GitHub Actions" `
        "Deployment did not finish within $ActionCompletionTimeoutMinutes minutes."
}



# ============================================================
# START
# ============================================================

Write-Host ""
Write-Host "========================================"
Write-Host " Quartz Publish Automation v2"
Write-Host "========================================"


Set-Location $QuartzPath


# ------------------------------------------------------------
# Step 1: Safety check
# ------------------------------------------------------------

Write-Host ""
Write-Host "[1/8] Safety check"


if (!(Test-Path $Source))
{
    Error-Exit `
        "Safety Check" `
        "Source folder not found: $Source"
}


if (!(Test-Path $Target))
{
    Error-Exit `
        "Safety Check" `
        "Quartz content folder not found: $Target"
}


$MarkdownFiles = @(
    Get-ChildItem `
        -Path $Source `
        -Filter "*.md" `
        -File `
        -Recurse `
        -ErrorAction SilentlyContinue
)


if ($MarkdownFiles.Count -eq 0)
{
    Error-Exit `
        "Safety Check" `
        "No Markdown files were found in the Obsidian public folder. Publishing was stopped to prevent /MIR from accidentally deleting the whole website."
}


Write-Host "Markdown files found: $($MarkdownFiles.Count)"
Write-Host "Safety check passed."


# ------------------------------------------------------------
# Step 2: Sync
# ------------------------------------------------------------

Write-Host ""
Write-Host "[2/8] Sync Obsidian public notes"


robocopy `
	$Source `
	$Target `
	/MIR `
	/XD ".obsidian" `
	/R:3 `
	/W:5


$RoboCopyExitCode = $LASTEXITCODE


# Robocopy codes 0-7 are considered success.
if ($RoboCopyExitCode -gt 7)
{
    Error-Exit `
        "Sync" `
        "Robocopy failed with code $RoboCopyExitCode."
}

Write-Host "[Sync Check]"

git status --short


Write-Host "Sync completed."


# ------------------------------------------------------------
# Step 3: Build Quartz
# ------------------------------------------------------------

Write-Host ""
Write-Host "[3/8] Build Quartz"


npx quartz build


if ($LASTEXITCODE -ne 0)
{
    Error-Exit `
        "Quartz Build" `
        "npx quartz build failed."
}


Write-Host "Build completed."


# ------------------------------------------------------------
# Step 4: Detect changes + generate release log
# ------------------------------------------------------------

Write-Host ""
Write-Host "[4/8] Detect changes"


$WorkingStatus = @(
    git -c core.quotepath=false status --porcelain
)


$RealChanges = @(
    $WorkingStatus |
    Where-Object {
        $_ -notmatch "publish-log\.md$"
    }
)


$CommitCreated = $false


if ($RealChanges.Count -gt 0)
{
    Write-Host ""
    Write-Host "Changes detected:"


    $ChangedFiles = @()


    foreach ($Line in $RealChanges)
    {
        Write-Host "  $Line"

        if ($Line.Length -ge 4)
        {
            $ChangedFiles += $Line.Substring(3)
        }
        else
        {
            $ChangedFiles += $Line
        }
    }


    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $CommitMessage =
        "update notes $Time"


    $ChangedFilesText =
        ($ChangedFiles |
        ForEach-Object {
            "- $_"
        }) -join "`r`n"


    # IMPORTANT:
    # Generate the release log BEFORE git add / commit.
    # Therefore this log belongs to the CURRENT release,
    # not the next release.
    $ReleaseEntry = @"

## $Time

Commit message:

$CommitMessage

Changed files:

$ChangedFilesText

Remote verification:

GitHub Pages deployment will be verified automatically by publish.ps1.

---------------------

"@


    Write-ReleaseLog $ReleaseEntry


    Write-Host ""
    Write-Host "Release log generated."
}
else
{
    Write-Host "No new note changes detected."
}


# ------------------------------------------------------------
# Step 5: Git add + commit
# ------------------------------------------------------------

Write-Host ""
Write-Host "[5/8] Git add / commit"


git add -A


if ($LASTEXITCODE -ne 0)
{
    Error-Exit `
        "Git Add" `
        "git add -A failed."
}


$StagedChanges = git diff --cached --name-only


if ($StagedChanges)
{
    # If CommitMessage was not created above, this may be
    # a leftover change from an earlier failed run.
    if (!$CommitMessage)
    {
        $CommitMessage =
            "update notes " +
            (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }


    git commit -m $CommitMessage


    if ($LASTEXITCODE -ne 0)
    {
        Error-Exit `
            "Git Commit" `
            "git commit failed."
    }


    $CommitCreated = $true

    Write-Host "Commit created."
}
else
{
    Write-Host "No new commit required."
}


# ------------------------------------------------------------
# Step 6: GitHub connectivity + push
# ------------------------------------------------------------

Write-Host ""
Write-Host "[6/8] GitHub connectivity and push"


$LocalSha = (
    git rev-parse HEAD
).Trim()


$ShortSha = (
    git rev-parse --short HEAD
).Trim()


Write-Host "Local commit: $ShortSha"


$RemoteSha = Get-RemoteMainSha -Attempts 3


if (!$RemoteSha)
{
    Error-Exit `
        "GitHub Connection" `
        "Git cannot reach GitHub after 3 attempts.

Check:
1. Proxy software is running.
2. Git http.proxy / https.proxy settings.
3. Proxy port (currently expected to be your configured local proxy).
4. Internet connection.

Your local commit is safe and can be pushed later by running publish.ps1 again."
}


# ------------------------------------------------------------
# Nothing new to push
# ------------------------------------------------------------

if ($RemoteSha -eq $LocalSha)
{
    Write-Host ""
    Write-Host "Local and GitHub commits are already identical."
    Write-Host "Nothing needs to be pushed."

    Write-RuntimeLog `
        "NOOP | Commit=$ShortSha | Nothing to publish"

    Write-Host ""
    Write-Host "========================================"
    Write-Host " Nothing new to publish"
    Write-Host "========================================"

    exit 0
}


# ------------------------------------------------------------
# Check that remote history is an ancestor of local history.
# This prevents accidentally overwriting newer remote commits.
# ------------------------------------------------------------

git merge-base --is-ancestor $RemoteSha $LocalSha


if ($LASTEXITCODE -ne 0)
{
    Error-Exit `
        "Git Sync" `
        "GitHub main is not an ancestor of your local main.

The remote repository may contain newer commits.

Do NOT force push.

Suggested next step:
git pull --rebase origin main"
}


# ------------------------------------------------------------
# Push with retry
# ------------------------------------------------------------

$PushSucceeded = $false


for ($Attempt = 1; $Attempt -le $PushRetries; $Attempt++)
{
    Write-Host ""
    Write-Host "git push attempt $Attempt/$PushRetries..."


    git push origin main


    if ($LASTEXITCODE -eq 0)
    {
        $PushSucceeded = $true
        break
    }


    if ($Attempt -lt $PushRetries)
    {
        Write-Host ""
        Write-Host "Push failed."
        Write-Host "Retrying in $NetworkRetrySeconds seconds..."

        Start-Sleep -Seconds $NetworkRetrySeconds
    }
}


if (!$PushSucceeded)
{
    Error-Exit `
        "Git Push" `
        "git push failed after $PushRetries attempts.

Possible reasons:
- Proxy connection failed
- SSL/TLS handshake failed
- GitHub temporarily unavailable
- Internet connection problem

The commit remains safely stored locally.
Fix the connection and run publish.ps1 again."
}


# Verify that GitHub really received the commit.

$RemoteShaAfterPush =
    Get-RemoteMainSha -Attempts 3


if ($RemoteShaAfterPush -ne $LocalSha)
{
    Error-Exit `
        "Git Push Verification" `
        "git push appeared to finish, but GitHub main does not match local HEAD."
}


Write-Host ""
Write-Host "GitHub received commit $ShortSha successfully."


# ------------------------------------------------------------
# Step 7: Wait for GitHub Actions / Pages
# ------------------------------------------------------------

$WorkflowUrl =
    Wait-GitHubWorkflow -CommitSha $LocalSha


# ------------------------------------------------------------
# Step 8: Open deployed website
# ------------------------------------------------------------

Write-Host ""
Write-Host "[8/8] Open deployed website"


# Give GitHub Pages a few extra seconds after deploy job success.
Start-Sleep -Seconds 10


# Cache-busting query parameter.
# This avoids accidentally viewing an old browser-cached homepage.
$WebsiteWithVersion =
    $Website + "?deploy=" + $ShortSha


Write-Host ""
Write-Host "========================================"
Write-Host " PUBLISH SUCCESSFUL"
Write-Host ""
Write-Host " Commit:"
Write-Host " $LocalSha"
Write-Host ""
Write-Host " GitHub Actions:"
Write-Host " $WorkflowUrl"
Write-Host ""
Write-Host " Website:"
Write-Host " $WebsiteWithVersion"
Write-Host "========================================"


Write-RuntimeLog `
    "SUCCESS | Commit=$LocalSha | Website=$Website"


Start-Process $WebsiteWithVersion