# WWMD Quickstart

This guide gets a local development checkout to a verified database-health
check and the native app. V0 runs entirely in that app process; it does not
configure collection sources, XPC, a socket, or a background service.

## Prerequisites

You need all of the following:

1. A Mac running macOS 13 (Ventura) or later.
2. Apple's Swift 6 toolchain. Install the Command Line Tools if necessary:

   ~~~sh
   xcode-select --install
   ~~~

3. Git, to obtain the repository.
4. A local user account that can create files in its own Application Support
   directory.

Verify the installed tools before continuing:

~~~sh
sw_vers -productVersion
xcode-select -p
swift --version
git --version
~~~

`swift --version` must report Swift 6 or newer. WWMD has no Homebrew,
Docker, Python, cloud-account, or third-party database prerequisite; it links
the SQLite library provided by macOS.

## Get the source

Clone the public repository, then enter it:

~~~sh
git clone https://github.com/iamh2o/wwmd.git
cd wwmd
~~~

If you already have a checkout, enter that checkout instead. Do not use
`sudo`; WWMD's development commands run as the signed-in macOS user.

## Build and verify the foundation

Run the complete unit-test suite, then check the CLI version:

~~~sh
swift test
swift run wwmd --version
~~~

The initial `swift` invocation may download nothing but still takes longer
while SwiftPM builds the package. Later invocations reuse `.build/`.

## Create and inspect a local WWMD database (optional)

Choose a database **file** path. The value after `--database` must end in a
filename such as `wwmd.sqlite`; it must not be only a directory path.

~~~sh
mkdir -p "$HOME/Library/Application Support/WWMD"
wwmd_db="$HOME/Library/Application Support/WWMD/wwmd.sqlite"
swift run wwmdd --database "$wwmd_db" --health
~~~

Expected output has this shape:

~~~text
wwmdd database health: schema=<number> events=0 quick_check=ok
~~~

WWMD creates the parent directory if needed, but creating it explicitly
makes the location clear. The database is local to this Mac and starts with no
collected events.

The command below is incomplete because it supplies neither the required mode
nor a database filename:

~~~sh
swift run wwmdd --database "$PWD/db/"
~~~

Use the exact `--health` command above instead. If you prefer a project-local
database, choose a new file path that does not collide with an existing file,
for example:

~~~sh
swift run wwmdd --database "$PWD/.local/wwmd.sqlite" --health
~~~

## Start the development app

Run the native development UI from the checkout:

~~~sh
swift run WWMDApp
~~~

This starts the menu-bar/viewer app. Click the WWMD menu-bar item, then click
**Open WWMD** to show its main window. In **Local database**, enter the exact
absolute file path you chose above (for example,
`$HOME/Library/Application Support/WWMD/wwmd.sqlite`) and click **Open selected
database**. The app acquires the exclusive local runtime lease, creates and
migrates the database if necessary, and shows its health.

With the database open, choose an explicit **From** and **To** date range, then
click **Load dashboard**. The app does not auto-query a date range, expose
event payloads, or turn on a collection source. It runs no second process: the
app is the only WWMD runtime for the selected database until you close it or
quit WWMD.

Do not run `wwmdd --health` against the same path while WWMD is open. The
diagnostic and the app deliberately use the same exclusive lease. Close the
database in the app first if you need to run a closed-app health check.

## Deferred native XPC path

Native XPC source and CLI support remain in the repository for a future signed
packaged release. It is not part of V0 setup and there is no Mach service name,
code-signing requirement, launchd job, or XPC value to obtain or enter today.

## Current collection prerequisites

WWMD does not scan the filesystem or infer data sources. Each implemented
source requires an explicit opt-in and its own proven contract:

- Codex CSV import remains unavailable until an actual CSV schema is supplied.
- Git metadata requires a user-selected repository root; source contents and
  filenames are not collected.
- Build/test metadata requires an explicit user-approved invocation; command
  arguments and output are not persisted.
- Activity collection requires a user-approved safe source; window titles and
  idle inference are excluded.

See the [implementation ledger](plans/20260724T085520Z_wwmd_v0_multiagent_ledger.md)
for the release gates and outstanding work.

## Troubleshooting

| Symptom | Resolution |
|---|---|
| `wwmdd` prints its usage text | Supply the current one-shot local mode: `--database /absolute/path/wwmd.sqlite --health`. |
| `swift --version` reports a version below 6 | Install or select a Swift 6 Xcode/Command Line Tools toolchain, then rerun the checks. |
| A path such as `$PWD/db/` fails | Pass a file path such as `$PWD/.local/wwmd.sqlite`; do not point the database option at a directory. |
| `database already in use` | WWMD or another supported diagnostic already owns that exact database. Close it before retrying; do not force a second runtime. |
| A previous database path already exists | Select a different new filename, or inspect the existing local data before deciding whether it may be removed. |
