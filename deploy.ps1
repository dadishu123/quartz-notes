Write-Host "=== Quartz Deploy Start ==="


# Go to quartz directory
Set-Location "D:\Program Files\Obsidian\quartz-5"


# Check content
if (!(Test-Path ".\content")) {
    Write-Host "ERROR: content folder missing"
    exit 1
}


Write-Host "Building Quartz..."

npx quartz build

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Quartz build failed"
    exit 1
}


Write-Host "Git status..."

git add .


$changes = git status --porcelain

if ($changes) {

    git commit -m "update notes"

    git push

    Write-Host "Deploy pushed successfully"

}
else {

    Write-Host "No changes detected"

}


Write-Host "=== Done ==="