"""Shared request plan. Adapters fill in the vendor's own URL, headers, and body."""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass


class ProviderError(Exception):
    pass


@dataclass
class PlannedRequest:
    url: str
    headers: dict
    body: dict


class Provider:
    name = "provider"

    def plan(self, system: str, user: str) -> PlannedRequest:
        raise NotImplementedError

    def complete(self, system: str, user: str) -> str:
        planned = self.plan(system, user)
        payload = json.dumps(planned.body, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            planned.url,
            data=payload,
            headers=planned.headers,
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raise ProviderError(f"provider http {exc.code}") from None
        except urllib.error.URLError as exc:
            raise ProviderError("provider unreachable") from None
        try:
            decoded = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise ProviderError("provider returned non-json") from exc
        text = self.parse(decoded)
        if not str(text).strip():
            raise ProviderError("provider returned empty text")
        return text

    def parse(self, decoded: dict) -> str:
        raise NotImplementedError


def join_url(base: str, suffix: str) -> str:
    return base.rstrip("/") + "/" + suffix.lstrip("/")


def reject_cursor_host(url: str) -> None:
    host = urllib.parse.urlparse(url).hostname or ""
    lowered = host.lower()
    if "cursor.com" in lowered or "cursor.sh" in lowered or lowered == "cursor":
        raise ValueError("Cursor API is not an inference provider")
