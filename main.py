"""
KRM Weigh Scale Integration
Polls a weight-scale API at a configurable interval and logs non-idle
weight readings (with timestamp) to a text file.

Intended to be run as a Windows service via NSSM or invoked periodically
by any scheduler.  All settings live in config.ini.
"""

import configparser
import logging
import os
import sys
import time
from datetime import datetime

import requests

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

CONFIG_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.ini")

# The "idle / no-load" weight value returned by the scale when nothing is
# on the pan.  Readings that match this value are silently ignored.
IDLE_WEIGHT = "\x021      00    00"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load_config(path: str) -> configparser.ConfigParser:
    config = configparser.ConfigParser()
    if not config.read(path):
        print(f"ERROR: Configuration file not found: {path}", file=sys.stderr)
        sys.exit(1)
    return config


def setup_logger(log_file: str) -> logging.Logger:
    logger = logging.getLogger("weight_logger")
    logger.setLevel(logging.INFO)

    # Avoid adding duplicate handlers when the module is reloaded
    if logger.handlers:
        return logger

    formatter = logging.Formatter("%(asctime)s  %(message)s", datefmt="%Y-%m-%d %H:%M:%S")

    # File handler – append so previous runs are preserved
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setFormatter(formatter)
    logger.addHandler(fh)

    # Console handler – useful when running interactively / debugging
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    return logger


def fetch_weight(api_url: str, timeout: int) -> dict | None:
    """Call the API and return the parsed JSON body, or None on failure."""
    try:
        response = requests.get(api_url, timeout=timeout)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.ConnectionError:
        print(f"WARNING: Could not connect to {api_url}", file=sys.stderr)
    except requests.exceptions.Timeout:
        print(f"WARNING: Request to {api_url} timed out", file=sys.stderr)
    except requests.exceptions.HTTPError as exc:
        print(f"WARNING: HTTP error from {api_url}: {exc}", file=sys.stderr)
    except ValueError:
        print("WARNING: Response was not valid JSON", file=sys.stderr)
    return None


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def run():
    config = load_config(CONFIG_FILE)

    api_url = config.get("settings", "api_url").strip()
    poll_interval = config.getint("settings", "poll_interval_seconds")
    log_file = config.get("settings", "log_file").strip()
    request_timeout = config.getint("settings", "request_timeout_seconds")

    # Resolve a relative log-file path to the directory containing this script
    if not os.path.isabs(log_file):
        log_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), log_file)

    logger = setup_logger(log_file)
    logger.info("=== KRM Weigh Scale Integration started ===")
    logger.info("API URL       : %s", api_url)
    logger.info("Poll interval : %d seconds", poll_interval)
    logger.info("Log file      : %s", log_file)

    while True:
        data = fetch_weight(api_url, request_timeout)

        if data is not None:
            if not data.get("success"):
                print("WARNING: API returned success=false", file=sys.stderr)
            else:
                weight = data.get("weight", "")
                if weight != IDLE_WEIGHT:
                    logger.info("Weight: %s", weight)

        time.sleep(poll_interval)


if __name__ == "__main__":
    run()
