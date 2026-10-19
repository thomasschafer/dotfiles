"""Interactive one-off: authorise the backup's Todoist app for read-only access and store
the credentials in the Keychain. Nothing secret is printed."""

from __future__ import annotations

import getpass
import http.server
import secrets
import socket
import subprocess
import threading
import time
import urllib.parse

from . import api
from .auth import Credentials, KeychainTokenSource, credentials_from_token_response
from .config import OAUTH_REDIRECT_PORT, OAUTH_REDIRECT_URI, OAUTH_SCOPE

AUTHORIZE_URL = "https://app.todoist.com/oauth/authorize"
WAIT_SECONDS = 300


class SetupError(Exception):
    pass


class _IPv6Server(http.server.HTTPServer):
    address_family = socket.AF_INET6


def _wait_for_code(state: str) -> str:
    result: dict[str, str] = {}
    done = threading.Event()

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self) -> None:  # noqa: N802 - stdlib naming
            url = urllib.parse.urlsplit(self.path)
            if url.path != "/callback":
                self.send_error(404)
                return
            params = dict(urllib.parse.parse_qsl(url.query))
            if params.get("state") != state:
                result["error"] = "state mismatch: the redirect didn't come from this setup"
            elif "error" in params:
                result["error"] = f"Todoist returned {params['error']}"
            elif not params.get("code"):
                result["error"] = "no code in the redirect"
            else:
                result["code"] = params["code"]
            body = (
                "Authorised. You can close this tab."
                if "code" in result
                else "Authorisation failed; see the terminal."
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
            done.set()

        def log_message(self, format: str, *args: object) -> None:
            pass  # the default logs the URL, which contains the code

    # Browsers may resolve localhost to either loopback address, so listen on both.
    servers = [http.server.HTTPServer(("127.0.0.1", OAUTH_REDIRECT_PORT), Handler)]
    try:
        servers.append(_IPv6Server(("::1", OAUTH_REDIRECT_PORT), Handler))
    except OSError:
        pass
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        if not done.wait(WAIT_SECONDS):
            raise SetupError("timed out waiting for the Todoist redirect")
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
    if "error" in result:
        raise SetupError(result["error"])
    return result["code"]


def setup_token(
    tokens: KeychainTokenSource, transport: api.Transport = api.urllib_transport
) -> None:
    print("Authorising todoist-backup for read-only access (scope data:read).")
    print(f"The Todoist app's OAuth redirect URL must be {OAUTH_REDIRECT_URI}\n")
    client_id = input("Client ID: ").strip()
    client_secret = getpass.getpass("Client secret (hidden): ").strip()
    if not client_id or not client_secret:
        raise SetupError("client ID and secret are both required")

    state = secrets.token_urlsafe(32)
    url = (
        AUTHORIZE_URL
        + "?"
        + urllib.parse.urlencode(
            {
                "client_id": client_id,
                "scope": OAUTH_SCOPE,
                "state": state,
                "response_type": "code",
                "redirect_uri": OAUTH_REDIRECT_URI,
            }
        )
    )
    print("\nOpening your browser to approve access. If it doesn't open, visit:\n" + url + "\n")
    subprocess.run(["/usr/bin/open", url], check=False)
    code = _wait_for_code(state)

    response = api.send(
        transport,
        "POST",
        api.OAUTH_TOKEN_PATH,
        form={
            "grant_type": "authorization_code",
            "client_id": client_id,
            "client_secret": client_secret,
            "code": code,
            "redirect_uri": OAUTH_REDIRECT_URI,
        },
    )
    if not isinstance(response, dict) or "scope" not in response:
        raise SetupError(
            "Todoist didn't say which scope it granted, so read-only access is unconfirmed"
        )
    credentials: Credentials = credentials_from_token_response(
        response, client_id=client_id, client_secret=client_secret, now=time.time()
    )
    if credentials.expires_at is not None and credentials.refresh_token is None:
        raise SetupError("Todoist issued an expiring token without a refresh token")
    tokens.store(credentials)

    user = api.send(transport, "GET", "/api/v1/user", bearer=credentials.access_token)
    print(f"Stored. Authorised as {user.get('full_name') or user.get('email') or 'unknown user'}.")
    if credentials.expires_at is None:
        print("Todoist issued a long-lived token.")
    else:
        print("Todoist issued a short-lived token and a refresh token; runs refresh it.")
