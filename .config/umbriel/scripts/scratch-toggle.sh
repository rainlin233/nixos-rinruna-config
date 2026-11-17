#!/usr/bin/env bash
# Nyxuri multi-app scratchpad toggle (Umbriel)
# 原 niri-scratch-toggle.sh 的 umbriel 专用版本：
#   - kitty 使用 umbriel 原生 [[scratchpad]]（见 ~/.config/umbriel/config.toml）
#   - 其余应用走 umbriel IPC
# Orbit 启动器通过 ~/.config/noctalia/tools/orbit/window.py 调用本脚本。
# shellcheck disable=SC2317
set -uo pipefail

TARGET_APP="${1:-kitty}"

# ── Serialization Lock ──────────────────────────────────────────────
LOCK_NAME=$(printf '%s' "$TARGET_APP" | tr -c 'a-zA-Z0-9_' '_')
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/nyxuri-${UID}-scratch-${LOCK_NAME}.lock"
flock -n 9 || exit 0

# 输出 "id scratchpad"
find_window() {
    local app_id="$1"
    umbriel windows --json 2>/dev/null \
        | jq -r --arg id "$app_id" \
            '[.[] | select(.app_id == $id)][0] | "\(.id) \(.scratchpad)"' 2>/dev/null
}

focused_window() {
    umbriel windows --json 2>/dev/null \
        | jq -r '[.[] | select(.focused == true)][0].id // empty' 2>/dev/null
}

act_spawn() { umbriel msg spawn "$*"; }
act_close() { umbriel msg window-close "$1" >/dev/null 2>&1 || true; }
act_focus() { umbriel msg window-focus "$1" >/dev/null 2>&1 || true; }

case "$TARGET_APP" in
    kitty|terminal|Kitty|Terminal)
        # 原生 scratchpad：空时按 spawn_when_empty 启动，已有窗口则显示/隐藏
        if ! umbriel msg scratchpad-toggle terminal >/dev/null 2>&1; then
            act_spawn kitty --app-id scratchpad --title "Scratchpad" \
                tmux new-session -A -D -s scratch fish
        fi
        ;;

    missioncenter|monitor|"mission center"|"Mission Center"|MissionCenter)
        APP_ID="io.missioncenter.MissionCenter"
        read -r win_id _ < <(find_window "$APP_ID")

        if [ -z "${win_id:-}" ]; then
            if command -v missioncenter >/dev/null 2>&1; then
                act_spawn missioncenter
            elif command -v flatpak >/dev/null 2>&1 && flatpak info io.missioncenter.MissionCenter >/dev/null 2>&1; then
                act_spawn flatpak run io.missioncenter.MissionCenter
            fi
        elif [ "$(focused_window)" = "$win_id" ]; then
            act_close "$win_id"
        else
            act_focus "$win_id"
        fi
        ;;

    nautilus|files|Nautilus|Files)
        APP_ID="org.gnome.Nautilus"
        read -r win_id _ < <(find_window "$APP_ID")

        if [ -z "${win_id:-}" ]; then
            act_spawn nautilus --new-window
        elif [ "$(focused_window)" = "$win_id" ]; then
            act_close "$win_id"
        else
            act_focus "$win_id"
        fi
        ;;

    wallpaper|wallpapers|"wallpaper-picker"|WallpaperPicker|*wallpaper-picker.py)
        if [ -f "$HOME/.config/noctalia/tools/wallpaper-picker.py" ]; then
            act_spawn python3 "$HOME/.config/noctalia/tools/wallpaper-picker.py"
        else
            act_spawn wallpaper-picker.py
        fi
        ;;

    clean|clean-cache.py|\~/.config/fish/clean-cache.py|"$HOME/.config/fish/clean-cache.py")
        # 旧版 Orbit 菜单仍带这个路径
        act_spawn kitty --app-id scratchpad -e nyxuri clean
        ;;

    *)
        if [[ "$TARGET_APP" =~ ^~.* ]]; then
            TARGET_APP="${TARGET_APP/#\~/$HOME}"
        fi
        if [ -x "$TARGET_APP" ] || command -v "$TARGET_APP" >/dev/null 2>&1; then
            act_spawn "$TARGET_APP"
        else
            printf 'scratch-toggle: refusing to run "%s" as a shell command\n' "$TARGET_APP" >&2
        fi
        ;;
esac
