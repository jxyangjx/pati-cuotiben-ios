"""Tongyi Qianwen through the DashScope native generation API."""

from __future__ import annotations

from gateway.providers.base import PlannedRequest, Provider, join_url, reject_cursor_host


class TongyiAdapter(Provider):
    def __init__(self, base_url: str, model: str, api_key: str):
        self.name = "tongyi"
        self.base_url = base_url or "https://dashscope.aliyuncs.com/api/v1"
        self.model = model or "qwen-plus"
        self.api_key = api_key

    def plan(self, system: str, user: str) -> PlannedRequest:
        url = join_url(self.base_url, "/services/aigc/text-generation/generation")
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
                "input": {
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": user},
                    ]
                },
                "parameters": {"result_format": "message", "temperature": 0},
            },
        )

    def parse(self, decoded: dict) -> str:
        output = decoded.get("output") or {}
        choices = output.get("choices") or []
        if choices:
            message = choices[0].get("message") or {}
            return message.get("content") or ""
        return output.get("text") or ""
