#!/usr/bin/env bash
# MPRIS 媒体播放防挂起：任一播放器 Playing 时持有 systemd sleep 锁
# 只拦挂起（sleep），不拦息屏
# 适配 systemd user service / Niri / Home Manager

set -uo pipefail

command -v playerctl >/dev/null 2>&1 || {
    echo "mpris-inhibit: playerctl not found" >&2
    exit 1
}

# 单实例
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/mpris-inhibit.lock"
exec 9>"$LOCK_FILE"

flock -n 9 || exit 0


INHIBIT_PID=""
PLAYERCTL_PID=""


cleanup() {
    # 停止 playerctl --follow
    if [ -n "$PLAYERCTL_PID" ]; then
        kill "$PLAYERCTL_PID" 2>/dev/null || true
        wait "$PLAYERCTL_PID" 2>/dev/null || true
    fi

    # 停止 systemd-inhibit
    if [ -n "$INHIBIT_PID" ]; then
        kill "$INHIBIT_PID" 2>/dev/null || true
        wait "$INHIBIT_PID" 2>/dev/null || true
    fi
}


trap cleanup EXIT
trap 'exit 0' INT TERM HUP


start_inhibit() {
    if [ -n "$INHIBIT_PID" ] &&
       kill -0 "$INHIBIT_PID" 2>/dev/null; then
        return
    fi

    systemd-inhibit \
        --who="MPRIS Player" \
        --why="MPRIS Media Playing" \
        --what=sleep \
        --mode=block \
        sleep infinity &

    INHIBIT_PID=$!
}


stop_inhibit() {
    if [ -n "$INHIBIT_PID" ]; then
        kill "$INHIBIT_PID" 2>/dev/null || true
        wait "$INHIBIT_PID" 2>/dev/null || true
        INHIBIT_PID=""
    fi
}


update_inhibit() {
    if playerctl -a status 2>/dev/null | grep -qx "Playing"; then
        start_inhibit
    else
        stop_inhibit
    fi
}


while true; do

    # 启动时检查一次
    update_inhibit


    # 监听播放器事件
    playerctl -a metadata --follow 2>/dev/null |
    while IFS= read -r _; do
        update_inhibit
    done &


    PLAYERCTL_PID=$!


    # 等待监听退出
    wait "$PLAYERCTL_PID"


    PLAYERCTL_PID=""


    # 防止播放器异常退出导致高频循环
    sleep 5

done
