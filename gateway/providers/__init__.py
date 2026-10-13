"""Provider registry.

The Cursor API is not a chat-completions backend and is not selectable here.
"""

from __future__ import annotations

from gateway.providers.anthropic import AnthropicAdapter
from gateway.providers.base import Provider
from gateway.providers.deepseek import DeepSeekAdapter
from gateway.providers.openai_chat import OpenAIAdapter
from gateway.providers.tongyi import TongyiAdapter
from gateway.providers.zhipu import ZhipuAdapter

PROVIDER_NAMES = ("fake", "openai", "anthropic", "tongyi", "zhipu", "deepseek")


class FakeProvider(Provider):
    name = "fake"

    def plan(self, system: str, user: str):
        raise RuntimeError("fake provider does not call a model")

    def complete(self, system: str, user: str) -> str:
        raise RuntimeError("fake provider does not call a model")


def build_provider(name: str, base_url: str = "", model: str = "", api_key: str = "") -> Provider:
    key = (name or "").strip().lower()
    if not key:
        key = "fake"
    if "cursor" in key:
        raise ValueError("Cursor API is not an inference provider")
    if key not in PROVIDER_NAMES:
        known = ", ".join(PROVIDER_NAMES)
        raise ValueError(f"Unknown provider '{key}'. Choose one of: {known}")
    if key == "fake":
        return FakeProvider()
    if key != "fake" and not api_key:
        raise ValueError(f"INFERENCE_API_KEY is required for provider {key}")
    if key == "openai":
        return OpenAIAdapter(base_url, model, api_key)
    if key == "anthropic":
        return AnthropicAdapter(base_url, model, api_key)
    if key == "tongyi":
        return TongyiAdapter(base_url, model, api_key)
    if key == "zhipu":
        return ZhipuAdapter(base_url, model, api_key)
    if key == "deepseek":
        return DeepSeekAdapter(base_url, model, api_key)
    raise ValueError(f"Unknown provider '{key}'")
