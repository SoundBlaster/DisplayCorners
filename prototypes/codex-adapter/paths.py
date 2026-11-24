"""Stable short socket paths for macOS Unix-domain socket limits."""
import hashlib
import os
from pathlib import Path


def socket_directory(data_directory):
    identity = str(Path(data_directory).expanduser().resolve()).encode()
    suffix = hashlib.sha256(identity).hexdigest()[:16]
    return Path('/tmp') / f'dc-{os.getuid()}-{suffix}'
