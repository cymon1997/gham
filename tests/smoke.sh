#!/usr/bin/env bash
# Smoke tests for gham. Uses a fake `gh` and `glab` and the real git, so no network or
# login is needed. Run from the repository root:  ./tests/smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Physical path: on macOS mktemp returns /var/…, a symlink to /private/var/….
SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export GHAM_HOME="$HOME/.gham"
export SHELL=/bin/bash
export XDG_CONFIG_HOME="$HOME/.config"
unset GHAM_ACCOUNT GHAM_ACCOUNT_ACTIVE GHAM_ENV_APPLIED GHAM_SHELL_INIT GH_CONFIG_DIR GH_TOKEN GITHUB_TOKEN \
  GLAB_CONFIG_DIR GITLAB_TOKEN GITLAB_ACCESS_TOKEN OAUTH_TOKEN GITLAB_HOST DISPLAY WAYLAND_DISPLAY \
  GIT_SSH_COMMAND GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL GIT_AUTHOR_NAME GIT_COMMITTER_NAME
mkdir -p "$HOME/.config/gh" "$SANDBOX/fakebin" "$SANDBOX/work/repo" "$SANDBOX/oss"

# A fake gh: "logs in" by writing hosts.yml for $FAKE_LOGIN, answers `api user`,
# records uploaded keys, and acts as a git credential helper that names the
# config dir it was given.
cat > "$SANDBOX/fakebin/gh" <<'EOF'
#!/usr/bin/env bash
login="${FAKE_LOGIN:-octo}"
case "${1:-} ${2:-}" in
  "auth login")
    printf 'github.com:\n    users:\n        %s:\n    git_protocol: https\n    user: %s\n' "$login" "$login" > "$GH_CONFIG_DIR/hosts.yml"
    echo "$*" > "$GH_CONFIG_DIR/login-args"; exit 0 ;;
  "auth logout") exit 0 ;;
  "auth git-credential")
    cat >/dev/null; printf 'protocol=https\nhost=github.com\nusername=x\npassword=token-for-%s\n' "$GH_CONFIG_DIR"; exit 0 ;;
  "ssh-key add") cp "$3" "$GH_CONFIG_DIR/uploaded.pub"; exit 0 ;;
  "config set") echo "$*" >> "$GH_CONFIG_DIR/config-set"; exit 0 ;;
esac
if [[ "${1:-}" == api ]]; then
  user="$(awk '$1 == "user:" {print $2; exit}' "$GH_CONFIG_DIR/hosts.yml" 2>/dev/null)"
  [[ -n "$user" ]] || exit 1
  if [[ "$*" == *"--jq .login"* ]]; then echo "$user"; else printf '%s\t42\t%s\t\n' "$user" "Name of $user"; fi
  exit 0
fi
[[ "${1:-}" == "--version" ]] && { echo "gh version 0.0.0 (fake)"; exit 0; }
echo "gh config=$GH_CONFIG_DIR account=${GHAM_ACCOUNT_ACTIVE:-} args=$*"
EOF
chmod +x "$SANDBOX/fakebin/gh"

# A fake glab, the same idea: config.yml in GLAB_CONFIG_DIR, `api user` as
# pretty-printed JSON, key upload, credential helper.
cat > "$SANDBOX/fakebin/glab" <<'EOF'
#!/usr/bin/env bash
login="${FAKE_LOGIN:-tanuki}"
[[ "${1:-} ${2:-} ${3:-}" == "auth login --help" ]] && { echo "  --insecure-storage   Store the token as plaintext"; exit 0; }
case "${1:-} ${2:-}" in
  "auth login")
    printf 'git_protocol: https\nhosts:\n    gitlab.com:\n        token: glpat-x\n        api_host: gitlab.com\n        user: %s\n' "$login" > "$GLAB_CONFIG_DIR/config.yml"
    echo "$*" > "$GLAB_CONFIG_DIR/login-args"; exit 0 ;;
  "auth logout") exit 0 ;;
  "auth git-credential")
    cat >/dev/null; printf 'protocol=https\nhost=gitlab.com\nusername=x\npassword=token-for-%s\n' "$GLAB_CONFIG_DIR"; exit 0 ;;
  "ssh-key add") cp "$3" "$GLAB_CONFIG_DIR/uploaded.pub"; echo "${GITLAB_HOST:-}" > "$GLAB_CONFIG_DIR/upload-host"; exit 0 ;;
  "config set") echo "$*" >> "$GLAB_CONFIG_DIR/config-set"; exit 0 ;;
esac
if [[ "${1:-}" == api ]]; then
  user="$(awk '$1 == "user:" {print $2; exit}' "$GLAB_CONFIG_DIR/config.yml" 2>/dev/null)"
  [[ -n "$user" ]] || exit 1
  printf '{\n  "id": 77,\n  "username": "%s",\n  "name": "Tanuki %s",\n  "public_email": "",\n  "commit_email": "%s@commits.example",\n  "identities": [{"provider": "x"}]\n}\n' "$user" "$user" "$user"
  exit 0
fi
[[ "${1:-}" == "--version" ]] && { echo "glab 0.0.0 (fake)"; exit 0; }
echo "glab config=${GLAB_CONFIG_DIR:-} gh-config=${GH_CONFIG_DIR:-} account=${GHAM_ACCOUNT_ACTIVE:-} args=$*"
EOF
chmod +x "$SANDBOX/fakebin/glab"
export PATH="$SANDBOX/fakebin:$PATH"

# An existing identity to import.
cat > "$HOME/.gitconfig" <<'EOF'
[user]
	name = Global Me
	email = me@example.com
[init]
	defaultBranch = main
EOF
printf 'github.com:\n    users:\n        me:\n    user: me\n' > "$HOME/.config/gh/hosts.yml"
echo 'aliases: {co: pr checkout}' > "$HOME/.config/gh/config.yml"

"$ROOT/install.sh" >/dev/null
eval "$("$GHAM_HOME/bin/gham" init bash)"

pass=0
check() { # check <description> <command…>
  local desc="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $desc"; else echo "FAIL $desc" >&2; exit 1; fi
}
contains() { grep -q -- "$2" <<<"$1"; }
email_in() { (cd "$1" && git config user.email); }

check "git goes through the shim" [ "$(command -v git)" = "$GHAM_HOME/bin/git" ]
check "gh goes through the shim" [ "$(command -v gh)" = "$GHAM_HOME/bin/gh" ]
check "glab goes through the shim" [ "$(command -v glab)" = "$GHAM_HOME/bin/glab" ]
check "version prints" contains "$(gham version)" "gham "
check "no accounts: git passes straight through" [ "$(email_in "$SANDBOX/oss")" = me@example.com ]

# Import the existing identity.
gham add personal --import 2>/dev/null
check "import copies the gh login" grep -q 'user: me' "$GHAM_HOME/accounts/personal/gh/hosts.yml"
check "import takes the git identity" grep -q '^email=me@example.com' "$GHAM_HOME/accounts/personal/account.conf"
check "import records the gh user" grep -q '^login=me' "$GHAM_HOME/accounts/personal/account.conf"
check "first account becomes default" [ "$(gham default)" = personal ]
check "gh config.yml is shared" [ "$(readlink "$GHAM_HOME/accounts/personal/gh/config.yml")" = "$HOME/.config/gh/config.yml" ]

# A new account: login, API identity, generated + uploaded SSH key.
FAKE_LOGIN=octo-work gham add work 2>/dev/null
w="$GHAM_HOME/accounts/work"
check "add logs in through gh" grep -q 'user: octo-work' "$w/gh/hosts.yml"
check "add asks for the key-upload scope" grep -q 'admin:public_key' "$w/gh/login-args"
check "add keeps the token in the account, not the shared keyring" grep -q -- '--insecure-storage' "$w/gh/login-args"
check "add fills the login from the API" grep -q '^login=octo-work' "$w/account.conf"
check "add uses the noreply email when none is public" grep -q '^email=42+octo-work@users.noreply.github.com' "$w/account.conf"
check "add generates an SSH key" [ -f "$w/ssh/id_ed25519" ]
check "add uploads the SSH key" cmp -s "$w/ssh/id_ed25519.pub" "$w/gh/uploaded.pub"
check "add switches gh to ssh" grep -q 'git_protocol ssh' "$w/gh/config-set"
check "second account does not steal the default" [ "$(gham default)" = personal ]

gham add bare --no-login --no-ssh --git-email bare@example.com 2>/dev/null
check "no-login account is listed as such" contains "$(gham list)" "no-login"

# Directory binds.
gham bind "$SANDBOX/work" work 2>/dev/null
check "outside a bind: the default" [ "$(email_in "$SANDBOX/oss")" = me@example.com ]
check "inside a bind: the bound account" [ "$(email_in "$SANDBOX/work/repo")" = 42+octo-work@users.noreply.github.com ]
check "bind matches the bound dir itself" [ "$(email_in "$SANDBOX/work")" = 42+octo-work@users.noreply.github.com ]
check "bind does not match a sibling prefix" bash -c "mkdir -p '$SANDBOX/workshop' && [ \"\$(cd '$SANDBOX/workshop' && git config user.email)\" = me@example.com ]"
check "git -C resolves the target dir" [ "$(cd "$SANDBOX/oss" && git -C ../work/repo config user.email)" = 42+octo-work@users.noreply.github.com ]
check "bound account gets its SSH key" contains "$(cd "$SANDBOX/work" && git config core.sshCommand)" "$w/ssh/id_ed25519"
check "default account has no SSH override" bash -c "! (cd '$SANDBOX/oss' && git config core.sshCommand)"
cred="$(cd "$SANDBOX/work" && printf 'protocol=https\nhost=github.com\n\n' | git credential fill)"
check "HTTPS credentials come from the bound account's gh" contains "$cred" "token-for-$w/gh"
check "gh in a bind uses the bound login" contains "$(cd "$SANDBOX/work" && gh repo list)" "config=$w/gh"
check "current explains a bind" contains "$(cd "$SANDBOX/work/repo" && gham current)" "bind $SANDBOX/work"
check "list marks the active account here" contains "$(cd "$SANDBOX/work" && gham list)" "> work"
check "list counts binds" contains "$(gham list)" "1 bind"

mkdir -p "$SANDBOX/work/client"
gham bind "$SANDBOX/work/client" bare 2>/dev/null
check "the longest bind wins" [ "$(email_in "$SANDBOX/work/client")" = bare@example.com ]
gham unbind "$SANDBOX/work/client" 2>/dev/null
check "unbind falls back to the outer bind" [ "$(email_in "$SANDBOX/work/client")" = 42+octo-work@users.noreply.github.com ]

# Overrides: gham use and gham run win over a bind.
gham use personal >/dev/null 2>&1
check "gham use overrides a bind" [ "$(email_in "$SANDBOX/work")" = me@example.com ]
gham use --default >/dev/null 2>&1
check "gham use --default restores the bind" [ "$(email_in "$SANDBOX/work")" = 42+octo-work@users.noreply.github.com ]
check "gham run overrides a bind" [ "$(cd "$SANDBOX/work" && gham run personal git config user.email)" = me@example.com ]
check "gham run pins child processes" [ "$(cd "$SANDBOX/oss" && gham run work bash -c 'cd ../work && git config user.email')" = 42+octo-work@users.noreply.github.com ]
check "gham run without a bind" [ "$(cd "$SANDBOX/oss" && gham run work git config user.email)" = 42+octo-work@users.noreply.github.com ]
check "nested shims do not stack config" [ "$(gham run work git -c alias.e='!git config user.email' e)" = 42+octo-work@users.noreply.github.com ]

# A real commit gets the right author, and ~/.gitconfig is never touched.
(cd "$SANDBOX/work/repo" && git init -q && git commit -q --allow-empty -m test)
check "a commit is authored by the bound account" [ "$(cd "$SANDBOX/work/repo" && git log -1 --format=%ae)" = 42+octo-work@users.noreply.github.com ]
check "the global gitconfig keeps its identity" grep -q 'email = me@example.com' "$HOME/.gitconfig"
check "a repo-local identity is overridden by the account" bash -c "cd '$SANDBOX/work/repo' && command '$GHAM_HOME/bin/git' config user.email local@example.com && [ \"\$(git config user.email)\" = 42+octo-work@users.noreply.github.com ]"

# env for scripts.
envout="$(cd "$SANDBOX/oss" && gham env work)"
check "env exports GH_CONFIG_DIR" contains "$envout" "GH_CONFIG_DIR=$w/gh"
check "env exports the git identity" [ "$(cd "$SANDBOX/oss" && eval "$envout" && command "$(gham doctor | awk '/^real git/ {print $3}')" config user.email)" = 42+octo-work@users.noreply.github.com ]

# Owner binds: a personal repo inside a work-bound tree, holding bare repos
# and worktrees of the work org — git follows each repository's remote.
hub="$SANDBOX/work/hub"
mkdir -p "$hub/.repos" "$hub/services"
(cd "$hub" && command git init -q && command git remote add origin git@github.com:cymon1997/HUB.git)
command git init -q "$SANDBOX/seed" && command git -C "$SANDBOX/seed" -c user.email=s@x -c user.name=s commit -q --allow-empty -m seed
command git clone -q --bare "$SANDBOX/seed" "$hub/.repos/api.git"
command git -C "$hub/.repos/api.git" remote set-url origin https://github.com/acme/api.git
command git -C "$hub/.repos/api.git" worktree add -q "$hub/services/api" HEAD 2>/dev/null
gham owner cymon1997 personal 2>/dev/null
gham owner Acme work 2>/dev/null
check "owner keys are host/owner, lowercase" grep -q "^github.com/acme"$'\t'"work" "$GHAM_HOME/owners"
check "owner beats the directory bind" [ "$(email_in "$hub")" = me@example.com ]
check "owner applies in a subdirectory" bash -c "cd '$hub/services' && [ \"\$(git config user.email)\" = me@example.com ]"
check "bare repo resolves by its remote" [ "$(cd "$hub" && git -C .repos/api.git config user.email)" = 42+octo-work@users.noreply.github.com ]
check "linked worktree resolves by its remote" [ "$(email_in "$hub/services/api")" = 42+octo-work@users.noreply.github.com ]
check "owner works outside any bind" [ "$(cd "$SANDBOX/oss" && git -C "$hub/.repos/api.git" config user.email)" = 42+octo-work@users.noreply.github.com ]
check "gh still follows the directory bind" contains "$(cd "$hub" && gh repo list)" "config=$w/gh"
cur="$(cd "$hub" && gham current)"
check "current names the owner for git" contains "$cur" "owner github.com/cymon1997"
check "current shows gh separately when it differs" contains "$cur" "gh/glab here: work"
check "gham run beats the owner" [ "$(cd "$hub" && gham run work git config user.email)" = 42+octo-work@users.noreply.github.com ]
(cd "$hub" && command git remote set-url origin git@github.com:someone-else/HUB.git)
check "an unbound owner falls back to the bind" [ "$(email_in "$hub")" = 42+octo-work@users.noreply.github.com ]
(cd "$hub" && command git remote set-url origin ssh://git@github.com:22/CYMON1997/HUB)
check "ssh:// URLs with a port match" [ "$(email_in "$hub")" = me@example.com ]

# git clone has no repository yet: the URL decides. A fake ssh records the key.
printf '#!/usr/bin/env bash\necho "$*" > "%s/ssh-args"; exit 1\n' "$SANDBOX" > "$SANDBOX/fakebin/ssh"; chmod +x "$SANDBOX/fakebin/ssh"
(cd "$SANDBOX/oss" && git clone -q --bare git@github.com:acme/web.git y.git >/dev/null 2>&1 || true)
check "clone resolves by the URL's owner" grep -q "$w/ssh/id_ed25519" "$SANDBOX/ssh-args"
rm -f "$SANDBOX/fakebin/ssh"
check "list counts owners" contains "$(gham list)" "1 owner"
check "owners lists the binds" contains "$(gham owners)" "github.com/cymon1997/\*"
gham unowner cymon1997 2>/dev/null
check "unowner removes it" bash -c "! grep -q cymon1997 '$GHAM_HOME/owners'"

# set, rename, remove.
gham set work email work@company.example 2>/dev/null
check "set changes the email" [ "$(email_in "$SANDBOX/work")" = work@company.example ]
check "set shows the settings" contains "$(gham set work)" "ssh-key"
gham rename work job 2>/dev/null
check "rename carries the bind" [ "$(email_in "$SANDBOX/work")" = work@company.example ]
check "rename moves the SSH key path" contains "$(gham set job)" "accounts/job/ssh/id_ed25519"
check "rename carries the owner bind" grep -q "^github.com/acme"$'\t'"job" "$GHAM_HOME/owners"
gham default job 2>/dev/null
gham remove job -y 2>/dev/null
check "remove deletes the account" [ ! -d "$GHAM_HOME/accounts/job" ]
check "remove drops its binds" bash -c "! grep -q job '$GHAM_HOME/binds'"
check "remove drops its owner binds" bash -c "! grep -q job '$GHAM_HOME/owners'"
check "remove clears the default" bash -c "! gham default 2>/dev/null"
check "shared gh config survives remove" [ -f "$HOME/.config/gh/config.yml" ]

# Tab completion, driven the way readline calls it.
complete_words() { COMP_WORDS=("$@"); COMP_CWORD=$((${#COMP_WORDS[@]} - 1)); _gham_complete; echo "${COMPREPLY[*]}"; }
check "list --names prints bare names" [ "$(gham list --names | tr '\n' ' ')" = "bare personal " ]
check "completion offers providers" [ "$(complete_words gham add --provider gi)" = "github gitlab git" ]
check "completion offers subcommands" contains "$(complete_words gham bi)" "bind"
check "completion offers account names" [ "$(complete_words gham use pe)" = personal ]
check "completion offers set keys" contains "$(complete_words gham set bare '')" "ssh-key"
if command -v zsh >/dev/null; then
  check "zsh completion registers" contains \
    "$(zsh -fc 'eval "$("$1" init zsh)"; print -r -- "$_comps[gham]"' _ "$GHAM_HOME/bin/gham")" "_gham"
fi

# GitLab through glab.
gham add lab --provider gitlab 2>/dev/null
l="$GHAM_HOME/accounts/lab"
check "gitlab: add logs in through glab" grep -q 'user: tanuki' "$l/glab/config.yml"
check "gitlab: login targets gitlab.com" grep -q -- '--hostname gitlab.com' "$l/glab/login-args"
check "gitlab: provider and host are recorded" bash -c "grep -q '^provider=gitlab' '$l/account.conf' && grep -q '^host=gitlab.com' '$l/account.conf'"
check "gitlab: login comes from the API" grep -q '^login=tanuki' "$l/account.conf"
check "gitlab: the commit email comes from the API" grep -q '^email=tanuki@commits.example' "$l/account.conf"
check "gitlab: the name is the top-level one" grep -q '^name=Tanuki tanuki' "$l/account.conf"
check "gitlab: add uploads the SSH key through glab" cmp -s "$l/ssh/id_ed25519.pub" "$l/glab/uploaded.pub"
check "gitlab: switches glab to ssh in the account's own config" grep -q -- '--global --host gitlab.com git_protocol ssh' "$l/glab/config-set"
check "gitlab: keeps the token out of the shared keyring" grep -q -- '--insecure-storage' "$l/glab/login-args"
check "gitlab: the key goes to the account's host" grep -qx 'gitlab.com' "$l/glab/upload-host"
check "gitlab: no gh directory" [ ! -e "$l/gh" ]
mkdir -p "$SANDBOX/lab/repo"
gham bind "$SANDBOX/lab" lab 2>/dev/null
check "gitlab: a bind gives the identity" [ "$(email_in "$SANDBOX/lab/repo")" = tanuki@commits.example ]
check "gitlab: a bind gives the SSH key" contains "$(cd "$SANDBOX/lab" && git config core.sshCommand)" "$l/ssh/id_ed25519"
cred="$(cd "$SANDBOX/lab" && printf 'protocol=https\nhost=gitlab.com\n\n' | git credential fill)"
check "gitlab: HTTPS credentials come from the account's glab" contains "$cred" "token-for-$l/glab"
check "gitlab: glab in a bind uses the account's config" contains "$(cd "$SANDBOX/lab" && glab repo list)" "config=$l/glab"
check "gitlab: gh in a gitlab bind runs with your normal login" contains "$(cd "$SANDBOX/lab" && gh repo list)" "config= account= "
check "github: glab as a github account runs with your normal login" contains "$(gham run personal glab repo list)" "glab config= gh-config=$GHAM_HOME/accounts/personal/gh"
check "gitlab: env exports GLAB_CONFIG_DIR, not GH_CONFIG_DIR" bash -c "o=\"\$(gham env lab)\"; grep -q 'GLAB_CONFIG_DIR=' <<<\"\$o\" && ! grep -q 'GH_CONFIG_DIR' <<<\"\$o\""
gham owner Group lab 2>/dev/null
check "gitlab: a bare owner takes the account's host" grep -q "^gitlab.com/group"$'\t'"lab" "$GHAM_HOME/owners"
(cd "$SANDBOX/oss" && command git init -q nested && command git -C nested remote add origin git@gitlab.com:group/sub/deep.git)
check "gitlab: a nested group repo matches its top group" [ "$(email_in "$SANDBOX/oss/nested")" = tanuki@commits.example ]
gham unowner group 2>/dev/null
check "gitlab: unowner finds the bare owner on its host" bash -c "! grep -q 'gitlab.com/group' '$GHAM_HOME/owners'"

# A plain git account: any host, no CLI.
check "git: needs a host" bash -c "! gham add bb --provider git --git-email x@y 2>/dev/null"
check "git: needs an email" bash -c "! gham add bb --provider git --hostname bitbucket.org 2>/dev/null"
check "git: leaves nothing behind when refused" [ ! -d "$GHAM_HOME/accounts/bb" ]
hint="$(gham add bb --provider git --hostname bitbucket.org --user bbme --git-email bb@example.com 2>&1)"
b="$GHAM_HOME/accounts/bb"
check "git: generates an SSH key" [ -f "$b/ssh/id_ed25519" ]
check "git: prints the key to add by hand" contains "$hint" "$(cut -d' ' -f2 "$b/ssh/id_ed25519.pub")"
check "git: points at the host's key page" contains "$hint" "bitbucket.org/account/settings/ssh-keys"
check "git: no CLI directory" bash -c "[ ! -e '$b/gh' ] && [ ! -e '$b/glab' ]"
check "git: name falls back to the global one" grep -q '^name=Global Me' "$b/account.conf"
mkdir -p "$SANDBOX/bb"
gham bind "$SANDBOX/bb" bb 2>/dev/null
check "git: a bind gives the identity" [ "$(email_in "$SANDBOX/bb")" = bb@example.com ]
check "git: a bind gives the SSH key" contains "$(cd "$SANDBOX/bb" && git config core.sshCommand)" "$b/ssh/id_ed25519"
check "git: HTTPS names the user" [ "$(cd "$SANDBOX/bb" && git config credential.https://bitbucket.org.username)" = bbme ]
git config --global credential.https://bitbucket.org.helper my-keyring
check "git: the user's own credential helper is kept" [ "$(cd "$SANDBOX/bb" && git config --get-all credential.https://bitbucket.org.helper)" = my-keyring ]
check "git: login is refused with a reason" bash -c "gham login bb 2>&1 | grep -q 'nothing to log in to'"
check "git: list marks it as git, not no-login" bash -c "gham list | grep ' bb ' | grep -q 'bbme@bitbucket.org (git)'"
check "git: gh in a git bind runs with your normal login" contains "$(cd "$SANDBOX/bb" && gh repo list)" "config= account= "
check "git: env exports no CLI config dir" bash -c "! gham env bb | grep -q CONFIG_DIR="

# Accounts written by gham 0.2 have no provider line and stay GitHub accounts.
mkdir -p "$GHAM_HOME/accounts/legacy/gh"
printf '# old\nlogin=old\nhost=github.com\nname=Old\nemail=old@example.com\nssh_key=\n' > "$GHAM_HOME/accounts/legacy/account.conf"
check "legacy: still a github account" contains "$(gham set legacy)" "provider github"
check "legacy: git gets the gh credential helper" contains "$(gham run legacy git config --get-all credential.https://github.com.helper)" "auth git-credential"
check "legacy: gh gets the account's config dir" contains "$(gham run legacy gh repo list)" "config=$GHAM_HOME/accounts/legacy/gh"

# ssh greetings from different hosts.
# eval, not `source <(…)`: bash 3.2 reads nothing from a process substitution.
greet() { bash -c 'eval "$(sed -n "/^ssh_greeting()/,/^}/p" "$1")"; ssh_greeting "$2" && echo "ok:$S_USER"' _ "$GHAM_HOME/bin/gham" "$1"; }
check "ssh: GitHub greeting" [ "$(greet "Hi octo! You've successfully authenticated, but GitHub does not provide shell access.")" = ok:octo ]
check "ssh: GitLab greeting" [ "$(greet "Welcome to GitLab, @tanuki!")" = ok:tanuki ]
check "ssh: Gitea greeting" [ "$(greet "Hi there, gitea-user! You've successfully authenticated with the key named k")" = ok:gitea-user ]
check "ssh: Bitbucket greeting" [ "$(greet "authenticated via ssh key.")" = ok: ]
check "ssh: a refusal fails" [ -z "$(greet 'git@x: Permission denied (publickey).')" ]

check "unknown provider fails" bash -c "! gham add z --provider svn 2>/dev/null"
check "unknown account fails" bash -c "! gham run nope true 2>/dev/null"
check "binding to an unknown account fails" bash -c "! gham bind '$SANDBOX/oss' nope 2>/dev/null"
check "a pinned unknown account fails loudly" bash -c "! GHAM_ACCOUNT_ACTIVE=nope git status 2>/dev/null"

echo "$pass checks passed"
