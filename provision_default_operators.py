#!/usr/bin/env python3
"""Provision operator-01..operator-99 in Havoc and Mythic."""
import json
import os
import pathlib
import ssl
import sys
import time
import urllib.error
import urllib.request
from typing import Dict, Optional, Tuple

TEAMSERVER = "172.16.113.66"
MYTHIC_PORT = 7443
DEFAULT_PASSWORD = "DeimusTech-Lab-Operator!"
DEFAULT_OPERATION = "DeimusTech Operations"
MYTHIC_DIR = pathlib.Path("/opt/deimustech/Mythic")
HAVOC_PROFILE = pathlib.Path("/opt/deimustech/Havoc/profiles/deimustech-lab.yaotl")
CREDENTIAL_SUMMARY = pathlib.Path("/etc/deimustech-c2/operator-accounts.txt")
USERS = [f"operator-{number:02d}" for number in range(1, 100)]


def read_env(path: pathlib.Path) -> Dict[str, str]:
    values = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip().upper()] = value.strip().strip('"').strip("'")
    return values


def request_json(url: str, payload: dict, headers: Optional[dict] = None) -> dict:
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", **(headers or {})},
        method="POST",
    )
    with urllib.request.urlopen(request, context=context, timeout=30) as response:
        return json.load(response)


def graphql(token: str, query: str, variables: Optional[dict] = None) -> dict:
    response = request_json(
        f"https://{TEAMSERVER}:{MYTHIC_PORT}/graphql/",
        {"query": query, "variables": variables or {}},
        {"Authorization": f"Bearer {token}"},
    )
    if response.get("errors"):
        raise RuntimeError(json.dumps(response["errors"], indent=2))
    return response["data"]


def wait_for_login(username: str, password: str) -> str:
    deadline = time.monotonic() + 300
    last_error = "Mythic has not answered yet"
    while time.monotonic() < deadline:
        try:
            response = request_json(
                f"https://{TEAMSERVER}:{MYTHIC_PORT}/auth",
                {"username": username, "password": password, "scripting_version": "0.2.8"},
            )
            if response.get("access_token"):
                return response["access_token"]
            last_error = response.get("error", "authentication returned no access token")
        except (OSError, urllib.error.URLError, json.JSONDecodeError) as error:
            last_error = str(error)
        time.sleep(5)
    raise RuntimeError(f"Mythic was not ready after five minutes: {last_error}")


def write_havoc_profile(password: str) -> None:
    operators = "\n".join(
        f'    user "{username}" {{\n        Password = "{password}"\n    }}\n'
        for username in USERS
    )
    profile = f'''Teamserver {{
    Host = "{TEAMSERVER}"
    Port = 40056

    Build {{
        Compiler64 = "data/x86_64-w64-mingw32-cross/bin/x86_64-w64-mingw32-gcc"
        Compiler86 = "data/i686-w64-mingw32-cross/bin/i686-w64-mingw32-gcc"
        Nasm = "/usr/bin/nasm"
    }}
}}

Operators {{
{operators}}}

Demon {{
    Sleep = 5
    Jitter = 20
    TrustXForwardedFor = false

    Injection {{
        Spawn64 = "C:\\\\Windows\\\\System32\\\\notepad.exe"
        Spawn32 = "C:\\\\Windows\\\\SysWOW64\\\\notepad.exe"
    }}
}}
'''
    HAVOC_PROFILE.parent.mkdir(parents=True, exist_ok=True)
    HAVOC_PROFILE.write_text(profile, encoding="utf-8")
    HAVOC_PROFILE.chmod(0o600)


def provision_mythic(password: str, env: Dict[str, str]) -> Tuple[int, int]:
    admin_user = env.get("MYTHIC_ADMIN_USER", "mythic_admin")
    admin_password = env.get("MYTHIC_ADMIN_PASSWORD")
    if not admin_password:
        raise RuntimeError("MYTHIC_ADMIN_PASSWORD is missing from Mythic/.env")
    operation = env.get("DEFAULT_OPERATION_NAME", DEFAULT_OPERATION)
    token = wait_for_login(admin_user, admin_password)

    existing_data = graphql(token, "query ExistingOperators { operator { id username } }")
    existing = {item["username"]: item["id"] for item in existing_data["operator"]}
    created = 0
    mutation = """
      mutation NewOperator($username: String!, $password: String!) {
        createOperator(input: {username: $username, password: $password, bot: false}) {
          status error id username
        }
      }
    """
    for username in USERS:
        if username in existing:
            continue
        result = graphql(token, mutation, {"username": username, "password": password})["createOperator"]
        if result.get("status") != "success":
            raise RuntimeError(f"Failed to create {username}: {result.get('error')}")
        existing[username] = result["id"]
        created += 1

    membership_query = """
      query Membership($name: String!) {
        operation(where: {name: {_eq: $name}}) {
          id operatoroperations { operator { username } }
        }
      }
    """
    operations = graphql(token, membership_query, {"name": operation})["operation"]
    if len(operations) != 1:
        raise RuntimeError(f"Expected one Mythic operation named {operation!r}; found {len(operations)}")
    current = {entry["operator"]["username"] for entry in operations[0]["operatoroperations"]}
    missing_ids = [existing[name] for name in USERS if name not in current]
    if missing_ids:
        add_mutation = """
          mutation AddOperators($operation_id: Int!, $add_users: [Int]) {
            updateOperatorOperation(operation_id: $operation_id, add_users: $add_users) {
              status error
            }
          }
        """
        result = graphql(token, add_mutation, {
            "operation_id": operations[0]["id"], "add_users": missing_ids
        })["updateOperatorOperation"]
        if result.get("status") != "success":
            raise RuntimeError(f"Failed to add Mythic operators to the operation: {result.get('error')}")
    return created, len(missing_ids)


def main() -> int:
    password = os.environ.get("DEIMUSTECH_OPERATOR_PASSWORD", DEFAULT_PASSWORD)
    if len(password) < 12:
        raise SystemExit("DEIMUSTECH_OPERATOR_PASSWORD must contain at least 12 characters")
    env_path = MYTHIC_DIR / ".env"
    if not env_path.exists():
        raise SystemExit(f"Missing Mythic configuration: {env_path}")

    write_havoc_profile(password)
    created, memberships = provision_mythic(password, read_env(env_path))
    CREDENTIAL_SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    CREDENTIAL_SUMMARY.write_text(
        "DeimusTech training operator accounts\n"
        "Users: operator-01 through operator-99\n"
        f"Initial password: {password}\n"
        "Change or rotate this shared initial password before any non-lab use.\n",
        encoding="utf-8",
    )
    CREDENTIAL_SUMMARY.chmod(0o600)
    print(f"Havoc profile provisioned with {len(USERS)} operators: {HAVOC_PROFILE}")
    print(f"Mythic created {created} accounts and added {memberships} operation memberships.")
    print(f"Credential summary: {CREDENTIAL_SUMMARY}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
