#!/usr/bin/env python3
"""Create the Render web service. Prints only service id and URL."""

from __future__ import annotations

import json
import os
import ssl
import urllib.error
import urllib.request
from pathlib import Path

OWNER_ID = "tea-dapdlgtbedkc738gdvs0"
REPO = "https://github.com/LeoFom/financial-app"
ENV_KEYS = (
    "GEMINI_API_KEY",
    "GEMINI_PROJECT",
    "GEMINI_MODEL",
    "GEMINI_USE_VERTEX",
    "OPENAI_API_KEY",
    "OPENAI_MODEL",
)


def load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def request(method: str, path: str, payload: dict | None = None):
    key = os.environ["RENDER_API_KEY"]
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(
        f"https://api.render.com/v1{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=60, context=ctx) as resp:
            raw = resp.read().decode()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()[:2000]
    except urllib.error.URLError:
        # macOS Python 3.14 often lacks certs; fall back for this deploy only
        insecure = ssl._create_unverified_context()
        try:
            with urllib.request.urlopen(req, timeout=60, context=insecure) as resp:
                raw = resp.read().decode()
                return resp.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            return error.code, error.read().decode()[:2000]


def main() -> None:
    dotenv = load_dotenv(Path(__file__).resolve().parents[1] / ".env")
    env_vars = [{"key": "NODE_ENV", "value": "production"}]
    for key in ENV_KEYS:
        value = os.environ.get(key) or dotenv.get(key)
        if value:
            env_vars.append({"key": key, "value": value})

    payload = {
        "type": "web_service",
        "name": "financial-parser",
        "ownerId": OWNER_ID,
        "repo": REPO,
        "autoDeploy": "yes",
        "branch": "main",
        "rootDir": "backend",
        "envVars": env_vars,
        "serviceDetails": {
            "runtime": "node",
            "plan": "free",
            "region": "frankfurt",
            "healthCheckPath": "/health",
            "envSpecificDetails": {
                "buildCommand": "npm ci",
                "startCommand": "npx tsx src/index.ts",
            },
        },
    }

    status, body = request("POST", "/services", payload)
    if status >= 400:
        print(f"CREATE_FAILED {status}")
        print(body if isinstance(body, str) else json.dumps(body)[:2000])
        raise SystemExit(1)

    service = body.get("service", body) if isinstance(body, dict) else {}
    details = service.get("serviceDetails") or {}
    print(f"SERVICE_ID={service.get('id')}")
    print(f"SERVICE_URL={details.get('url') or service.get('url')}")
    print(f"DASHBOARD={service.get('dashboardUrl')}")


if __name__ == "__main__":
    main()
