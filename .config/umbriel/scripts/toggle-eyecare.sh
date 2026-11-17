#!/usr/bin/env bash
# Nyxuri EyeCare One-shot Self-Healing Toggle & Sync Script — Umbriel 版
#
# 与 niri 版本的差异：
#   niri 用 effects.kdl 软链接 + `niri msg action load-config-file`
#   umbriel 用 visuals.toml 软链接 + `umbriel msg config-reload`
# 状态来源仍是软链接自身，重启合成器后自动恢复。
#
# shellcheck disable=SC2317
set -uo pipefail

exec 9> "${XDG_RUNTIME_DIR:-/tmp}/nyxuri-${UID}-eyecare.lock"
flock -w 5 9 || exit 1

UMB_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel"
VISUALS_LINK="$UMB_DIR/visuals.toml"
NORMAL_VISUALS="$UMB_DIR/visuals_normal.toml"
EYECARE_VISUALS="$UMB_DIR/visuals_eyecare.toml"

EYECARE_TEMP=5500

LOG_FILE="${XDG_RUNTIME_DIR:-/tmp}/nyxuri-eyecare.log"

KITTY_CONF="$HOME/.config/kitty/kitty.conf"
KITTY_OPACITY_ON="1.0"
KITTY_OPACITY_OFF="0.9"

HAS_NOCTALIA=false
if command -v noctalia >/dev/null 2>&1; then
    HAS_NOCTALIA=true
fi

reload_compositor() {
    if command -v umbriel >/dev/null 2>&1 && [ -n "${UMBRIEL_SOCKET:-}" ]; then
        umbriel msg config-reload >>"$LOG_FILE" 2>&1 || true
    elif command -v niri >/dev/null 2>&1 && [ -n "${NIRI_SOCKET:-}" ]; then
        niri msg action load-config-file >>"$LOG_FILE" 2>&1 || true
    fi
}

CURRENTLY_ON=false
if [ "$(readlink "$VISUALS_LINK" 2>/dev/null)" = "visuals_eyecare.toml" ] \
    || [ "$(readlink -f "$VISUALS_LINK" 2>/dev/null)" = "$EYECARE_VISUALS" ]; then
    CURRENTLY_ON=true
fi

apply_visuals() {
    local target
    if [ "$1" = "on" ]; then
        target="$EYECARE_VISUALS"
    else
        target="$NORMAL_VISUALS"
    fi

    ln -sfn "$(basename "$target")" "$VISUALS_LINK"
    if [ ! -e "$VISUALS_LINK" ]; then
        echo "$(date '+%F %T') [eyecare] symlink swap failed (target=$target)" >> "$LOG_FILE"
    fi
    reload_compositor
}

# Kitty 自带 background_opacity，niri 的窗口规则覆盖不了；umbriel 同理。
# 改配置行后 SIGUSR1（该选项支持热重载）。
# NixOS: kitty comm 是 ".kitty-wrapped"，按 argv 匹配而不是 -x。
set_kitty_opacity() {
    local value="$1"
    [ -f "$KITTY_CONF" ] || return 0
    if grep -q '^background_opacity' "$KITTY_CONF"; then
        sed -i "s/^background_opacity .*/background_opacity $value/" "$KITTY_CONF"
    else
        printf '\nbackground_opacity %s\n' "$value" >> "$KITTY_CONF"
    fi
    pkill -SIGUSR1 -f '(^|/)[k]itty( |$)' 2>/dev/null || true
}

# --sync：登录时幂等对齐（不翻转）。软链接是持久状态，wlsunset 是易失运行时，
# 每次会话启动都强制重建，避免上一会话遗留的僵尸 wlsunset。
if [ "${1:-}" = "--sync" ]; then
    link_target="$(readlink "$VISUALS_LINK" 2>/dev/null || true)"
    if [ "$link_target" != "visuals_eyecare.toml" ] && [ "$link_target" != "visuals_normal.toml" ]; then
        ln -sfn "visuals_normal.toml" "$VISUALS_LINK"
        CURRENTLY_ON=false
        echo "$(date '+%F %T') [eyecare] healed broken visuals.toml -> Normal" >> "$LOG_FILE"
        reload_compositor
    fi
    sleep 1
    if [ "$HAS_NOCTALIA" = "true" ]; then
        noctalia msg nightlight-disable 2>/dev/null || true
    fi
    pkill -f '[w]lsunset' 2>/dev/null || true
    if [ "$CURRENTLY_ON" = "true" ]; then
        if command -v wlsunset >/dev/null 2>&1; then
            nohup wlsunset -T 6500 -t "$EYECARE_TEMP" -d 0.3 -S 00:00 -s 00:00 >/dev/null 2>&1 9>&- &
        fi
        set_kitty_opacity "$KITTY_OPACITY_ON"
    else
        set_kitty_opacity "$KITTY_OPACITY_OFF"
    fi
    exit 0
fi

# 1. 先让 Noctalia 释放 Wayland gamma 锁，并清掉遗留 wlsunset
if [ "$HAS_NOCTALIA" = "true" ]; then
    noctalia msg nightlight-disable 2>/dev/null || true
fi
pkill -f '[w]lsunset' 2>/dev/null || true

IS_TURNING_ON=false

if [ "$CURRENTLY_ON" = "true" ]; then
    apply_visuals off
    set_kitty_opacity "$KITTY_OPACITY_OFF"
else
    apply_visuals on
    set_kitty_opacity "$KITTY_OPACITY_ON"
    IS_TURNING_ON=true
fi

# 3. 0.3s 平滑过渡到目标色温
if [ "$IS_TURNING_ON" = "true" ]; then
    sleep 0.05
    nohup wlsunset -T 6500 -t "$EYECARE_TEMP" -d 0.3 -S 00:00 -s 00:00 >/dev/null 2>&1 9>&- &
fi

# 4. 通知
if [ "$IS_TURNING_ON" = "true" ]; then
    notify-send -t 2000 "Eye Care : On"
else
    notify-send -t 2000 "Eye Care : Off"
fi
