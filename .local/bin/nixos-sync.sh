#!/usr/bin/env bash
# 登录同步 /etc/nixos -> ~/dotfiles/（根目录） -> GitHub。
# 由 niri spawn-at-startup 调用（见 __custom__.kdl），best-effort，永不报错。
# 要求：GitHub 上已有同名仓库；push 走 SSH（~/.ssh/id_ed25519，无密码短语）。
set -uo pipefail

# 非交互环境：永远别弹密码框，拿不到凭证就快速失败（外层有 timeout 兜底）。
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"

# niri 重启也会触发 spawn，串行化防并发。
exec 9> "${XDG_RUNTIME_DIR:-/tmp}/nyxuri-${UID}-nixos-sync.lock"
flock -w 10 9 || exit 0

SRC="/etc/nixos"
REPO="$HOME/dotfiles"
DST="$REPO"
FILES=(configuration.nix home.nix flake.nix flake.lock hardware-configuration.nix)

mkdir -p "$DST"

sync_one() {
    local f="$1"
    [ -f "$SRC/$f" ] || return 0
    local tmp
    tmp="$(mktemp)" || return 0
    cp "$SRC/$f" "$tmp"
    if [[ "$f" == "configuration.nix" ]]; then
        sed -e '/^  fileSystems = {/,/^  \};$/d' "$tmp" > "$tmp.stripped"
        if nix-instantiate --parse "$tmp.stripped" >/dev/null 2>&1; then
            mv "$tmp.stripped" "$tmp"
        else
            echo "[nixos-sync] WARNING: strip of $f failed validation, skip this round"
            rm -f "$tmp" "$tmp.stripped"
            return 0
        fi
    fi
    if ! cmp -s "$tmp" "$DST/$f" 2>/dev/null; then
        mv "$tmp" "$DST/$f"
        echo "[nixos-sync] updated $f"
    else
        rm -f "$tmp"
    fi
}

for f in "${FILES[@]}"; do
    sync_one "$f"
done

cd "$REPO" || exit 0
git add -- "${FILES[@]}" 2>/dev/null || exit 0

if git diff --cached --quiet; then
    echo "[nixos-sync] no changes, skip commit"
else
    git commit -qm "Auto-sync /etc/nixos $(date '+%F %T')" || exit 0
    echo "[nixos-sync] committed"
fi

# 只在本地领先远端时 push；没网/没 key/被拒都静默跳过，不断言失败。
# niri 启动时网络可能还没就绪，最多等 ~60 秒。
if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    if [ "$(git rev-list --count HEAD..'@{u}' 2>/dev/null)" = "0" ] && \
       [ "$(git rev-list --count '@{u}'..HEAD 2>/dev/null)" != "0" ]; then
        for _ in $(seq 1 12); do
            if timeout 8 git ls-remote origin HEAD >/dev/null 2>&1; then
                break
            fi
            sleep 5
        done
        if timeout 90 git push origin main 2>&1 | tail -3; then
            echo "[nixos-sync] pushed"
        else
            echo "[nixos-sync] push failed (offline / no key / rejected), left for manual push"
        fi
    else
        echo "[nixos-sync] nothing to push or diverged, skip"
    fi
else
    echo "[nixos-sync] no upstream set, skip push"
fi

exit 0
