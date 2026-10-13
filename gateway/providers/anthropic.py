"""Anthropic Messages API. This is not the OpenAI chat-completions shape."""

from __future__ import annotations

from gateway.providers.base import PlannedRequest, Provider, join_url, reject_cursor_host


class AnthropicAdapter(Provider):
    def __init__(self, base_url: str, model: str, api_key: str):
        self.name = "anthropic"
        self.base_url = base_url or "https://api.anthropic.com"
        self.model = model or "claude-3-5-sonnet-latest"
        self.api_key = api_key

    def plan(self, system: str, user: str) -> PlannedRequest:
        url = join_url(self.base_url, "/v1/messages")
        reject_cursor_host(url)
        return PlannedRequest(
            url=url,
            headers={
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
                "User-Agent": "PaiTiCuoTiBen-Gateway/0.1",
            },
            body={
                "model": self.model,
                "max_tokens": 1200,
                "temperature": 0,
                "system": system,
                "messages": [{"role": "user", "content": user}],
            },
        )

    def parse(self, decoded: dict) -> str:
        blocks = decoded.get("content") or []
        parts = []
        for block in blocks:
            if isinstance(block, dict) and block.get("type", "text") == "text":
                parts.append(block.get("text") or "")
        return "".join(parts)
