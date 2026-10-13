"""Zhipu GLM. The BigModel endpoint uses a chat-completions body with its own base URL."""

from __future__ import annotations

from gateway.providers.openai_chat import OpenAIChatAdapter


class ZhipuAdapter(OpenAIChatAdapter):
    def __init__(self, base_url: str, model: str, api_key: str):
        super().__init__(
            name="zhipu",
            base_url=base_url or "https://open.bigmodel.cn/api/paas/v4",
            model=model or "glm-4-flash",
            api_key=api_key,
        )
