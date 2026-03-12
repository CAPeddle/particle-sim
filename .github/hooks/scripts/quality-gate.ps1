#!/usr/bin/env pwsh
# .github/hooks/scripts/quality-gate.ps1
#
# Copilot agentStop hook — runs clang-format AND clang-tidy on every C++ file
# modified during the agent session.
#
# Receives agent event JSON via stdin.
# Exits non-zero if any violation is found.
#
# Requirements:
#   - clang-format in PATH
#   - clang-tidy in PATH
#   - compile_commands.json produced by the build system (for clang-tidy)
#
# CUDA Notes:
#   - clang-format runs on .cu/.cuh files (formatting supported)
#   - clang-tidy SKIPS .cu/.cuh files (limited CUDA support)

$ErrorActionPreference = "Stop"

# --- Configuration ---
$BuildDir = "build"   # Path to CMake build directory containing compile_commands.json

# --- Read agent event from stdin ---
$eventJson = $null
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
        $eventJson = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    }
} catch { }

$status = if ($eventJson) { $eventJson.status } else { "unknown" }

Write-Host ""
Write-Host "=== Quality Gate (agentStop) ===" -ForegroundColor Cyan
Write-Host "Agent status: $status" -ForegroundColor DarkGray

# --- Collect modified C++ files ---
$formatExtensions = @('.cpp', '.cc', '.h', '.hpp', '.hxx', '.cxx', '.cu', '.cuh')
$tidyExtensions = @('.cpp', '.cc', '.h', '.hpp', '.hxx', '.cxx')

$allChangedFiles = @()
$allChangedFiles += git diff --name-only 2>$null
$allChangedFiles += git diff --cached --name-only 2>$null
$allChangedFiles = $allChangedFiles | Sort-Object -Unique | Where-Object { Test-Path $_ }

$formatFiles = $allChangedFiles | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_).ToLower()
    $formatExtensions -contains $ext
}

$tidyFiles = $allChangedFiles | Where-Object {
    $ext = [System.IO.Path]::GetExtension($_).ToLower()
    $tidyExtensions -contains $ext
}

if ($formatFiles.Count -eq 0) {
    Write-Host "No modified C++ files found — nothing to check." -ForegroundColor DarkGray
    exit 0
}

Write-Host "Checking $($formatFiles.Count) file(s) for format, $($tidyFiles.Count) for tidy..." -ForegroundColor DarkGray

$overallFailures = @()

# =========================================================
# Gate 1: clang-format (includes CUDA files)
# =========================================================
if (-not (Get-Command clang-format -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: clang-format not found in PATH — skipping format check." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "--- clang-format ---" -ForegroundColor DarkGray
    $formatFailures = @()
    foreach ($file in $formatFiles) {
        $null = & clang-format --dry-run --Werror --style=file:.clang-format $file 2>&1
        if ($LASTEXITCODE -ne 0) {
            $formatFailures += $file
        }
    }
    if ($formatFailures.Count -eq 0) {
        Write-Host "✅ clang-format: all $($formatFiles.Count) file(s) compliant." -ForegroundColor Green
    } else {
        Write-Host "❌ clang-format violations in $($formatFailures.Count) file(s):" -ForegroundColor Red
        foreach ($f in $formatFailures) { Write-Host "   $f" -ForegroundColor Red }
        Write-Host "Fix: clang-format -i --style=file:.clang-format <file>" -ForegroundColor Yellow
        $overallFailures += $formatFailures
    }
}

# =========================================================
# Gate 2: clang-tidy (skips CUDA files)
# =========================================================
if ($tidyFiles.Count -eq 0) {
    Write-Host "No non-CUDA C++ files to check with clang-tidy." -ForegroundColor DarkGray
} elseif (-not (Get-Command clang-tidy -ErrorAction SilentlyContinue)) {
    Write-Host "WARNING: clang-tidy not found in PATH — skipping tidy check." -ForegroundColor Yellow
} elseif (-not (Test-Path "$BuildDir/compile_commands.json")) {
    Write-Host "WARNING: compile_commands.json not found at $BuildDir/compile_commands.json" -ForegroundColor Yellow
    Write-Host "         Build the project first to generate compile commands, then re-run." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "--- clang-tidy (skipping .cu/.cuh files) ---" -ForegroundColor DarkGray
    $tidyFailures = @()
    foreach ($file in $tidyFiles) {
        $output = & clang-tidy -p $BuildDir $file 2>&1
        if ($LASTEXITCODE -ne 0) {
            $tidyFailures += $file
            Write-Host "   ❌ $file" -ForegroundColor Red
            Write-Host $output -ForegroundColor DarkRed
        }
    }
    if ($tidyFailures.Count -eq 0) {
        Write-Host "✅ clang-tidy: all $($tidyFiles.Count) file(s) clean." -ForegroundColor Green
    } else {
        Write-Host "clang-tidy violations in $($tidyFailures.Count) file(s)." -ForegroundColor Red
        Write-Host "Fix the findings before committing. Add // NOLINT(check-name): reason only for confirmed false positives." -ForegroundColor Yellow
        $overallFailures += $tidyFailures
    }
}

# =========================================================
# Summary
# =========================================================
Write-Host ""
if ($overallFailures.Count -eq 0) {
    Write-Host "✅ Quality gate PASSED." -ForegroundColor Green
    exit 0
} else {
    $uniqueFailures = $overallFailures | Sort-Object -Unique
    Write-Host "❌ Quality gate FAILED — $($uniqueFailures.Count) file(s) have violations." -ForegroundColor Red
    exit 1
}
