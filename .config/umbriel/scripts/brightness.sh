#!/usr/bin/env bash
# Brightness keys: laptop backlight via Noctalia, external DDC via ddcutil.
# Umbriel 版：focused-output 查询同时支持 umbriel / niri。
#
# 保持 Noctalia [brightness] enable_ddcutil = false（避免 NVIDIA 开机扫 I2C）。
# 内屏走 Noctalia 背光，外接屏走 ddcutil。

set -uo pipefail

dir="${1:-}"
case "$dir" in
    up|down) ;;
    *)
        printf 'usage: brightness.sh up|down\n' >&2
        exit 2
        ;;
esac

if command -v noctalia >/dev/null 2>&1; then
    noctalia msg "brightness-${dir}" || true
fi

connector=""
if [ -n "${UMBRIEL_SOCKET:-}" ] && command -v umbriel >/dev/null 2>&1; then
    connector="$(umbriel outputs --json 2>/dev/null \
        | jq -r '[.[] | select(.focused == true) | .name][0] // empty' 2>/dev/null || true)"
elif command -v niri >/dev/null 2>&1 && [ -n "${NIRI_SOCKET:-}" ]; then
    connector="$(niri msg focused-output 2>/dev/null | sed -n '1s/.*(\([^)]*\))$/\1/p')"
fi

case "$connector" in
    eDP-*|LVDS-*|DSI-*)
        exit 0
        ;;
esac

backlight_dir="${NYXURI_BACKLIGHT_DIR:-${NYXNIRI_BACKLIGHT_DIR:-/sys/class/backlight}}"
has_backlight=false
if [ -d "$backlight_dir" ]; then
    for dev in "$backlight_dir"/*; do
        if [ -e "$dev" ]; then
            has_backlight=true
            break
        fi
    done
fi

# 未知 connector 但机器有 sysfs 背光：按内屏处理，避免 NVIDIA 笔记本每次按键都 I2C 超时。
if [ -z "$connector" ] && [ "$has_backlight" = true ]; then
    exit 0
fi

noctalia_ddc=false
conf="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/noctalia-config.toml"
if [ -f "$conf" ] && grep -E '^[[:space:]]*enable_ddcutil[[:space:]]*=[[:space:]]*true\b' "$conf" >/dev/null 2>&1; then
    noctalia_ddc=true
fi
if [ "$noctalia_ddc" = true ]; then
    exit 0
fi

if ! command -v ddcutil >/dev/null 2>&1; then
    exit 0
fi

if [ "$dir" = up ]; then
    ddcutil setvcp 10 + 10 >/dev/null 2>&1 || true
else
    ddcutil setvcp 10 - 10 >/dev/null 2>&1 || true
fi
