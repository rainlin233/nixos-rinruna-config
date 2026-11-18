"""
Nyxuri wallpaper picker backend
Executes wallpaper switching for static images and live video wallpapers, synchronized with Noctalia & mpvpaper plugin state.
"""

import os
import sys
import json
import time
import subprocess

STATE_DIR = os.path.expanduser("~/.local/state/noctalia/mpvpaper")
ASSIGNMENTS_FILE = os.path.join(STATE_DIR, "assignments.json")
MPVPAPER_CACHE_DIR = os.path.expanduser("~/.cache/noctalia/mpvpaper")

# NixOS: nixpkgs wraps binaries (comm is ".mpvpaper-wrapp"), so pkill/pgrep -x
# never matches. Match by argv instead; [m] bracket avoids matching ourselves.
_MPVPAPER_PATTERN = "(^|/)[m]pvpaper( |$)"


def _mpvpaper_running() -> bool:
    """True when an mpvpaper instance is alive, i.e. a video wallpaper is on screen."""
    try:
        return subprocess.run(
            ["pgrep", "-f", _MPVPAPER_PATTERN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False
        ).returncode == 0
    except Exception:
        return False


def _clear_mpvpaper():
    """Cleanly terminate running mpvpaper instances and wait for process exit."""
    try:
        subprocess.run(["pkill", "-f", _MPVPAPER_PATTERN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        for _ in range(10):
            res = subprocess.run(["pgrep", "-f", _MPVPAPER_PATTERN], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
            if res.returncode != 0:
                break
            time.sleep(0.05)
    except Exception:
        pass


def _write_mpvpaper_assignments(assignments: dict):
    """Write mpvpaper assignments atomically to synchronize with Noctalia's mpvpaper service."""
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        tmp_file = f"{ASSIGNMENTS_FILE}.tmp.{os.getpid()}"
        data = {
            "assignments": assignments,
            "launchedAsSystemd": {k: False for k in assignments}
        }
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp_file, ASSIGNMENTS_FILE)
    except Exception as e:
        print(f"Warning: Failed to update mpvpaper assignments: {e}", file=sys.stderr)


def _static_frame_stamp() -> int:
    """Newest mtime (ns) among the plugin's extracted <connector>_static.jpg fallbacks."""
    stamp = 0
    try:
        for name in os.listdir(MPVPAPER_CACHE_DIR):
            if name.endswith("_static.jpg"):
                stamp = max(stamp, os.stat(os.path.join(MPVPAPER_CACHE_DIR, name)).st_mtime_ns)
    except OSError:
        pass
    return stamp


def _wait_static_frame(stamp: int, timeout: float = 3.0) -> bool:
    """Wait for the plugin's async clear-all frame extraction, then for its setWallpaper call."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(0.05)
        if _static_frame_stamp() != stamp:
            # ffmpeg just exited; the plugin calls setWallpaper in its completion callback.
            time.sleep(0.2)
            return True
    return False


def _set_wallpaper(path: str):
    subprocess.Popen(["noctalia", "msg", "wallpaper-set", path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def apply_static_wallpaper(path: str) -> bool:
    """Apply static wallpaper, clear mpvpaper video assignments, and restore host wallpaper rendering."""
    try:
        # clear-all makes the plugin extract the last video frame to __static.jpg and
        # setWallpaper() it a moment later, which would undo the pick. Remember how the
        # fallback cache looks right now, and whether a video is actually on screen.
        had_video = _mpvpaper_running()
        stamp = _static_frame_stamp() if had_video else 0

        # 1. Notify Noctalia's mpvpaper service to clear assignments and re-enable static wallpaper layer
        try:
            subprocess.run(
                ["noctalia", "msg", "plugin", "noctalia/mpvpaper:service", "all", "clear-all"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2, check=False
            )
        except Exception:
            pass

        # 2. Clear mpvpaper assignments file directly as fallback
        _write_mpvpaper_assignments({})

        # 3. Terminate any running mpvpaper instances with process wait
        _clear_mpvpaper()

        # 4. Apply through Noctalia so it can refresh the palette and wallpaper layer
        _set_wallpaper(path)

        # 5. Re-apply once the plugin's fallback frame has landed, so the pick wins.
        if had_video and _wait_static_frame(stamp):
            _set_wallpaper(path)
        return True
    except Exception as e:
        print(f"Error applying static wallpaper: {e}", file=sys.stderr)
        return False


def apply_dynamic_wallpaper(video_path: str, thumb_path: str = None) -> bool:
    """Apply dynamic video wallpaper via mpvpaper and synchronize Noctalia Material You palette."""
    try:
        # 1. Terminate existing mpvpaper instances and wait for exit
        _clear_mpvpaper()

        # 2. Update assignments so Noctalia's plugin and hooks recognize the active video
        _write_mpvpaper_assignments({"*": video_path})
        time.sleep(0.15)

        # 3. If thumbnail is available, set it as Noctalia wallpaper for instant theme sync
        if thumb_path and os.path.isfile(thumb_path):
            subprocess.run(["noctalia", "msg", "wallpaper-set", thumb_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

        # 4. Launch mpvpaper with isolated config, auto-pause, and Noctalia lua sync hook
        hook_script = os.path.expanduser("~/.config/noctalia/mpv-hook.lua")
        mpv_opts = "config=no load-scripts=no loop-file=inf panscan=1.0 no-audio hwdec=auto"
        if os.path.isfile(hook_script):
            mpv_opts += f" --script={hook_script}"

        cmd = ["mpvpaper", "--auto-pause", "-o", mpv_opts, "*", video_path]
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except Exception as e:
        print(f"Error applying live wallpaper: {e}", file=sys.stderr)
        return False


def apply_wallpaper(item) -> bool:
    """Polymorphic wallpaper application dispatcher."""
    if item.is_video:
        return apply_dynamic_wallpaper(item.path, item.thumb_path)
    else:
        return apply_static_wallpaper(item.path)
