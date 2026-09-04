#!/usr/bin/env python3
import argparse
import pathlib
import re
import subprocess
import time
import xml.etree.ElementTree as ET

BOUNDS = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
ROOM_CODE = re.compile(r"C[ÓO]DIGO\s*·\s*([A-Z0-9]{6})")


def adb(*args, capture=True):
    result = subprocess.run(
        ["adb", *args],
        check=True,
        text=capture,
        capture_output=capture,
    )
    return result.stdout if capture else ""


def nodes():
    adb("shell", "uiautomator", "dump", "/sdcard/window.xml")
    xml = adb("exec-out", "cat", "/sdcard/window.xml")
    return list(ET.fromstring(xml).iter("node"))


def center(bounds):
    match = BOUNDS.fullmatch(bounds or "")
    if not match:
        raise RuntimeError(f"invalid bounds: {bounds}")
    x1, y1, x2, y2 = map(int, match.groups())
    return (x1 + x2) // 2, (y1 + y2) // 2


def find_text(text, exact=False):
    for node in nodes():
        value = node.attrib.get("text", "")
        description = node.attrib.get("content-desc", "")
        if (value == text or description == text) if exact else (text in value or text in description):
            return node
    return None


def wait_text(text, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        node = find_text(text)
        if node is not None:
            return node
        time.sleep(0.4)
    raise RuntimeError(f"text not visible: {text}")


def tap_text(text, timeout=30, scroll=True):
    deadline = time.time() + timeout
    while time.time() < deadline:
        node = find_text(text)
        if node is not None:
            x, y = center(node.attrib.get("bounds"))
            adb("shell", "input", "tap", str(x), str(y))
            time.sleep(0.7)
            return
        if scroll:
            adb("shell", "input", "swipe", "540", "1550", "540", "650", "250")
            time.sleep(0.4)
        else:
            time.sleep(0.4)
    raise RuntimeError(f"unable to tap: {text}")


def room_code(timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        for node in nodes():
            for value in (node.attrib.get("text", ""), node.attrib.get("content-desc", "")):
                match = ROOM_CODE.search(value)
                if match:
                    return match.group(1)
        time.sleep(0.4)
    raise RuntimeError("authoritative room code not visible")


def screenshot(path):
    target = pathlib.Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("wb") as handle:
        subprocess.run(["adb", "exec-out", "screencap", "-p"], check=True, stdout=handle)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("room-code")
    tap = sub.add_parser("tap")
    tap.add_argument("text")
    wait = sub.add_parser("wait")
    wait.add_argument("text")
    shot = sub.add_parser("screenshot")
    shot.add_argument("path")
    args = parser.parse_args()

    if args.command == "room-code":
        print(room_code())
    elif args.command == "tap":
        tap_text(args.text)
    elif args.command == "wait":
        wait_text(args.text)
    elif args.command == "screenshot":
        screenshot(args.path)


if __name__ == "__main__":
    main()
