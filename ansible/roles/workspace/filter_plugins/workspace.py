"""workspace_path: map a git clone URL to its folder under ~/workspace."""

import posixpath
import re

from ansible.errors import AnsibleFilterError

# ssh://user@host:2222/path, https://host/path, git://host/path
_URL = re.compile(r"^(?:ssh|https?|git)://(?:[^@/]+@)?([^/:]+)(?::\d+)?/(.+)$")
# scp-like: user@host:path or host:path (no scheme)
_SCP = re.compile(r"^(?:[^@/:]+@)?([^:/]+):(.+)$")


def workspace_path(url, host_dirs=None):
    """github.com/<owner>/<repo>, or <host_dirs[host]>/<repo> for mapped hosts."""
    url = str(url).strip()
    match = _URL.match(url) or _SCP.match(url)
    if not match:
        raise AnsibleFilterError(f"workspace_path: cannot parse clone URL {url!r}")
    host, path = match.groups()
    path = path.strip("/")
    if path.endswith(".git"):
        path = path[: -len(".git")]
    parts = [p for p in path.split("/") if p]
    if not parts or any(p in (".", "..") for p in parts):
        raise AnsibleFilterError(f"workspace_path: unsafe path in {url!r}")
    mapped = (host_dirs or {}).get(host)
    if mapped:
        return posixpath.join(mapped, parts[-1])
    return posixpath.join(host, *parts)


class FilterModule:
    def filters(self):
        return {"workspace_path": workspace_path}
