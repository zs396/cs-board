$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$python = Join-Path $root ".venv\Scripts\python.exe"
$webRoot = Join-Path $root "web"
$stateDir = Join-Path $root ".webapp"
$launcherErrorLog = Join-Path $stateDir "launcher-error.log"
$backendOutputLog = Join-Path $stateDir "backend-output.log"
$backendErrorLog = Join-Path $stateDir "backend-error.log"
$frontendOutputLog = Join-Path $stateDir "frontend-output.log"
$frontendErrorLog = Join-Path $stateDir "frontend-error.log"
$expectedPipelineVersion = "narrated_deck_v8_oil_visual"
$backendUpdateDeferred = $false
$appUrl = "http://127.0.0.1:13000"

New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
Remove-Item -LiteralPath $launcherErrorLog -Force -ErrorAction SilentlyContinue

function Test-BackendReady {
    if ($script:backendUpdateDeferred) {
        return $true
    }
    try {
        $health = Invoke-RestMethod "http://127.0.0.1:18765/api/health" -TimeoutSec 2
        return $health.pipeline_version -eq $expectedPipelineVersion
    } catch {
        return $false
    }
}

function Stop-StaleBackend {
    try {
        $health = Invoke-RestMethod "http://127.0.0.1:18765/api/health" -TimeoutSec 2
        if ($health.pipeline_version -eq $expectedPipelineVersion) {
            return
        }
        $jobs = Invoke-RestMethod "http://127.0.0.1:18765/api/jobs?limit=100" -TimeoutSec 3
        $busyJobs = @($jobs.items | Where-Object { $_.status -eq "running" -or $_.status -eq "queued" })
        if ($busyJobs.Count -gt 0) {
            $script:backendUpdateDeferred = $true
            Write-Host "A video is still being generated. The pipeline upgrade is deferred to protect it." -ForegroundColor Yellow
            return
        }
        $listener = Get-NetTCPConnection -LocalPort 18765 -State Listen -ErrorAction Stop
        if ($listener.OwningProcess) {
            Write-Host "An older video pipeline is running. Restarting it..." -ForegroundColor Yellow
            Stop-Process -Id $listener.OwningProcess -Force
            Start-Sleep -Milliseconds 700
        }
    } catch {
        # No responding stale backend; the normal startup path handles this.
    }
}

function Test-FrontendReady {
    try {
        Invoke-WebRequest $appUrl -UseBasicParsing -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Open-DesktopWindow {
    $edgeCandidates = @(
        "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    )
    $chromeCandidates = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )

    $browser = @($edgeCandidates + $chromeCandidates) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if ($browser) {
        Start-Process -FilePath $browser -ArgumentList "--app=$appUrl", "--start-maximized"
        return
    }

    # Fallback for systems without Edge/Chrome: open the local URL normally.
    Start-Process $appUrl
}

try {
    Write-Host "Starting the whiteboard video workshop..." -ForegroundColor Cyan
    Write-Host "Local-only URL: $appUrl"

    Stop-StaleBackend
    if (Test-BackendReady) {
        if ($backendUpdateDeferred) {
            Write-Host "Backend is busy; run this launcher again after the current task finishes to load the upgrade." -ForegroundColor Yellow
        } else {
            Write-Host "Backend is already running." -ForegroundColor DarkGray
        }
    } else {
        Remove-Item -LiteralPath $backendOutputLog, $backendErrorLog -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath $python -ArgumentList "-m", "uvicorn", "webapp.server:app", "--host", "127.0.0.1", "--port", "18765" -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $backendOutputLog -RedirectStandardError $backendErrorLog
    }

    if (Test-FrontendReady) {
        Write-Host "Frontend is already running." -ForegroundColor DarkGray
    } else {
        Remove-Item -LiteralPath $frontendOutputLog, $frontendErrorLog -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath "npm.cmd" -ArgumentList "run", "dev" -WorkingDirectory $webRoot -WindowStyle Hidden -RedirectStandardOutput $frontendOutputLog -RedirectStandardError $frontendErrorLog
    }

    $backendReady = $false
    $frontendReady = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        $backendReady = Test-BackendReady
        $frontendReady = Test-FrontendReady
        if ($backendReady -and $frontendReady) {
            break
        }
        Start-Sleep -Seconds 1
    }

    if (-not $backendReady) {
        throw "Backend failed to start. See .webapp\backend-error.log."
    }
    if (-not $frontendReady) {
        throw "Frontend failed to start. See .webapp\frontend-error.log."
    }

    Write-Host "Ready. Opening desktop-style app window..." -ForegroundColor Green
    Open-DesktopWindow
} catch {
    $message = "{0}`r`n{1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message
    Set-Content -LiteralPath $launcherErrorLog -Value $message -Encoding UTF8
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
