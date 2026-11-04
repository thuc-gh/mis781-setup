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
# A process started with other credentials gets that user's own environment,
# not this one, so the values the student side needs travel in a file.
$config = Join-Path $env:RUNNER_TEMP 'student-env.json'
@{ Workspace = $env:GITHUB_WORKSPACE; TestPassword = $env:TEST_PASSWORD; SecondPassword = $env:SECOND_PASSWORD } |
    ConvertTo-Json | Set-Content $config -Encoding UTF8
$p = Start-Process powershell.exe -Credential $cred -LoadUserProfile -WorkingDirectory $env:RUNNER_TEMP `
     -ArgumentList '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', "`"$script`"", '-Step', $Step, '-Config', "`"$config`"" `
     -RedirectStandardOutput $log -RedirectStandardError $err -Wait -PassThru
Get-Content $log -ErrorAction SilentlyContinue
$e = Get-Content $err -ErrorAction SilentlyContinue
if ($e) { Write-Host '--- stderr ---'; $e }
if ($p.ExitCode -ne 0) { throw "student step '$Step' failed with exit code $($p.ExitCode)" }
