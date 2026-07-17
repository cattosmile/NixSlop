"""Version fetching from various sources (GitHub, npm, custom APIs)."""

import re
from typing import cast

from .http import fetch_json, fetch_text
from .nix import NixCommandError, run_command


def fetch_github_latest_release(owner: str, repo: str) -> str:
    """Fetch the latest release version from GitHub.

    Args:
        owner: Repository owner
        repo: Repository name

    Returns:
        Latest release version (without 'v' prefix)

    """
    url = f"https://api.github.com/repos/{owner}/{repo}/releases/latest"
    data = fetch_json(url)
    if not isinstance(data, dict):
        msg = f"Expected dict from GitHub API, got {type(data)}"
        raise TypeError(msg)
    tag = cast("str", data["tag_name"])

    # Strip 'v' prefix if present (also handled in parse_version for defensive comparison)
    return tag.lstrip("v")


def fetch_npm_version(package: str) -> str:
    """Fetch the latest version from npm registry.

    Args:
        package: npm package name

    Returns:
        Latest version

    """
    # Try using npm command first
    try:
        cmd = ["npm", "view", package, "version"]
        result = run_command(cmd)
        return result.stdout.strip()
    except (FileNotFoundError, NixCommandError, OSError):
        # npm is unavailable or failed; fall back to the registry API.
        url = f"https://registry.npmjs.org/{package}/latest"
        data = fetch_json(url)
        if not isinstance(data, dict):
            msg = f"Expected dict from npm registry, got {type(data)}"
            raise TypeError(msg) from None
        return cast("str", data["version"])


# Parse versions into numeric components for proper comparison
# Handle versions like "1.0.105", "0.61.0", "2025.11.06-8fe8a63", "v1.0.0"
def parse_version(v: str) -> tuple[list[int], list[str]]:
    """Parse numeric release components and prerelease identifiers."""
    # Strip 'v' prefix if present
    v = v.lstrip("v")

    # Build metadata does not affect version precedence.
    precedence = v.split("+", 1)[0]
    parts = precedence.split("-", 1)
    numeric_str = parts[0]
    prerelease = parts[1].split(".") if len(parts) > 1 else []

    # Parse numeric components
    try:
        numeric = [int(x) for x in numeric_str.split(".")]
    except ValueError:
        # Fallback to lexicographic if not numeric
        numeric = []

    return (numeric, prerelease)


def compare_versions(v1: str, v2: str) -> int:
    """Compare two semantic versions.

    Args:
        v1: First version
        v2: Second version

    Returns:
        -1 if v1 < v2, 0 if v1 == v2, 1 if v1 > v2

    """
    if v1 == v2:
        return 0

    v1_numeric, v1_prerelease = parse_version(v1)
    v2_numeric, v2_prerelease = parse_version(v2)

    # If parsing failed for either, fall back to lexicographic
    if not v1_numeric or not v2_numeric:
        return -1 if v1 < v2 else 1

    # Compare numeric components
    for i in range(max(len(v1_numeric), len(v2_numeric))):
        n1 = v1_numeric[i] if i < len(v1_numeric) else 0
        n2 = v2_numeric[i] if i < len(v2_numeric) else 0
        if n1 < n2:
            return -1
        if n1 > n2:
            return 1

    # A stable release sorts after a prerelease with the same numeric version.
    if v1_prerelease == v2_prerelease:
        return 0
    if not v1_prerelease:
        return 1
    if not v2_prerelease:
        return -1

    for identifier1, identifier2 in zip(v1_prerelease, v2_prerelease, strict=False):
        if identifier1 == identifier2:
            continue

        numeric1 = identifier1.isdigit()
        numeric2 = identifier2.isdigit()
        if numeric1 and numeric2:
            return -1 if int(identifier1) < int(identifier2) else 1
        if numeric1 != numeric2:
            return -1 if numeric1 else 1
        return -1 if identifier1 < identifier2 else 1

    return -1 if len(v1_prerelease) < len(v2_prerelease) else 1


def should_update(current: str, latest: str) -> bool:
    """Check if an update is needed.

    Args:
        current: Current version
        latest: Latest available version

    Returns:
        True if update is needed

    """
    return compare_versions(current, latest) < 0


def fetch_version_from_text(url: str, pattern: str) -> str:
    """Fetch text from URL and extract version using regex pattern.

    Args:
        url: URL to fetch text from
        pattern: Regex pattern with a capture group for the version

    Returns:
        Extracted version string

    Raises:
        ValueError: If version cannot be extracted

    """
    text = fetch_text(url)
    match = re.search(pattern, text)
    if not match:
        msg = f"Could not extract version from {url} using pattern {pattern}"
        raise ValueError(msg)
    return match.group(1)
