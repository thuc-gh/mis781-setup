---
status: accepted
date: 2026-11-04
---

# A forgotten root password is handled by a reset, not a reinstall

Students forget the MySQL root password every trimester, and the first README told them the only fix was to remove MySQL and install it again, which also destroyed any coursework databases they had built. We decided instead that the setup script offers a **Reset password** action that stops our server, starts it once with an init file that sets a new root password, restarts it and proves the new password works, keeping every database. Remove server and reinstall stays as the fallback when the reset fails or the server will not start at all.

## Considered options

- **Reinstall only** (the original choice): simplest to document, but destroys coursework for a problem that does not need it, and students who have already loaded the Employees data pay another ten minutes.
- **Reset for any server found**: Homebrew, Oracle pkg, MAMP and Docker servers each start and stop differently and are not ours to manage; a wrong restart could leave a student's other project broken. Reset is therefore offered for our server only, and the README links to Oracle's reset instructions for the rest.

## Consequences

- The README line "there is no recovery" is wrong and must go.
- Reset is never the scan's recommendation, since the scan cannot know a password was forgotten; it is a standing menu item whenever our server is present.
- On Windows a reset of the legacy server (the MSI-installed service, see ADR 0002) needs one elevation prompt (stop and start the service); the setup script relaunches itself elevated rather than asking the student to open Terminal (Admin). Our server on Windows, which runs as the student, resets without elevation.
