# Changelog

All notable changes to gham are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-11-21

### Added
- Providers: `gham add --provider github|gitlab|git`, stored as `provider=` in `account.conf`.
  - `gitlab` logs in with `glab auth login --insecure-storage` (when the glab supports the flag)
    into the account's own `GLAB_CONFIG_DIR`, so tokens stay per account instead of in glab's
    shared keyring entry. It reads the
    username, name and commit email from the API, uploads the generated key with
    `glab ssh-key add`, and serves HTTPS tokens through `glab auth git-credential`.
  - `git` works with any host and needs no CLI: git identity and SSH key only. gham prints the
    public key, copies it to the clipboard when it can, and names the host's key page. HTTPS
    keeps the user's own credential helper; `--user` sets `credential.<host>.username`.
- A `glab` shim. `gh` and `glab` only take over for an account of their own provider and run
  untouched otherwise.
- `gham verify` per provider; the SSH check understands GitHub, GitLab, Gitea/Forgejo and
  Bitbucket greetings. `gham doctor` shows glab, warns about `GITLAB_TOKEN`,
  `GITLAB_ACCESS_TOKEN` and `OAUTH_TOKEN`, and about glab tokens left in the keyring.
- `gham set <name> provider <p>`; `--user` on `add`; completion for providers.

### Changed
- gh is no longer required: only `github` accounts need it, only `gitlab` accounts need glab.
  A missing CLI fails `add` before anything is created, and its shim exits 127.
- `gham owner <owner> <name>` without `--hostname` binds the owner on the account's own host.
  `gham unowner <owner>` finds a bare owner on its host when only one host has it.
- `gham current` labels the second line `gh/glab here`.

### Fixed
- An account on a non-GitHub host lost HTTPS access: gham cleared the user's credential helper for
  that host and put `gh auth git-credential` in its place, though gh held no token for it.

### Docs
- README: `gham init` belongs after `brew shellenv` in the rc file, so the shims stay first on
  `PATH`.

### Compatibility
- Accounts without a `provider` line are `github` and behave exactly as in 0.2. An older gham
  ignores the new line.

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
