#!/usr/bin/env python3
"""Send one literal safe console line. Never sends terminal control interrupts."""
import argparse
import subprocess

def send(session, command):
    if not command or any(ord(c) < 32 or ord(c) == 127 for c in command):
        raise ValueError("Command must be one printable line")
    subprocess.run(["screen", "-S", session, "-p", "0", "-X", "stuff", command + "\r"], check=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command")
    parser.add_argument("--session", default="tf2")
    args = parser.parse_args()
    send(args.session, args.command)
