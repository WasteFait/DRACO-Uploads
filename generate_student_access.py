#!/usr/bin/env python3
"""Create unique per-student Havoc credentials and a Mythic import worksheet."""
import argparse, csv, pathlib, re, secrets, string

ALPHABET = string.ascii_letters + string.digits + "!@#%_-"

def password(length=24):
    while True:
        value = "".join(secrets.choice(ALPHABET) for _ in range(length))
        if any(c.islower() for c in value) and any(c.isupper() for c in value) and any(c.isdigit() for c in value):
            return value

def username(value):
    result = re.sub(r"[^a-z0-9._-]+", "-", value.strip().lower()).strip("-.")
    if len(result) < 2:
        raise ValueError(f"invalid student identifier: {value!r}")
    return "student-" + result[:32]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("students", nargs="+", help="student IDs or roster names")
    p.add_argument("--output-dir", default="student-access")
    a=p.parse_args(); out=pathlib.Path(a.output_dir); out.mkdir(parents=True, exist_ok=True)
    rows=[]; seen=set()
    for item in a.students:
        user=username(item)
        if user in seen: raise SystemExit(f"duplicate normalized username: {user}")
        seen.add(user); rows.append({"student_id":item,"username":user,
            "havoc_password":password(),"mythic_password":password()})
    with (out/"student-credentials.csv").open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=rows[0]); w.writeheader(); w.writerows(rows)
    operators = "Operators {\n"+"".join(
        f'    user "{r["username"]}" {{\n        Password = "{r["havoc_password"]}"\n    }}\n\n' for r in rows)+"}\n"
    (out/"havoc-operators.yaotl").write_text(operators,encoding="utf-8")
    (out/"deimustech-lab.yaotl").write_text(
        'Teamserver {\n    Host = "172.16.113.66"\n    Port = 40056\n\n'
        '    Build {\n        Compiler64 = "data/x86_64-w64-mingw32-cross/bin/x86_64-w64-mingw32-gcc"\n'
        '        Compiler86 = "data/i686-w64-mingw32-cross/bin/i686-w64-mingw32-gcc"\n'
        '        Nasm = "/usr/bin/nasm"\n    }\n}\n\n' + operators +
        '\nDemon {\n    Sleep = 5\n    Jitter = 20\n    TrustXForwardedFor = false\n\n'
        '    Injection {\n        Spawn64 = "C:\\\\Windows\\\\System32\\\\notepad.exe"\n'
        '        Spawn32 = "C:\\\\Windows\\\\SysWOW64\\\\notepad.exe"\n    }\n}\n', encoding="utf-8")
    with (out/"mythic-operator-import.csv").open("w",newline="",encoding="utf-8") as f:
        w=csv.DictWriter(f,fieldnames=("username","password")); w.writeheader()
        w.writerows({"username":r["username"],"password":r["mythic_password"]} for r in rows)
    (out/"README.txt").write_text(
        "Protect student-credentials.csv as a secret. Copy deimustech-lab.yaotl into /opt/deimustech/Havoc/profiles/.\n"
        "Create the matching Mythic users as an administrator from the Settings interface or an approved Mythic scripting client.\n"
        "Distribute only one row to each student and delete distribution copies after first-login rotation.\n",encoding="utf-8")
    for path in out.iterdir(): path.chmod(0o600)
    print(f"Generated {len(rows)} unique account pairs in {out}")

if __name__ == "__main__": main()
