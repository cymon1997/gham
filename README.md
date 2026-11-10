# gham — GitHub Account Manager

[![CI](https://github.com/cymon1997/gham/actions/workflows/ci.yml/badge.svg)](https://github.com/cymon1997/gham/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Use several GitHub accounts on one machine, and let the directory you're in pick the right one.
gham is the sibling of [cam](https://github.com/cymon1997/cam), which does the same for Claude Code.

```console
$ gham list
> personal       default  me@github.com                  me@example.com  [1 bind]
  work                    me-at-work@github.com          me@company.com  [1 bind]

$ gham bind ~/Code/company work
$ cd ~/Code/company/api && gham current
work  (bind /home/me/Code/company)  me-at-work@github.com  Me <me@company.com>

$ git commit -m "fix"      # authored as me@company.com
$ git push                 # pushed with work's SSH key
$ gh pr create             # opened by me-at-work
```

- **One account is a whole identity:** the `gh` login, the git author name and email, the SSH key
  used for push and pull, and the HTTPS credential. Switching an account switches all four.
- **Bind directories.** `gham bind ~/Code/company work` makes every repo under that directory
  use `work`. The deepest bind wins.
- **Or let the repository decide.** `gham owner acme work` makes git use `work` in any repo whose
  remote is `acme/*`, wherever it lives on disk. That covers a personal repo sitting inside a
  company tree, and bare repos or worktrees of company repos inside a personal one.
- **Override when you need to.** `gham run personal git push` does it once. `gham use personal`
  switches the shell. Both beat a bind.
- **Plain `git` and `gh` keep working.** Small shims pick the account, so scripts, aliases and
  tools that call `git` or `gh` from `PATH` follow along.
- **`~/.gitconfig` is never edited.** The account's settings are injected through git's own
  `GIT_CONFIG_COUNT` environment config, and `git config --global` still writes where it always did.
- **A single bash script** with no dependencies beyond `bash`, `git` 2.31+, `gh` and `ssh-keygen`.

## How it works

```
~/.gham/
├── bin/
│   ├── gham
│   ├── git -> gham            shim: picks an account, then runs the real git
│   └── gh  -> gham            shim: picks an account, then runs the real gh
├── default                    name of the default account
├── binds                      <directory> TAB <account>, one per line
├── owners                     <host>/<owner> TAB <account>, one per line
└── accounts/
    └── work/
        ├── account.conf       login, host, git name/email, SSH key path
        ├── gh/                GH_CONFIG_DIR for "work"
        │   ├── hosts.yml      ← this account's gh login (private)
        │   └── config.yml -> ~/.config/gh/config.yml   (shared aliases and settings)
        └── ssh/id_ed25519     ← the key gham generated and uploaded (private)
```

A shim resolves the account in this order:

1. `GHAM_ACCOUNT_ACTIVE`, set by `gham run` and passed on to every child process. A git hook or
   a `gh` that calls `git` keeps the account its parent started with.
2. `GHAM_ACCOUNT`, set for the current shell by `gham use`.
3. **git only:** a `gham owner` matching the repository's remote: `origin`, or else the first
   remote. For `git clone`, the URL being cloned counts. gham finds the repository by walking up
   from the working directory and reading its config file, whether that is a normal `.git`, a
   linked worktree, a submodule or a bare repo. It does this without starting another process.
4. The longest `gham bind` directory that contains the working directory. For git, `-C`,
   `--git-dir` and `--work-tree` count as the working directory.
5. The default account, set with `gham default`.

gh doesn't use step 3, so `gh` follows directory binds. In one directory, git and gh can
therefore resolve to different accounts. `gham current` shows both when they differ.

It then exports `GH_CONFIG_DIR` and these git settings, and `exec`s the real binary:

| Setting | Value |
|---|---|
| `user.name`, `user.email` | the account's author |
| `core.sshCommand` | `ssh -i <account key> -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new` |
| `credential.https://<host>.helper` | reset, then the real `gh auth git-credential` under the account's `GH_CONFIG_DIR` |

If nothing resolves, `git` and `gh` pass straight through, as if gham were not installed.

## Installation

```bash
git clone https://github.com/cymon1997/gham.git
cd gham
./install.sh
```

or `curl -fsSL https://raw.githubusercontent.com/cymon1997/gham/main/install.sh | bash`.
Both methods install to `~/.gham/bin`. Set `GHAM_HOME` to install somewhere else.

Add this line to `~/.zshrc` or `~/.bashrc`, then open a new shell:

```bash
eval "$(~/.gham/bin/gham init)"
```

It puts `~/.gham/bin` first on `PATH`, defines a `gham` shell function so that `gham use` can
change the current shell, and turns on tab completion. Check the setup with `gham doctor`.

## Tutorial

### 1. Keep the identity you already have

```console
$ gham add personal --import
Imported the current identity into 'personal' (gh: me): Me <me@example.com>.
No SSH key set, so git uses your normal ~/.ssh setup. Pin one with: gham set personal ssh-key <path>
'personal' is now the default.
```

`--import` copies the current `gh` login from `~/.config/gh/hosts.yml` and the global git
`user.name` and `user.email`. If the account has its own key, pin it with
`--ssh-key ~/.ssh/id_ed25519` or with `gham set`.

### 2. Add a second account

```console
$ gham add work
Starting GitHub login for 'work' on github.com …
```

The normal `gh auth login` flow opens. Sign in as the other account. gham then:

- reads the login, name and public email from the API. With no public email it uses the
  `<id>+<login>@users.noreply.github.com` address, which GitHub attributes to the account.
  Override it with `--git-email` or `gham set work email …`;
- generates `~/.gham/accounts/work/ssh/id_ed25519` and uploads it with `gh ssh-key add`. That is
  why the login asks for the `admin:public_key` scope. Use `--ssh-key PATH` to reuse an existing
  key, or `--no-ssh` to leave SSH alone.

Check that GitHub agrees:

```console
$ gham verify work
gh token   ok — me-at-work
ssh key    ok — me-at-work
git author Me <me@company.com>
```

### 3. Bind directories

```bash
gham bind ~/Code/company work
gham bind ~/Code/company/oss-fork personal   # the deeper bind wins inside it
gham binds
```

`git clone`, `commit`, `push` and `gh pr create` under `~/Code/company` now run as `work`.
Everywhere else they run as the default.

### 4. Let the remote decide

Directory binds assume one directory means one account. That breaks when a personal repo holds
company repos, for example a workspace with bare clones under `.repos/` and worktrees under
`services/`:

```bash
gham bind  ~/Code/company work      # gh, and git where no repo or owner applies (e.g. a clone target)
gham owner me personal              # git in any repo whose remote is me/*
gham owner company work             # git in any repo whose remote is company/*
```

```console
$ cd ~/Code/company/my-workspace && gham current
personal  (owner github.com/me)  me@github.com  Me <me@example.com>
  gham bind ~/Code/company → gh here: work  (bind /home/me/Code/company)  me-at-work@github.com
$ git -C .repos/api.git fetch        # work: the bare repo's remote is company/api
$ git commit && git push             # personal: the workspace's remote is me/my-workspace
$ gh pr list -R company/api          # work: gh follows the directory bind
```

`gham owner ghe.example.com/team work` binds an owner on a GitHub Enterprise host. Matching
ignores case, and handles `git@host:owner/repo`, `ssh://git@host:port/owner/repo` and
`https://host/owner/repo`.

### 5. Override a bind

```bash
gham run personal git push         # once
gham run personal                  # a subshell pinned to personal
gham use personal                  # this shell, until: gham use --default
```

### 6. Scripts and CI-like jobs

```bash
eval "$(gham env work)"
git push && gh release create v1.0.0
```

## Command reference

| Command | What it does |
|---|---|
| `gham add <name>` | Register an account: `gh` login, git author from the API, new SSH key uploaded to GitHub. The first account becomes the default. |
| `gham add <name> --import` | Take the current `gh` login and global git identity instead of logging in. |
| `gham add … --ssh-key PATH` / `--no-ssh` | Use an existing key, or don't manage SSH. |
| `gham add … --git-name N --git-email E` | Set the commit author instead of reading it from the API. |
| `gham add … --hostname H` | A GitHub Enterprise host instead of github.com. |
| `gham add … --no-login` | Register without logging in. |
| `gham add … -- <args>` | Pass extra arguments to `gh auth login`, such as `--with-token`. |
| `gham login <name>` | Log the account's `gh` in again. |
| `gham list [--names]` | List accounts. `>` marks the one git and gh use here. |
| `gham use <name>` / `--default` | Switch this shell, or clear the switch. |
| `gham bind <dir> <name>` | Use `<name>` anywhere under `<dir>`. |
| `gham unbind <dir>`, `gham binds` | Remove a bind, list binds. |
| `gham owner <owner> <name> [--hostname H]` | Use `<name>` for git in any repository whose remote is `<owner>/*`. |
| `gham unowner <owner>`, `gham owners` | Remove an owner bind, list owner binds. |
| `gham default [name]` | Show or set the machine-wide default. |
| `gham current [dir]` | Which account git uses here, and why, plus gh's account when it differs. |
| `gham run <name> [cmd…]` | Run a command, or a shell, as `<name>`. Wins over owners, binds and `use`. |
| `gham env [name]` | Print the exports for scripts. |
| `gham set <name> [key value]` | Show or change `name`, `email`, `ssh-key` (`none` clears it), `host`, `login`. |
| `gham rename <old> <new>` | Rename an account. Its binds, owners, default and key path follow. |
| `gham remove <name> [-y]` | Delete the local login, key, binds and owners. |
| `gham verify [name]` | Ask GitHub who the token and the SSH key belong to. Needs the network. |
| `gham doctor` | Paths, real binaries, shims, warnings, accounts and binds. |
| `gham init [zsh\|bash]` | Shell integration and tab completion. |

### Environment variables

| Variable | Meaning |
|---|---|
| `GHAM_HOME` | Where gham keeps its binary and accounts. Default `~/.gham`. |
| `GHAM_ACCOUNT` | Account for this shell. Set by `gham use`. |
| `GHAM_ACCOUNT_ACTIVE` | Account pinned for this process tree. Set by `gham run` and `gham env`. |
| `GHAM_GIT_BIN`, `GHAM_GH_BIN` | Paths to the real binaries, if the `PATH` search picks the wrong one. |
| `GHAM_GH_SHARED_DIR` | Shared gh settings directory. Default `~/.config/gh`. |

## Things to know

- **The account wins over a repo's own `user.email`.** Command-line-level config outranks
  `.git/config`. To give one repo a different identity, bind its directory or its owner to
  another account.
- **Tools that bypass `PATH` bypass gham.** An IDE configured with `/usr/bin/git` or a GUI client
  with its own git won't see the account. Point the IDE at `~/.gham/bin/git`, or launch it from a
  `gham run` shell.
- **gh tokens live in each account's `gh/hosts.yml`, not the system keyring.** gh keeps the
  active account's token in one keyring entry per host, and every config directory shares it, so
  the last login would silently become every account's token. gham logs in with
  `--insecure-storage`, so the token is a plain-text file readable only by you, as with cam's stored
  login. `gham doctor` flags an account whose token is still in the keyring, and `gham login <name>`
  moves it.
- **`GH_TOKEN`, `GITHUB_TOKEN` and `GIT_SSH_COMMAND` beat gham.** `gham doctor` warns about them.
- **Removing an account doesn't revoke anything on GitHub.** Delete the uploaded key at
  `github.com/settings/keys` and revoke the token at `github.com/settings/applications`.
- **The generated SSH key has no passphrase,** like cam's stored login. Add one with
  `ssh-keygen -p -f ~/.gham/accounts/<name>/ssh/id_ed25519`, and load it into `ssh-agent`.
- **Owner matching reads the raw remote URL.** An SSH host alias such as `git@github-work:…` is
  not `github.com`, and `url.<base>.insteadOf` rewrites are not applied before matching. Both
  still match if you bind the owner under the alias, e.g. `gham owner github-work/company work`.
- **Each `git` call goes through a bash shim,** which adds a few milliseconds. Prompt themes that
  run git on every prompt will notice it, but not much.

## Contributing

```bash
./tests/smoke.sh                        # fake gh, real git: no network, no login
shellcheck gham install.sh tests/*.sh   # must be clean
```

Please keep gham a single, dependency-free bash script.

## License

[MIT](LICENSE) © cymon1997. gham is a community tool, not affiliated with or endorsed by GitHub.
