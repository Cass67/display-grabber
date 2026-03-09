"""Command-line interface for display-grabber."""

from __future__ import annotations

import argparse
import sys

from display_grabber.displays import apply_config, get_online_displays


def cmd_list() -> None:
    displays = get_online_displays()
    print(f"Connected displays ({len(displays)} total):")
    for d in displays:
        print(f"  {d}")


def cmd_auto(*, dry_run: bool = False) -> None:
    displays = get_online_displays()
    print(f"Connected displays ({len(displays)} total):")
    for d in displays:
        print(f"  {d}")

    live = [d for d in displays if d.is_active and not d.is_asleep]

    if not live:
        sys.exit(
            "\nNo active displays detected. Are all monitors asleep or on another input?\n"
            "Try --list to inspect state, or --main <id> to force a specific display."
        )

    if len(live) == 1:
        main = live[0]
        others = [d.id for d in displays if d.id != main.id]
        name = f" ({main.name})" if main.name else ""
        print(f"\nDetected 1 live display: [{main.id}] {main.width}x{main.height}{name}")
        if not others:
            print("No other displays to mirror — nothing to do.")
            return
        print(f"Will mirror {len(others)} display(s) to it.")
        if dry_run:
            print("(dry run — no changes made)")
            return
        if not apply_config(main.id, others):
            sys.exit(1)
        print("Done.")
    else:
        print(f"\nMultiple live displays found ({len(live)}):")
        for i, d in enumerate(live):
            print(f"  [{i}]  {d}")
        print("\nCannot auto-detect which to use as main.")
        print(f"Run with --main <id> to specify. Example:\n  display-grabber --main {live[0].id}")
        sys.exit(1)


def cmd_set_main(raw_id: str) -> None:
    try:
        main_id = int(raw_id)
    except ValueError:
        sys.exit(f"Error: '{raw_id}' is not a valid display ID")
    displays = get_online_displays()
    if not any(d.id == main_id for d in displays):
        sys.exit(f"Error: Display {main_id} not found. Run --list to see available displays.")
    others = [d.id for d in displays if d.id != main_id]
    print(f"Setting display {main_id} as main, mirroring {len(others)} other(s)...")
    if not apply_config(main_id, others):
        sys.exit(1)
    print("Done.")


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="display-grabber",
        description="Set the active Mac display as main and mirror the rest.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
detection:
  A display is "live" if CGDisplayIsActive is true and it is not asleep.
  When a monitor switches its input to another device, macOS marks it inactive.
  If auto-detection fails for your setup, use --main <id> (find IDs with --list).

examples:
  display-grabber                 auto mode (default)
  display-grabber --list          show all displays and their IDs
  display-grabber --main 2        force display 2 as main, mirror the rest
  display-grabber --dry-run       preview without applying changes
""",
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--list", action="store_true", help="List all connected displays")
    group.add_argument("--main", metavar="ID", help="Set display <ID> as main, mirror all others")
    group.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would happen without applying changes",
    )
    return parser


def main() -> None:
    args = _build_parser().parse_args()
    if args.list:
        cmd_list()
    elif args.main:
        cmd_set_main(args.main)
    elif args.dry_run:
        cmd_auto(dry_run=True)
    else:
        cmd_auto()


if __name__ == "__main__":
    main()
