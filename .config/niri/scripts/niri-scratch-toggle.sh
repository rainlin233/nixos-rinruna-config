#!/usr/bin/env bash
# Nyxuri multi-app scratchpad toggle
# Controls floating scratchpad lifecycle for Kitty, Mission Center, Nautilus, and custom apps.
#
# 同时支持 niri 与 umbriel：
#   在 umbriel 会话中（UMBRIEL_SOCKET 存在）走 umbriel IPC，
#   kitty 使用 umbriel 原生 [[scratchpad]]（见 ~/.config/umbriel/config.toml）。
#   Orbit 启动器仍按原路径调用本脚本，因此不需要改 Python。
# shellcheck disable=SC2317
set -uo pipefail

TARGET_APP="${1:-kitty}"

COMPOSITOR="niri"
if [ -n "${UMBRIEL_SOCKET:-}" ] && command -v umbriel >/dev/null 2>&1; then
    COMPOSITOR="umbriel"
fi

active_workspace() {
    if [ "$COMPOSITOR" = "umbriel" ]; then
        umbriel workspaces --json 2>/dev/null \
            | jq -r '[.[] | select(.focused == true)][0].id // empty' 2>/dev/null
    else
        niri msg -j workspaces 2>/dev/null \
            | jq -r '(.[] | select(.is_focused == true) | .id) // (.[] | select(.is_active == true) | .id)' \
            | head -n1
    fi
}

# 输出 "id workspace"
find_window() {
    local app_id="$1"
    if [ "$COMPOSITOR" = "umbriel" ]; then
        umbriel windows --json 2>/dev/null \
            | jq -r --arg id "$app_id" \
                '[.[] | select(.app_id == $id)][0] | "\(.id) \(.workspace)"' 2>/dev/null
    else
        niri msg -j windows 2>/dev/null \
            | jq -r --arg id "$app_id" \
                '.[] | select(.app_id == $id) | "\(.id) \(.workspace_id)"' \
            | head -n1
    fi
}

focused_window() {
    if [ "$COMPOSITOR" = "umbriel" ]; then
        umbriel windows --json 2>/dev/null \
            | jq -r '[.[] | select(.focused == true)][0].id // empty' 2>/dev/null
    else
        niri msg -j focused-window 2>/dev/null | jq -r '.id // empty' 2>/dev/null
    fi
}

act_spawn() {
    if [ "$COMPOSITOR" = "umbriel" ]; then
        umbriel msg spawn "$*"
    else
        niri msg action spawn -- "$@"
    fi
}

act_close() {
    if [ "$COMPOSITOR" = "umbriel" ]; then
        umbriel msg window-close "$1" >/dev/null 2>&1 || true
    else
        niri msg action close-window --id "$1"
    fi
}

act_focus() {
    if [ "$COMPOSITOR" = "umbriel" ]; then
        umbriel msg window-focus "$1" >/dev/null 2>&1 || true
    else
        niri msg action focus-window --id "$1"
    fi
}

# ── Serialization Lock ──────────────────────────────────────────────
LOCK_NAME=$(printf '%s' "$TARGET_APP" | tr -c 'a-zA-Z0-9_' '_')
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/nyxuri-${UID}-scratch-${LOCK_NAME}.lock"
flock -n 9 || exit 0

case "$TARGET_APP" in
    kitty|terminal|Kitty|Terminal)
        APP_ID="scratchpad"
        TMUX_SESSION="scratch"

        spawn_kitty() {
            if command -v tmux >/dev/null 2>&1; then
                act_spawn kitty --app-id "$APP_ID" --title "Scratchpad" \
                    tmux new-session -A -D -s "$TMUX_SESSION" \
                    "fish -C 'function fish_greeting; end' -C 'set -g fish_history scratchpad'" \
                    \; set-option status off \
                    \; set-option mouse on \
                    \; set-option history-limit 50000
            else
                act_spawn kitty --app-id "$APP_ID" --title "Scratchpad"
            fi
        }

        if [ "$COMPOSITOR" = "umbriel" ]; then
            # 原生 scratchpad：空时自动按 spawn_when_empty 启动，已存在则显示/隐藏
            if ! umbriel msg scratchpad-toggle terminal >/dev/null 2>&1; then
                spawn_kitty
            fi
            exit 0
        fi

        ACTIVE_WS=$(active_workspace)
        read -r win_id win_ws < <(find_window "$APP_ID")

        if [ -z "${win_id:-}" ]; then
            spawn_kitty
        elif [ -n "$ACTIVE_WS" ] && [ -n "${win_ws:-}" ] && [ "$win_ws" != "$ACTIVE_WS" ]; then
            act_close "$win_id"
            sleep 0.05
            spawn_kitty
        else
            act_close "$win_id"
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
        elif [ -f "$(dirname "${BASH_SOURCE[0]}")/../../noctalia/tools/wallpaper-picker.py" ]; then
            act_spawn python3 "$(dirname "${BASH_SOURCE[0]}")/../../noctalia/tools/wallpaper-picker.py"
        else
            act_spawn wallpaper-picker.py
        fi
        ;;

    clean|clean-cache.py|\~/.config/fish/clean-cache.py|"$HOME/.config/fish/clean-cache.py")
        # Older preserved Orbit menus still carry the former script path.
        act_spawn kitty --app-id "scratchpad" -e nyxuri clean
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
