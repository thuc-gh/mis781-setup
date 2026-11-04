# MIS781 setup

Scripts that put MySQL Server, MySQL Workbench and the Employees sample database on a student's own macOS or Windows computer, and take them off again. Students run one line and should never have to diagnose their own machine.

## Language

**Setup script**:
The single one-liner per platform a student runs. It scans, recommends one action, and runs the action chosen.
_Avoid_: installer (that is one action the setup script can run), launcher, menu script

**Scan**:
A read-only inventory of what MySQL-related software is on the computer. It never asks for a password and never changes anything.
_Avoid_: detect, check, probe

**Recommendation**:
The one action the scan result points to, shown as the default choice in the menu.
_Avoid_: suggestion, default action

**Action**:
One thing the setup script can do after the scan: install, load data, reset password, remove server, remove everything.
_Avoid_: option, mode, command, step

**Our server**:
A MySQL Server put on the computer by this unit's scripts: the home-folder install on macOS, or the MySQL Windows service installed from our MSI.
_Avoid_: MIS781 server, local server, the unit's MySQL

**Other server**:
Any MySQL Server not installed by this unit: Homebrew, the Oracle package installer on macOS, MAMP, XAMPP, WAMP, Docker. The macOS installer uses it when it is there; the Windows installer cannot and asks for it to be stopped first. Neither removes it unless the student picks a removal action that lists it.
_Avoid_: existing server, foreign server, third-party MySQL

**Install**:
The action that puts in place whatever is missing from the full set: server, Workbench, Employees files and Employees data. Re-running it on a complete computer changes nothing.
_Avoid_: full install, repair, finish install (all are this one action)

**Employees files**:
The unpacked `test_db` download sitting in the student's MIS781 folder. Having the files does not mean the data is loaded.
_Avoid_: the data, the database, the zip

**Employees data**:
The `employees` database as loaded into a running MySQL Server, complete when it holds 300,024 employees.
_Avoid_: the data, the sample database, the schema

**Load data**:
The action that runs the Employees files into the server to produce the Employees data.
_Avoid_: import (the worker scripts are still named import; the action a student sees is "load")

**Reset password**:
The action that gives the root account a new password while keeping every database on the server. The first thing offered for a forgotten password.
_Avoid_: recover password (nothing is recovered), reinstall

**Remove server**:
The action that takes MySQL Server and all its databases off the computer and leaves Workbench and the Employees files in place, so a fresh install is quick.
_Avoid_: uninstall (ambiguous between the two removal actions), clean, reinstall

**Remove everything**:
The action that takes off the server, Workbench, its saved connections, the Employees files and the downloaded installers.
_Avoid_: full uninstall, purge, wipe

**Destructive action**:
An action that deletes files or databases, or changes something the student cannot get back without a password they may not know: remove server, remove everything, load data over an existing Employees data, reset password.
_Avoid_: dangerous action, irreversible action

**Confirmation**:
The step shown immediately before a destructive action runs: the concrete list of what will change, then the student's explicit agreement. Removals need the word `yes` typed; a reload or a reset needs `y`. Anything else means nothing changes.
_Avoid_: prompt, warning, are-you-sure

**Unattended**:
Running the setup script with the action and the root password supplied by environment variables, so no prompt appears. Used by the Actions test and lab imaging.
_Avoid_: silent, headless, CI mode
