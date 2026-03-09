"""CoreGraphics display detection and configuration."""

from __future__ import annotations

import json
import subprocess  # noqa: S404
import sys
from dataclasses import dataclass, field

import Quartz

_SYSTEM_PROFILER = "/usr/sbin/system_profiler"
_MAX_DISPLAYS = 32


@dataclass
class DisplayInfo:
    id: int
    width: int
    height: int
    is_main: bool
    is_active: bool
    is_asleep: bool
    is_mirrored: bool
    origin_x: float
    origin_y: float
    name: str = field(default="")

    def __str__(self) -> str:
        flags = []
        if self.is_main:
            flags.append("MAIN")
        if not self.is_active:
            flags.append("inactive")
        if self.is_asleep:
            flags.append("asleep")
        if self.is_mirrored:
            flags.append("mirrored")
        flag_str = ", ".join(flags) if flags else "active"
        ox, oy = int(self.origin_x), int(self.origin_y)
        label = f"  {self.name}" if self.name else ""
        return f"[{self.id}] {self.width}x{self.height} @ ({ox},{oy})  [{flag_str}]{label}"


def _get_display_names() -> dict[int, str]:
    """Return a mapping of CGDisplay ID → monitor model name via system_profiler."""
    try:
        result = subprocess.run(  # noqa: S603
            [_SYSTEM_PROFILER, "SPDisplaysDataType", "-json"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        data: dict[str, list[dict[str, object]]] = json.loads(result.stdout)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return {}

    names: dict[int, str] = {}
    for gpu in data.get("SPDisplaysDataType", []):
        for monitor in gpu.get("spdisplays_ndrvs", []):  # type: ignore[union-attr]
            raw_id = monitor.get("_spdisplays_displayID")
            name = monitor.get("_name", "")
            if raw_id and name:
                try:
                    names[int(str(raw_id))] = str(name)
                except ValueError:
                    pass
    return names


def get_online_displays() -> list[DisplayInfo]:
    """Return all displays currently known to the OS."""
    err, display_ids, count = Quartz.CGGetOnlineDisplayList(_MAX_DISPLAYS, None, None)
    if err != 0:
        sys.exit(f"Error: CGGetOnlineDisplayList failed (code {err})")
    names = _get_display_names()
    displays = []
    for did in display_ids[:count]:
        bounds = Quartz.CGDisplayBounds(did)
        displays.append(
            DisplayInfo(
                id=did,
                width=Quartz.CGDisplayPixelsWide(did),
                height=Quartz.CGDisplayPixelsHigh(did),
                is_main=bool(Quartz.CGDisplayIsMain(did)),
                is_active=bool(Quartz.CGDisplayIsActive(did)),
                is_asleep=bool(Quartz.CGDisplayIsAsleep(did)),
                is_mirrored=bool(Quartz.CGDisplayIsInMirrorSet(did)),
                origin_x=bounds.origin.x,
                origin_y=bounds.origin.y,
                name=names.get(did, ""),
            )
        )
    return displays


def apply_config(main_id: int, mirror_ids: list[int]) -> bool:
    """Set main_id as the primary display and mirror all mirror_ids to it."""
    err, cfg = Quartz.CGBeginDisplayConfiguration(None)
    if err != 0 or cfg is None:
        print(f"Error: CGBeginDisplayConfiguration failed (code {err})", file=sys.stderr)
        return False

    # Remove any existing mirroring before reconfiguring
    for did in mirror_ids:
        Quartz.CGConfigureDisplayMirrorOfDisplay(cfg, did, Quartz.kCGNullDirectDisplay)

    # Placing the display at (0, 0) makes it the menu-bar display
    Quartz.CGConfigureDisplayOrigin(cfg, main_id, 0, 0)

    for did in mirror_ids:
        Quartz.CGConfigureDisplayMirrorOfDisplay(cfg, did, main_id)

    err = Quartz.CGCompleteDisplayConfiguration(cfg, Quartz.kCGConfigureForSession)
    if err != 0:
        Quartz.CGCancelDisplayConfiguration(cfg)
        print(f"Error: CGCompleteDisplayConfiguration failed (code {err})", file=sys.stderr)
        return False
    return True
