# adopt-template-updates — Comparison Scripts

PowerShell scripts for comparing Generic template files with particle-sim local files.

## Hash Comparison (fast check)

```powershell
param(
    [string]$TemplatePath = "C:\projects\zoom_copilot_config\Generic",
    [string]$ProjectPath  = "."
)

$files = @(
    ".github/copilot-instructions.md",
    ".github/planning/PLANS.md",
    ".github/planning/execplans/_TEMPLATE.md",
    ".clang-format",
    ".clang-tidy",
    "AGENTS.md"
)

foreach ($f in $files) {
    $t = Join-Path $TemplatePath $f
    $p = Join-Path $ProjectPath $f
    if ((Test-Path $t) -and (Test-Path $p)) {
        $h1 = (Get-FileHash $t -Algorithm SHA256).Hash
        $h2 = (Get-FileHash $p -Algorithm SHA256).Hash
        $same = if ($h1 -eq $h2) { "SAME" } else { "DIFF" }
        Write-Host "$same  $f"
    } elseif (Test-Path $t) {
        Write-Host "NEW   $f  (exists in template, not in project)"
    } else {
        Write-Host "LOCAL $f  (exists in project, not in template)"
    }
}
```

## Content Diff (detailed delta)

```powershell
param(
    [string]$File,
    [string]$TemplatePath = "C:\projects\zoom_copilot_config\Generic",
    [string]$ProjectPath  = "."
)

$t = Get-Content (Join-Path $TemplatePath $File)
$p = Get-Content (Join-Path $ProjectPath $File)
Compare-Object $t $p | ForEach-Object {
    $indicator = if ($_.SideIndicator -eq "<=") { "TEMPLATE" } else { "PROJECT " }
    Write-Host "$indicator  $($_.InputObject)"
}
```

**Interpretation:**
- `TEMPLATE` — line exists only in template (potential adoption)
- `PROJECT` — line exists only in project (local customization)
