"""Thin homework-text gateway.

Run from the repo root:

    python3 -m gateway.server

Fake mode is the default and needs no model key. Choose a provider with
INFERENCE_PROVIDER, INFERENCE_BASE_URL, INFERENCE_MODEL, and INFERENCE_API_KEY.
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if __package__ in {None, ""}:
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from gateway import fake_backend
from gateway.llm import GatewayError, coerce, contains_forbidden, parse_json_object, system_prompt
from gateway.providers import build_provider
from gateway.providers.base import ProviderError

ROUTES = {
    "/v1/inference/solve": "solve",
    "/v1/inference/grade": "grade",
    "/v1/inference/error-analysis": "error-analysis",
    "/v1/inference/summary-groups": "summary-groups",
}
MAX_BODY = 256 * 1024


@dataclass
class Settings:
    provider: str = "fake"
    base_url: str = ""
    model: str = ""
    api_key: str = ""
    gateway_key: str = ""
    host: str = "127.0.0.1"
    port: int = 8787


def load_dotenv(path: str) -> None:
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            key, value = stripped.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def settings_from_env() -> Settings:
    here = os.path.dirname(os.path.abspath(__file__))
    load_dotenv(os.path.join(here, ".env"))
    provider = os.environ.get("INFERENCE_PROVIDER", "fake").strip().lower() or "fake"
    try:
        port = int(os.environ.get("PORT", "8787"))
    except ValueError:
        port = 8787
    return Settings(
        provider=provider,
        base_url=os.environ.get("INFERENCE_BASE_URL", "").strip(),
        model=os.environ.get("INFERENCE_MODEL", "").strip(),
        api_key=os.environ.get("INFERENCE_API_KEY", "").strip(),
        gateway_key=os.environ.get("GATEWAY_API_KEY", "").strip(),
        host=os.environ.get("GATEWAY_HOST", "127.0.0.1").strip() or "127.0.0.1",
        port=port,
    )


class GatewayApp:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.provider = build_provider(
            settings.provider,
            settings.base_url,
            settings.model,
            settings.api_key,
        )

    def health(self) -> dict:
        model = getattr(self.provider, "model", "") or ""
        return {
            "ok": True,
            "provider": self.provider.name,
            "model": model,
            "llm_key_configured": bool(self.settings.api_key),
        }

    def dispatch(self, kind: str, payload: dict) -> dict:
        if contains_forbidden(payload):
            raise GatewayError(400, "images_not_accepted")
        if self.provider.name == "fake":
            return fake_backend.handle(kind, payload)
        user = json.dumps(payload, ensure_ascii=False)
        try:
            text = self.provider.complete(system_prompt(kind), user)
        except ProviderError as exc:
            raise GatewayError(502, "provider_failed") from exc
        return coerce(kind, parse_json_object(text))


def make_handler(app: GatewayApp):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path != "/health":
                self._send(404, {"error": "not_found"})
                return
            self._send(200, app.health())

        def do_POST(self):
            path = self.path.split("?", 1)[0]
            kind = ROUTES.get(path)
            if kind is None:
                self._send(404, {"error": "not_found"})
                return
            if app.settings.gateway_key:
                header = self.headers.get("Authorization", "")
                if header != f"Bearer {app.settings.gateway_key}":
                    self._send(401, {"error": "unauthorized"})
                    return
            length = int(self.headers.get("Content-Length", "0") or "0")
            if length <= 0 or length > MAX_BODY:
                self._send(400, {"error": "invalid_body"})
                return
            raw = self.rfile.read(length)
            try:
                payload = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._send(400, {"error": "invalid_json"})
                return
            if not isinstance(payload, dict):
                self._send(400, {"error": "invalid_json"})
                return
            try:
                body = app.dispatch(kind, payload)
            except GatewayError as exc:
                self._send(exc.status, {"error": exc.code})
                return
            except Exception:
                self._send(500, {"error": "gateway_failed"})
                return
            self._send(200, body)

        def log_message(self, fmt, *args):
            sys.stderr.write("%s %s\n" % (self.command, self.path.split("?", 1)[0]))

        def _send(self, status: int, body: dict) -> None:
            encoded = json.dumps(body, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(encoded)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(encoded)

    return Handler


def make_server(settings: Settings) -> ThreadingHTTPServer:
    app = GatewayApp(settings)
    return ThreadingHTTPServer((settings.host, settings.port), make_handler(app))


def main() -> None:
    settings = settings_from_env()
    try:
        server = make_server(settings)
    except ValueError as exc:
        sys.stderr.write(str(exc) + "\n")
        sys.exit(1)
    sys.stderr.write(
        "inference gateway provider=%s model=%s host=%s port=%s llm_key=%s\n"
        % (
            settings.provider,
            settings.model or "(preset)",
            settings.host,
            server.server_address[1],
            "set" if settings.api_key else "empty",
        )
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
