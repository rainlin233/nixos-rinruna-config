#!/usr/bin/env bash
# Niri 手柄防息屏：有手柄连接时持有 systemd idle 锁，拔掉后晃一下鼠标唤醒空闲计时器
set -uo pipefail

# 单实例：niri 重启时旧进程没死透也不会跑重
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/gamepad-keepawake.lock"
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

INHIBIT_PID=""
HAS_DOTOOL=""
command -v dotool >/dev/null 2>&1 && HAS_DOTOOL=1

cleanup_and_wake() {
    if [[ -n "$INHIBIT_PID" ]] && kill -0 "$INHIBIT_PID" 2>/dev/null; then
        kill "$INHIBIT_PID" 2>/dev/null
        wait "$INHIBIT_PID" 2>/dev/null
    fi
    INHIBIT_PID=""

    # 留出足够时间，确保 D-Bus 上的 inhibit 锁彻底解除
    sleep 1

    # 连续发送两次相对位移，唤醒 Niri 的空闲计时器，且光标最终回到原位
    if [[ -n "$HAS_DOTOOL" ]]; then
        dotool << 'EOF'
mousemove 50 50
mousemove -50 -50
EOF
    fi
}

# 手柄是否在线
#
# 不再通过 /dev/input/js* 判断，因为虚拟输入设备（例如 Sunshine）
# 也可能创建 js* 节点。
#
# 使用 udev 的 ID_INPUT_JOYSTICK=1 判断真正的 joystick/gamepad。
gamepad_present() {
    local node

    for node in /dev/input/event*; do
        [ -e "$node" ] || continue

        if udevadm info -q property -n "$node" 2>/dev/null |
            grep -q '^ID_INPUT_JOYSTICK=1$'; then
            return 0
        fi
    done

    return 1
}

apply_state() {
    if gamepad_present; then
        if [[ -z "$INHIBIT_PID" ]] || ! kill -0 "$INHIBIT_PID" 2>/dev/null; then
            systemd-inhibit \
                --why="Gamepad Active" \
                --who="Niri Gamepad Inhibitor" \
                --what="idle" \
                sleep infinity &

            INHIBIT_PID=$!
        fi
    else
        if [[ -n "$INHIBIT_PID" ]]; then
            cleanup_and_wake
        fi
    fi
}

trap cleanup_and_wake EXIT

# 启动时先扫描一次，覆盖 Niri 启动前就已经插着手柄的情况
apply_state

# 事件驱动即时响应 + 60 秒超时兜底
# 防止 input 事件丢失后状态永远不同步
while true; do
    if inotifywait -e create -e delete -e move -t 60 --format '%e' /dev/input 2>/dev/null; then
        # 等设备节点稳定
        sleep 0.5
    else
        [ "$?" -eq 2 ] || sleep 10
    fi

    apply_state
done
