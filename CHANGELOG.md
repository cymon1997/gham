# Changelog

All notable changes to gham are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

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
