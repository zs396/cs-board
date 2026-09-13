$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Get-VersionText([string]$command, [string[]]$arguments) {
    try {
        $output = & $command @arguments 2>&1 | Select-Object -First 1
        return [string]$output
    } catch {
        return ""
    }
}

function Ensure-WingetPackage([string]$commandName, [string]$packageId, [string]$label) {
    if (Get-Command $commandName -ErrorAction SilentlyContinue) {
        Write-Host "[OK] $label" -ForegroundColor Green
        return
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "$label is missing and winget is unavailable. Install $label, then run this installer again."
    }
    Write-Host "Installing $label..." -ForegroundColor Cyan
    & winget.exe install --id $packageId --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install $label with winget."
    }
    Refresh-Path
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "$label was installed but is not visible in PATH yet. Restart Windows once, then run this installer again."
    }
}

Write-Host "Whiteboard Workshop - desktop setup" -ForegroundColor Cyan
Write-Host "This setup keeps the web UI and backend bound to 127.0.0.1 only." -ForegroundColor DarkGray

Ensure-WingetPackage "python.exe" "Python.Python.3.11" "Python 3.11+"
$pythonVersion = Get-VersionText "python.exe" @("--version")
if ($pythonVersion -notmatch "Python\s+(\d+)\.(\d+)") {
    throw "Python version could not be detected."
}
if ([int]$Matches[1] -lt 3 -or ([int]$Matches[1] -eq 3 -and [int]$Matches[2] -lt 11)) {
    throw "Python 3.11+ is required; detected: $pythonVersion"
}

Ensure-WingetPackage "node.exe" "OpenJS.NodeJS.LTS" "Node.js"
$nodeVersion = (& node.exe --version).Trim().TrimStart('v')
$nodeMajor = [int]($nodeVersion.Split('.')[0])
if ($nodeMajor -lt 22) {
    throw "Node.js 22.13+ is required; detected: $nodeVersion"
}

Ensure-WingetPackage "ffmpeg.exe" "Gyan.FFmpeg" "FFmpeg"
if (-not (Get-Command ffprobe.exe -ErrorAction SilentlyContinue)) {
    throw "FFprobe is missing after FFmpeg setup."
}

Write-Host "Preparing Python environment..." -ForegroundColor Cyan
& python.exe (Join-Path $root "scripts\prepare_env.py")
if ($LASTEXITCODE -ne 0) { throw "Python environment preparation failed." }

$venvPython = Join-Path $root ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) { throw "Virtual environment was not created." }
& $venvPython -m pip install --disable-pip-version-check -r (Join-Path $root "webapp\requirements.txt")
if ($LASTEXITCODE -ne 0) { throw "Backend dependency installation failed." }

Write-Host "Installing frontend dependencies..." -ForegroundColor Cyan
Push-Location (Join-Path $root "web")
& npm.cmd ci
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Frontend dependency installation failed." }
Pop-Location

Write-Host "Installing video renderer dependencies..." -ForegroundColor Cyan
Push-Location (Join-Path $root "video_renderer")
& npm.cmd ci
if ($LASTEXITCODE -ne 0) { Pop-Location; throw "Video renderer dependency installation failed." }
Pop-Location

Write-Host "Creating desktop shortcut..." -ForegroundColor Cyan
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "白板声画工坊.lnk"
$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:WINDIR "System32\wscript.exe"
$shortcut.Arguments = '"' + (Join-Path $root "启动桌面版.vbs") + '"'
$shortcut.WorkingDirectory = $root
$shortcut.Description = "白板声画工坊（本机安全版）"
$shortcut.IconLocation = (Join-Path $env:SystemRoot "System32\shell32.dll") + ",220"
$shortcut.Save()

Write-Host "" 
Write-Host "Desktop setup completed." -ForegroundColor Green
Write-Host "Double-click the '白板声画工坊' shortcut on the desktop to start it." -ForegroundColor Green
Write-Host "First use still requires your own OpenLux API key and a reachable IndexTTS 2.5 service." -ForegroundColor Yellow
