#requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Unit-test the persist-report script body extracted from the orchestration, invoked exactly
# as Orchestra's script executor would: stdin piped in, environment variables set, strictMode
# prologue prepended.
#
# The report is handed over on stdin. Orchestra pins UTF-8 on both sides of that pipe, so this
# suite deliberately pushes em-dashes, curly quotes and CJK through it -- the characters the
# Windows OEM code page destroys.

Import-Module powershell-yaml
$yamlPath = 'P:\Github\Neovim-Moaid\config\Orchestra\workspace\orchestrations\Personal\Connect\connect-evidence-pack.yaml'
$doc = ConvertFrom-Yaml (Get-Content -LiteralPath $yamlPath -Raw)
$persist = @($doc.steps) | Where-Object { $_['name'] -eq 'persist-report' }
if (-not $persist) { throw 'persist-report step not found' }
$body = $persist['script']
if (-not $body) { throw 'persist-report has no inline script' }
if (-not $persist.Contains('stdin')) { throw 'persist-report should receive the report on stdin' }
if ($body -match '\$input') {
    throw 'persist-report must read stdin via [Console]::In.ReadToEnd(); $input is not encoding-safe'
}

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) "connect-persist-$([guid]::NewGuid().ToString('N').Substring(0,8))"
New-Item -ItemType Directory -Path $sandbox -Force | Out-Null
$scriptFile = Join-Path $sandbox 'persist.ps1'

# Mirror the engine's injected preamble: UTF-8 out, UTF-8 in, then the strict-mode prologue.
$prologue =
    "try { [Console]::OutputEncoding = `$OutputEncoding = [System.Text.UTF8Encoding]::new(`$false) } catch { }; " +
    "try { [Console]::InputEncoding = [System.Text.UTF8Encoding]::new(`$false) } catch { }; " +
    "`$ErrorActionPreference='Stop'; trap { Write-Error -ErrorRecord `$_; exit 1 }; Set-StrictMode -Version Latest`n"
[System.IO.File]::WriteAllText($scriptFile, $prologue + $body, (New-Object System.Text.UTF8Encoding($false)))

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$pass = 0; $fail = 0
function Check([string]$label, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Output "PASS  $label"; $script:pass++ }
    else     { Write-Output "FAIL  $label $detail"; $script:fail++ }
}

# Runs the script the way the engine does: stdin redirected with UTF-8 encoding on both ends.
function Invoke-Persist([string]$Markdown, [string]$OutDir, [string]$Start, [string]$End) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'pwsh'
    foreach ($a in @('-NoProfile', '-File', $scriptFile)) { $psi.ArgumentList.Add($a) }
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = $utf8NoBom
    $psi.StandardErrorEncoding  = $utf8NoBom
    $psi.StandardInputEncoding  = $utf8NoBom
    $psi.Environment['CONNECT_OUTPUT_DIR'] = $OutDir
    $psi.Environment['CONNECT_START']      = $Start
    $psi.Environment['CONNECT_END']        = $End

    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($Markdown)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd().Trim()
    $err = $p.StandardError.ReadToEnd().Trim()
    $p.WaitForExit()
    return @{ Out = $out; Err = $err; Exit = $p.ExitCode }
}

# The exact characters the OEM code page destroys.
$emDash = [char]0x2014; $lq = [char]0x201C; $rq = [char]0x201D
$eAcute = [char]0x00E9; $cjk = [char]0x4E2D
$md = "# Evidence ${emDash} pack`n`n${lq}Quoted${rq} caf${eAcute} ${cjk}`n"

# ------------------------------------------ case 1: explicit output directory
$outDir = Join-Path $sandbox 'explicit'
$r = Invoke-Persist $md $outDir '2025-11-18' '2026-05-13'
Check 'case 1: exits 0' ($r.Exit -eq 0) "(exit=$($r.Exit) err=$($r.Err))"
$target = Join-Path $outDir 'connect-evidence-pack_2025-11-18_2026-05-13.md'
Check 'case 1: writes the expected filename' (Test-Path -LiteralPath $target)

if (Test-Path -LiteralPath $target) {
    $text = [System.IO.File]::ReadAllText($target)
    $bytes = [System.IO.File]::ReadAllBytes($target)

    Check 'case 1: em-dash U+2014 survives the stdin pipe' ($text.Contains($emDash))
    Check 'case 1: curly quotes survive the stdin pipe' ($text.Contains($lq) -and $text.Contains($rq))
    Check 'case 1: e-acute survives' ($text.Contains($eAcute))
    Check 'case 1: CJK outside CP1252 survives' ($text.Contains($cjk))
    Check 'case 1: content matches exactly' ($text -eq ($md -replace "`r`n", "`n")) "(len got=$($text.Length) want=$($md.Length))"
    Check 'case 1: no BOM' (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF))
    Check 'case 1: no CR (^M)' (-not $text.Contains("`r"))
    Check 'case 1: stdout is JSON with path+bytes' $(
        try { $j = $r.Out | ConvertFrom-Json; [bool]($j.path -and $j.bytes -gt 0) } catch { $false }
    ) "(stdout=$($r.Out))"
}

# ---------------------------------- case 2: empty dir -> USERPROFILE fallback
$fakeHome = Join-Path $sandbox 'fakehome'
New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null
$orig = $env:USERPROFILE
$env:USERPROFILE = $fakeHome
try { $r2 = Invoke-Persist "# fallback" '' '2026-06-01' '2026-11-30' } finally { $env:USERPROFILE = $orig }
$fallback = Join-Path $fakeHome 'OneDrive - Microsoft/Connect/2026-06-01_2026-11-30/connect-evidence-pack_2026-06-01_2026-11-30.md'
Check 'case 2: exits 0 with empty outputDirectory' ($r2.Exit -eq 0) "(exit=$($r2.Exit) err=$($r2.Err))"
Check 'case 2: falls back to USERPROFILE OneDrive path' (Test-Path -LiteralPath $fallback)

# ------------------------- case 3: render produced nothing -> clear failure
$r3 = Invoke-Persist '' (Join-Path $sandbox 'none') '2026-01-01' '2026-02-01'
Check 'case 3: empty render output fails the step' ($r3.Exit -ne 0) "(exit=$($r3.Exit))"
Check 'case 3: failure message is actionable' ($r3.Err -match 'no content to persist') "(err=$($r3.Err))"

# ----------------------------------------- case 4: nested directory creation
$deep = Join-Path $sandbox 'a/b/c/deep'
$r4 = Invoke-Persist "# deep" $deep '2026-03-01' '2026-03-31'
Check 'case 4: creates nested output directory' (Test-Path -LiteralPath (Join-Path $deep 'connect-evidence-pack_2026-03-01_2026-03-31.md')) "(exit=$($r4.Exit))"

# ------------------------------------------------ case 5: rerun overwrites
$r5 = Invoke-Persist $md $outDir '2025-11-18' '2026-05-13'
Check 'case 5: re-running overwrites cleanly' ($r5.Exit -eq 0) "(exit=$($r5.Exit))"

# ------------------------------- case 6: a JSON-bearing report stays parseable
$jsonReport = "# Report`n`n``````json`n{`"note`":`"He said ${lq}hi${rq}`"}`n``````'`n"
$r6 = Invoke-Persist $jsonReport (Join-Path $sandbox 'jsonrep') '2026-04-01' '2026-04-30'
$jsonTarget = Join-Path $sandbox 'jsonrep/connect-evidence-pack_2026-04-01_2026-04-30.md'
Check 'case 6: curly quotes inside a fenced JSON block survive' $(
    (Test-Path -LiteralPath $jsonTarget) -and ([System.IO.File]::ReadAllText($jsonTarget).Contains($lq))
) "(exit=$($r6.Exit))"

Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
Write-Output ''
Write-Output "RESULT: $pass passed, $fail failed"
if ($fail) { exit 1 }
