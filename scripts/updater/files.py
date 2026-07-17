"""Small, dependency-free helpers for safe updater file writes."""

from __future__ import annotations

import os
import stat
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path


def _atomic_write(path: Path, data: bytes, mode: int) -> None:
    """Replace ``path`` atomically with ``data`` while preserving its mode."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
    )
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(descriptor, "wb") as temporary_file:
            temporary_file.write(data)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        temporary_path.chmod(mode)
        os.replace(temporary_path, path)
    except BaseException:
        temporary_path.unlink(missing_ok=True)
        raise


def atomic_write_text(path: Path, text: str) -> None:
    """Write UTF-8 text without exposing a partially written destination file."""
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
    _atomic_write(path, text.encode("utf-8"), mode)


@contextmanager
def file_transaction(*paths: Path) -> Iterator[None]:
    """Restore all listed files if the enclosed updater work fails."""
    snapshots = {
        path: (
            path.read_bytes(),
            stat.S_IMODE(path.stat().st_mode),
        )
        if path.exists()
        else None
        for path in paths
    }

    try:
        yield
    except BaseException:
        for path, snapshot in snapshots.items():
            if snapshot is None:
                path.unlink(missing_ok=True)
            else:
                contents, mode = snapshot
                _atomic_write(path, contents, mode)
        raise
