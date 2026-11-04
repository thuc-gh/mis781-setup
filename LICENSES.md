# Licences and source availability

This repository mirrors unmodified vendor software and an unmodified public dataset for use in Deakin University's MIS781 unit. Nothing here is authored by the maintainer except the scripts and the documentation.

Files are mirrored rather than linked because vendor download URLs move when a version is superseded, which breaks setup instructions mid-trimester.

## MySQL Community Server 26.10.0 and MySQL Workbench 26.10.0 — unmodified

- **Files:** `mysql-26.10.0-macos15-arm64.tar.gz`, `mysql-26.10.0-winx64.msi`, `mysql-workbench-26.10.0-macos-arm64.zip`, `mysql-workbench-26.10.0-winx64.msi`, exactly as downloaded from dev.mysql.com (SHA-256 sums are in the release notes).
- **Licence:** GNU General Public License, version 2, as published by Oracle Corporation (Community edition). Licensing documents are included inside each distribution.
- **Copyright:** Oracle Corporation and/or its affiliates.
- **Trademarks:** MySQL is a trademark of Oracle Corporation. This mirror is not affiliated with, endorsed by, or sponsored by Oracle.
- **Corresponding source:** published by Oracle at
  - Server: https://dev.mysql.com/downloads/mysql/ (Source Code)
  - Workbench: https://dev.mysql.com/downloads/workbench/ (Source Code) and https://github.com/mysql/mysql-workbench
  - Archived versions: https://downloads.mysql.com/archives/

### Written offer of source

In accordance with GPLv2 section 3(b): for at least three years from the date of distribution, the maintainer of this repository will provide, to any third party who received these binaries from this repository, a complete machine-readable copy of the corresponding source code for the GPL-licensed works distributed here, on a medium customarily used for software interchange, for a charge no more than the cost of physically performing the distribution. Requests may be made by opening an issue on this repository.

The identical source is also available directly from Oracle at the links above.

## Employees sample database (`test_db-master.zip`) — unmodified

- **Source:** https://github.com/datacharmer/test_db, commit `e324b56` (10 April 2026), downloaded as the repository zip and redistributed as is.
- **Licence:** Creative Commons Attribution-Share Alike 3.0 Unported (CC BY-SA 3.0), https://creativecommons.org/licenses/by-sa/3.0/
- **Attribution:** data created by Fusheng Wang and Carlo Zaniolo at Siemens Corporate Research; relational schema by Giuseppe Maxia; MySQL data export by Patrick Crews. The data is fabricated and does not correspond to real people.

## Microsoft Visual C++ Redistributable — not mirrored

`install.ps1` downloads this directly from Microsoft (https://aka.ms/vs/17/release/vc_redist.x64.exe) when MySQL Server needs it. Microsoft's own licence terms apply.

## Contact

To request source, raise a licensing concern, or ask for removal of any file, open an issue on this repository.
