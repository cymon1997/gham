#!/usr/bin/env bash
# Smoke tests for gham. Uses a fake `gh` and the real git, so no network or
# login is needed. Run from the repository root:  ./tests/smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export GHAM_HOME="$HOME/.gham"
export SHELL=/bin/bash
export XDG_CONFIG_HOME="$HOME/.config"
unset GHAM_ACCOUNT GHAM_ACCOUNT_ACTIVE GHAM_ENV_APPLIED GHAM_SHELL_INIT GH_CONFIG_DIR GH_TOKEN GITHUB_TOKEN \
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
check "~/.gitconfig keeps the global identity" grep -q 'email = me@example.com' "$HOME/.gitconfig"
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
command git clone -q --bare "$SANDBOX/seed" "$hub/.repos/TIX-X.git"
command git -C "$hub/.repos/TIX-X.git" remote set-url origin https://github.com/tiket/TIX-X.git
command git -C "$hub/.repos/TIX-X.git" worktree add -q "$hub/services/TIX-X" HEAD 2>/dev/null
gham owner cymon1997 personal 2>/dev/null
gham owner Tiket work 2>/dev/null
check "owner keys are host/owner, lowercase" grep -q "^github.com/tiket"$'\t'"work" "$GHAM_HOME/owners"
check "owner beats the directory bind" [ "$(email_in "$hub")" = me@example.com ]
check "owner applies in a subdirectory" bash -c "cd '$hub/services' && [ \"\$(git config user.email)\" = me@example.com ]"
check "bare repo resolves by its remote" [ "$(cd "$hub" && git -C .repos/TIX-X.git config user.email)" = 42+octo-work@users.noreply.github.com ]
check "linked worktree resolves by its remote" [ "$(email_in "$hub/services/TIX-X")" = 42+octo-work@users.noreply.github.com ]
check "owner works outside any bind" [ "$(cd "$SANDBOX/oss" && git -C "$hub/.repos/TIX-X.git" config user.email)" = 42+octo-work@users.noreply.github.com ]
check "gh still follows the directory bind" contains "$(cd "$hub" && gh repo list)" "config=$w/gh"
cur="$(cd "$hub" && gham current)"
check "current names the owner for git" contains "$cur" "owner github.com/cymon1997"
check "current shows gh separately when it differs" contains "$cur" "gh here: work"
check "gham run beats the owner" [ "$(cd "$hub" && gham run work git config user.email)" = 42+octo-work@users.noreply.github.com ]
(cd "$hub" && command git remote set-url origin git@github.com:someone-else/HUB.git)
check "an unbound owner falls back to the bind" [ "$(email_in "$hub")" = 42+octo-work@users.noreply.github.com ]
(cd "$hub" && command git remote set-url origin ssh://git@github.com:22/CYMON1997/HUB)
check "ssh:// URLs with a port match" [ "$(email_in "$hub")" = me@example.com ]

# git clone has no repository yet: the URL decides. A fake ssh records the key.
printf '#!/usr/bin/env bash\necho "$*" > "%s/ssh-args"; exit 1\n' "$SANDBOX" > "$SANDBOX/fakebin/ssh"; chmod +x "$SANDBOX/fakebin/ssh"
(cd "$SANDBOX/oss" && git clone -q --bare git@github.com:tiket/TIX-Y.git y.git >/dev/null 2>&1 || true)
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
check "rename carries the owner bind" grep -q "^github.com/tiket"$'\t'"job" "$GHAM_HOME/owners"
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
check "completion offers subcommands" contains "$(complete_words gham bi)" "bind"
check "completion offers account names" [ "$(complete_words gham use pe)" = personal ]
check "completion offers set keys" contains "$(complete_words gham set bare '')" "ssh-key"
if command -v zsh >/dev/null; then
  check "zsh completion registers" contains \
    "$(zsh -fc 'eval "$("$1" init zsh)"; print -r -- "$_comps[gham]"' _ "$GHAM_HOME/bin/gham")" "_gham"
fi

check "unknown account fails" bash -c "! gham run nope true 2>/dev/null"
check "binding to an unknown account fails" bash -c "! gham bind '$SANDBOX/oss' nope 2>/dev/null"
check "a pinned unknown account fails loudly" bash -c "! GHAM_ACCOUNT_ACTIVE=nope git status 2>/dev/null"

echo "$pass checks passed"
