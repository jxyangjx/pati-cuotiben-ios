"""DeepSeek. Its public API is chat-completions on api.deepseek.com, selected here by name."""

from __future__ import annotations

from gateway.providers.openai_chat import OpenAIChatAdapter


class DeepSeekAdapter(OpenAIChatAdapter):
    def __init__(self, base_url: str, model: str, api_key: str):
        super().__init__(
            name="deepseek",
            base_url=base_url or "https://api.deepseek.com",
            model=model or "deepseek-chat",
            api_key=api_key,
        )
