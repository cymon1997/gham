# Changelog

All notable changes to gham are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.2.1] — 2026-11-13

### Fixed
- `gham owner` failed with `${1,,}: bad substitution` under bash 3.2, the `/bin/bash` macOS ships,
  so no owner bind could be added, and resolving a remote's owner hit the same error. Lowercasing
  now goes through a `lower` helper that works on bash 3.2 and later, and forks `tr` only when the
  text has an uppercase letter, so the git shim stays fork-free in the usual case.
- CI runs the macOS smoke tests under `/bin/bash` 3.2 as well as Homebrew's bash 5, so a bash 4+
  construct can no longer pass CI and break on a stock Mac.

## [0.2.0] — 2026-11-10

### Added
- Owner binds: `gham owner <owner> <name> [--hostname H]`, `gham unowner`, `gham owners`. git picks
  the account from the repository's remote (origin, else the first remote) or from the URL being
  cloned, before directory binds. It reads `.git` dirs, linked worktrees, submodules and bare
  repos without forking. gh keeps following directory binds.
- `gham current` shows gh's account too when it differs from git's; `gham doctor` shows both and
  lists owner binds; `gham list` counts owners.

### Changed
- The shims dispatch before the command definitions and look up the real binaries without forking,
  which halves their overhead per call.
- `rename` and `remove` keep owner binds in step.

### Fixed
- Two accounts on the same host shared one gh token: gh keeps the active token in a single
  keyring entry per host, shared by every `GH_CONFIG_DIR`, so the last login won. `add` and `login`
  now pass `--insecure-storage`, so each token lives in the account's own `hosts.yml` (mode 600).
  `login` first drops a keyring copy, and `doctor` warns about accounts still using the keyring.
  `verify` names the cause when the token belongs to someone else and prints the `gham login` fix.

## [0.1.0] — 2026-11-10

### Added
- `gham add` (with `--import`, `--no-login`, `--ssh-key`, `--no-ssh`, `--hostname`, `--git-name`,
  `--git-email`), `login`, `list`, `use`, `default`, `current`, `run`, `env`, `bind`, `unbind`,
  `binds`, `set`, `rename`, `remove`, `verify`, `doctor`, `init`, `version`.
- `git` and `gh` shims that resolve an account per process (`gham run`), per shell (`gham use`),
  per directory (`gham bind`, longest match) or per machine (`gham default`).
- Per account: its own gh login (`GH_CONFIG_DIR`), git author, SSH key (`core.sshCommand`) and
  HTTPS credential helper, injected through `GIT_CONFIG_COUNT` so `~/.gitconfig` is never edited.
- `gham add` generates an ed25519 key per account and uploads it with `gh ssh-key add`.
- Shared gh settings: every account's `config.yml` links to `~/.config/gh/config.yml`.
- Tab completion in bash and zsh.
- `install.sh`, smoke tests against a fake `gh` and the real git, and CI with ShellCheck.
