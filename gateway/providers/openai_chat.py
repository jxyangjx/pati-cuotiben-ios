"""OpenAI chat-completions wire. Other vendors subclass this only when they use the same shape."""

from __future__ import annotations

from gateway.providers.base import PlannedRequest, Provider, join_url, reject_cursor_host


class OpenAIChatAdapter(Provider):
    def __init__(self, name: str, base_url: str, model: str, api_key: str):
        self.name = name
        self.base_url = base_url
        self.model = model
        self.api_key = api_key

    def plan(self, system: str, user: str) -> PlannedRequest:
        url = join_url(self.base_url, "/chat/completions")
        reject_cursor_host(url)
        return PlannedRequest(
            url=url,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
                "User-Agent": "PaiTiCuoTiBen-Gateway/0.1",
            },
            body={
                "model": self.model,
                "temperature": 0,
                "max_tokens": 1200,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
            },
        )

    def parse(self, decoded: dict) -> str:
        choices = decoded.get("choices") or []
        if not choices:
            return ""
        message = choices[0].get("message") or {}
        content = message.get("content")
        if isinstance(content, list):
            parts = []
            for part in content:
                if isinstance(part, dict):
                    parts.append(part.get("text") or "")
                else:
                    parts.append(str(part))
            return "".join(parts)
        return content or ""


class OpenAIAdapter(OpenAIChatAdapter):
    def __init__(self, base_url: str, model: str, api_key: str):
        super().__init__(
            name="openai",
            base_url=base_url or "https://api.openai.com/v1",
            model=model or "gpt-4o-mini",
            api_key=api_key,
        )
