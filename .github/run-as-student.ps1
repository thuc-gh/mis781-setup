# Actions test helper (Windows): the administrator side. Runs one step of
# windows-student.ps1 as the standard local user the workflow created, shows
# its output and fails the job if the step failed. Never run by students.

param([Parameter(Mandatory)][string]$Step)

$ErrorActionPreference = 'Stop'
$user = 'mis781student'
$cred = New-Object Management.Automation.PSCredential("$env:COMPUTERNAME\$user", (ConvertTo-SecureString $env:STUDENT_PASSWORD -AsPlainText -Force))
$log = Join-Path $env:RUNNER_TEMP "student-$Step.log"
$err = Join-Path $env:RUNNER_TEMP "student-$Step.err"
$script = Join-Path $env:GITHUB_WORKSPACE '.github\windows-student.ps1'
$p = Start-Process powershell.exe -Credential $cred -LoadUserProfile -WorkingDirectory $env:RUNNER_TEMP `
     -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-Step', $Step `
     -RedirectStandardOutput $log -RedirectStandardError $err -Wait -PassThru
Get-Content $log -ErrorAction SilentlyContinue
$e = Get-Content $err -ErrorAction SilentlyContinue
if ($e) { Write-Host '--- stderr ---'; $e }
if ($p.ExitCode -ne 0) { throw "student step '$Step' failed with exit code $($p.ExitCode)" }
