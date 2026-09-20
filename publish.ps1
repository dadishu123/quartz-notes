# ==============================
# Quartz Publish Automation
# Sync + Deploy + Error Report
# ==============================


$QuartzPath = "D:\Program Files\Obsidian\quartz-5"

$Source = "D:\Program Files\Obsidian\Wenqiang_files\public"

$Target = "$QuartzPath\content"


function Error-Exit($step, $msg)
{
    Write-Host ""
    Write-Host "============================="
    Write-Host " PUBLISH FAILED"
    Write-Host " Step: $step"
    Write-Host " Reason:"
    Write-Host $msg
    Write-Host "============================="
    exit 1
}


Write-Host "=== Quartz Publish Start ==="


# ------------------------------
# Step 1 Sync
# ------------------------------

Write-Host ""
Write-Host "[1/5] Sync Obsidian public notes"


if (!(Test-Path $Source))
{
    Error-Exit "Sync" "Source folder not found: $Source"
}


if (!(Test-Path $Target))
{
    Error-Exit "Sync" "Quartz content folder not found: $Target"
}



robocopy $Source $Target /MIR /XD ".obsidian"


if ($LASTEXITCODE -gt 7)
{
    Error-Exit "Sync" "Robocopy failed with code $LASTEXITCODE"
}


Write-Host "Sync completed"



# ------------------------------
# Step 2 Build Quartz
# ------------------------------

Write-Host ""
Write-Host "[2/5] Build Quartz"


Set-Location $QuartzPath


npx quartz build


if ($LASTEXITCODE -ne 0)
{
    Error-Exit "Quartz Build" "npx quartz build failed"
}


Write-Host "Build completed"



# ------------------------------
# Step 3 Git Add
# ------------------------------

Write-Host ""
Write-Host "[3/5] Git add"


git add .


if ($LASTEXITCODE -ne 0)
{
    Error-Exit "Git Add" "git add failed"
}



# ------------------------------
# Step 4 Commit
# ------------------------------

Write-Host ""
Write-Host "[4/5] Git commit"


$status = git status --porcelain


if ($status)
{

    git commit -m "update notes"


    if ($LASTEXITCODE -ne 0)
    {
        Error-Exit "Git Commit" "git commit failed"
    }

}
else
{
    Write-Host "No changes detected"
}



# ------------------------------
# Step 5 Push
# ------------------------------

Write-Host ""
Write-Host "[5/5] Git push"


git push


if ($LASTEXITCODE -ne 0)
{
    Error-Exit "Git Push" "
GitHub connection failed.

Possible reasons:
- Network problem
- Proxy problem
- GitHub unavailable
- Authentication issue
"
}



Write-Host ""
Write-Host "============================="
Write-Host " Publish Successful"
Write-Host " Website will update after GitHub Pages build"
Write-Host "============================="