#!/usr/bin/env python3
"""Mint a GitHub App installation token. Prints token to stdout.

Env: MIRROR_APP_ID, MIRROR_APP_PRIVATE_KEY, DEST_OWNER (org login).
Installation tokens last ~1 hour — remint before dest git push.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def jwt_rs256(app_id: str, pem: str) -> str:
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}, separators=(",", ":")).encode())
    now = int(time.time())
    payload = b64url(
        json.dumps(
            {"iat": now - 60, "exp": now + 540, "iss": int(app_id)},
            separators=(",", ":"),
        ).encode()
    )
    signing_input = f"{header}.{payload}".encode()
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as fh:
        fh.write(pem)
        if not pem.endswith("\n"):
            fh.write("\n")
        key_path = fh.name
    try:
        os.chmod(key_path, 0o600)
        sig = subprocess.check_output(
            ["openssl", "dgst", "-sha256", "-sign", key_path],
            input=signing_input,
        )
    finally:
        os.unlink(key_path)
    return f"{header}.{payload}.{b64url(sig)}"


def gh_app(url: str, token: str, method: str = "GET", body: bytes | None = None) -> dict:
    req = urllib.request.Request(
        url,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "ngpestelos-mirror-sync",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        err = e.read().decode()[:400]
        print(f"FAIL {method} {url} HTTP {e.code}: {err}", file=sys.stderr)
        raise SystemExit(1) from e


def main() -> int:
    app_id = os.environ.get("MIRROR_APP_ID", "").strip()
    pem = os.environ.get("MIRROR_APP_PRIVATE_KEY", "").replace("\\n", "\n").strip()
    owner = os.environ.get("DEST_OWNER", "ngpestelos-mirrors").strip()
    if not app_id or not pem:
        print("FAIL MIRROR_APP_ID or MIRROR_APP_PRIVATE_KEY empty", file=sys.stderr)
        return 1
    if "BEGIN" not in pem:
        print("FAIL private key missing BEGIN marker", file=sys.stderr)
        return 1
    jwt = jwt_rs256(app_id, pem)
    inst = gh_app(f"https://api.github.com/orgs/{owner}/installation", jwt)
    inst_id = inst.get("id")
    if not inst_id:
        print(f"FAIL no installation on org {owner}", file=sys.stderr)
        return 1
    tok = gh_app(
        f"https://api.github.com/app/installations/{inst_id}/access_tokens",
        jwt,
        method="POST",
        body=b"{}",
    )
    token = tok.get("token")
    if not token:
        print("FAIL installation token empty", file=sys.stderr)
        return 1
    sys.stdout.write(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
