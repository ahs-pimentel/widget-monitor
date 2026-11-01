#!/usr/bin/env python3
"""Publica o AAB do oDois Monitor no canal de teste interno do Google Play.

Uso:
    scripts/publish-android.py [--track internal] [--dry-run]

Precisa de:
  - AAB assinado com a chave de upload: android/app/build/outputs/bundle/release/app-release.aab
    (gerado por `cd android && ./gradlew bundleRelease`);
  - chave JSON de uma conta de serviço com acesso ao app no Play Console, em
    ~/.config/odois-monitor/play-service-account.json (ou na variável PLAY_SERVICE_ACCOUNT).

Só usa a biblioteca padrão do Python e o `openssl` (assinatura RS256 do JWT).
Nunca imprime a chave nem o token de acesso.
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "me.o2d.odoismonitor"
AAB = ROOT / "android/app/build/outputs/bundle/release/app-release.aab"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def access_token(account: dict) -> str:
    """Troca um JWT assinado pela conta de serviço por um token OAuth (válido 1 h)."""
    now = int(time.time())
    header = b64url(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64url(json.dumps({
        "iss": account["client_email"], "scope": SCOPE, "aud": account["token_uri"],
        "iat": now, "exp": now + 3600,
    }).encode())
    signing_input = f"{header}.{claims}".encode()
    with tempfile.NamedTemporaryFile("w", delete=False) as key:
        os.chmod(key.name, 0o600)
        key.write(account["private_key"])
    try:
        signature = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", key.name], input=signing_input, capture_output=True, check=True
        ).stdout
    finally:
        os.unlink(key.name)
    body = urllib.parse.urlencode({
        "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
        "assertion": f"{signing_input.decode()}.{b64url(signature)}",
    }).encode()
    with urllib.request.urlopen(urllib.request.Request(account["token_uri"], data=body)) as resp:
        return json.load(resp)["access_token"]


def call(method: str, url: str, token: str, body=None, raw: bytes | None = None, content_type="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            text = resp.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            detail = json.loads(detail)["error"]["message"]
        except Exception:
            pass
        sys.exit(f"Play respondeu {e.code} em {method} {url.split('/applications/')[-1]}: {detail}")


def release_notes(version: str) -> str:
    """Notas em pt-BR: a seção da versão no CHANGELOG, sem Markdown, até 500 caracteres."""
    text = (ROOT / "CHANGELOG.md").read_text()
    match = re.search(rf"^## \[{re.escape(version)}\].*?$(.*?)(?=^## \[|\Z)", text, re.S | re.M)
    notes = match.group(1) if match else f"Versão {version}"
    notes = re.sub(r"[*`#]", "", notes)
    notes = "\n".join(line.strip() for line in notes.strip().splitlines() if line.strip())
    return notes[:497] + "…" if len(notes) > 500 else notes


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--track", default="internal", help="canal do Play (padrão: internal)")
    parser.add_argument("--dry-run", action="store_true", help="valida tudo e descarta a edição sem publicar")
    args = parser.parse_args()

    version = (ROOT / "VERSION").read_text().strip()
    if not AAB.exists():
        sys.exit(f"AAB não encontrado: {AAB}\nGere com: cd android && ./gradlew bundleRelease")
    key_path = Path(os.environ.get("PLAY_SERVICE_ACCOUNT", Path.home() / ".config/odois-monitor/play-service-account.json"))
    if not key_path.exists():
        sys.exit(f"Chave da conta de serviço não encontrada: {key_path}")
    account = json.loads(key_path.read_text())

    token = access_token(account)
    edit = call("POST", f"{API}/edits", token, {})["id"]
    print(f"edição aberta · versão {version} · canal {args.track}")

    bundle = call("POST", f"{UPLOAD}/edits/{edit}/bundles?uploadType=media", token,
                  raw=AAB.read_bytes(), content_type="application/octet-stream")
    code = bundle["versionCode"]
    print(f"AAB enviado · versionCode {code}")

    call("PUT", f"{API}/edits/{edit}/tracks/{args.track}", token, {
        "track": args.track,
        "releases": [{
            "name": version,
            "versionCodes": [str(code)],
            "status": "completed",
            "releaseNotes": [{"language": "pt-BR", "text": release_notes(version)}],
        }],
    })

    if args.dry_run:
        call("POST", f"{API}/edits/{edit}:validate", token)
        call("DELETE", f"{API}/edits/{edit}", token)
        print("validação ok · edição descartada (--dry-run)")
        return
    call("POST", f"{API}/edits/{edit}:commit", token)
    print(f"publicado no canal {args.track}: {version} ({code})")


if __name__ == "__main__":
    main()
