"""Gateway tests. Fake mode and provider request plans only; no live model calls."""

from __future__ import annotations

import json
import os
import threading
import unittest
import urllib.error
import urllib.request

from gateway.fake_backend import error_analysis, grade, similar, solve, summary_groups
from gateway.llm import coerce
from gateway.providers import PROVIDER_NAMES, build_provider
from gateway.providers.anthropic import AnthropicAdapter
from gateway.providers.deepseek import DeepSeekAdapter
from gateway.providers.openai_chat import OpenAIAdapter
from gateway.providers.tongyi import TongyiAdapter
from gateway.providers.zhipu import ZhipuAdapter
from gateway.server import Settings, make_server

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class FakeBackendTests(unittest.TestCase):
    def test_solve_matches_stub_arithmetic(self):
        body = solve(
            {
                "stem_text": "计算：1 + 1 = ?",
                "student_answer": "3",
                "subject": "数学",
                "grade": "七年级",
                "teacher_key_filename": "答案.docx",
            }
        )
        self.assertEqual(body["text"], "2")
        self.assertEqual(body["question_type"], "计算题")
        self.assertGreaterEqual(body["confidence"], 0.85)
        self.assertEqual(body["source_refs"], ["teacher-key:答案.docx"])

    def test_grade_empty_stays_pending_and_mismatch_is_objective(self):
        pending = grade(
            {
                "student_answer": " ",
                "canonical_text": "2",
                "question_type": "计算题",
                "canonical_confidence": 0.93,
            }
        )
        self.assertEqual(pending["result"], "pending")
        wrong = grade(
            {
                "student_answer": "3",
                "canonical_text": "2",
                "question_type": "计算题",
                "canonical_confidence": 0.93,
            }
        )
        self.assertEqual(wrong["result"], "wrong")
        self.assertEqual(wrong["suggested_authority"], "auto_objective")

    def test_summary_groups_counts(self):
        body = summary_groups(
            {
                "subject": "数学",
                "grade": "七年级",
                "questions": [
                    {"question_type": "计算题", "result": "wrong", "stem_text": "1"},
                    {"question_type": "计算题", "result": "pending", "stem_text": "2"},
                ],
            }
        )
        self.assertEqual(len(body["groups"]), 1)
        group = body["groups"][0]
        self.assertEqual(group["wrong_count"], 1)
        self.assertEqual(group["pending_count"], 1)
        self.assertEqual(group["correct_count"], 0)

    def test_error_tags_and_similar_variants(self):
        analysis = error_analysis(
            {
                "student_answer": "3",
                "canonical_text": "2",
                "question_type": "计算题",
                "subject": "数学",
            }
        )
        self.assertEqual(analysis["tags"], ["计算错误"])
        body = similar(
            {
                "stem_text": "计算：1 + 1 = ?",
                "canonical_text": "2",
                "question_type": "计算题",
                "subject": "数学",
                "locale": "zh-Hans",
            }
        )
        self.assertGreaterEqual(len(body["items"]), 2)
        self.assertLessEqual(len(body["items"]), 3)
        self.assertTrue(all(item["source"] == "generated" for item in body["items"]))
        coerced = coerce(
            "similar",
            {
                "items": [
                    {"stem": "第一道", "answer": "1", "source": "library"},
                    {"stem": "第二道"},
                    {"stem": "第三道"},
                    {"stem": "第四道"},
                ]
            },
        )
        self.assertEqual(len(coerced["items"]), 3)
        self.assertEqual(coerced["items"][0]["source"], "generated")
        self.assertEqual(coerced["items"][0]["answer"], "1")
        self.assertNotIn("answer", coerced["items"][1])

    def test_similar_coerce_rejects_a_single_item(self):
        from gateway.llm import GatewayError

        with self.assertRaises(GatewayError):
            coerce("similar", {"items": [{"stem": "只有一道"}]})


class ProviderPlanTests(unittest.TestCase):
    def test_registry_lists_vendors_and_rejects_cursor(self):
        self.assertEqual(
            PROVIDER_NAMES,
            ("fake", "openai", "anthropic", "tongyi", "zhipu", "deepseek"),
        )
        self.assertEqual(build_provider("fake").name, "fake")
        with self.assertRaises(ValueError):
            build_provider("cursor")
        with self.assertRaises(ValueError):
            build_provider("openai", api_key="")

    def test_each_vendor_has_its_own_endpoint(self):
        key = "secret-token"
        plans = {
            "openai": OpenAIAdapter("", "", key).plan("sys", "user"),
            "anthropic": AnthropicAdapter("", "", key).plan("sys", "user"),
            "tongyi": TongyiAdapter("", "", key).plan("sys", "user"),
            "zhipu": ZhipuAdapter("", "", key).plan("sys", "user"),
            "deepseek": DeepSeekAdapter("", "", key).plan("sys", "user"),
        }
        self.assertEqual(plans["openai"].url, "https://api.openai.com/v1/chat/completions")
        self.assertEqual(plans["anthropic"].url, "https://api.anthropic.com/v1/messages")
        self.assertNotIn("chat/completions", plans["anthropic"].url)
        self.assertIn("text-generation/generation", plans["tongyi"].url)
        self.assertEqual(plans["zhipu"].url, "https://open.bigmodel.cn/api/paas/v4/chat/completions")
        self.assertEqual(plans["deepseek"].url, "https://api.deepseek.com/chat/completions")
        self.assertEqual(plans["anthropic"].headers["x-api-key"], key)
        for name, planned in plans.items():
            self.assertNotIn(key, planned.url)
            self.assertNotIn("cursor", planned.url)
            if name != "anthropic":
                self.assertEqual(planned.headers["Authorization"], f"Bearer {key}")
        with self.assertRaises(ValueError):
            OpenAIAdapter("https://api.cursor.com/v1", "gpt-4o-mini", key).plan("sys", "user")

    def test_base_url_and_model_override_the_preset(self):
        planned = build_provider(
            "deepseek",
            base_url="https://llm.example.test/v1",
            model="deepseek-reasoner",
            api_key="secret-token",
        ).plan("sys", "user")
        self.assertEqual(planned.url, "https://llm.example.test/v1/chat/completions")
        self.assertEqual(planned.body["model"], "deepseek-reasoner")


class GatewayHTTPTests(unittest.TestCase):
    def test_fake_http_routes_and_guards(self):
        server = make_server(Settings(provider="fake", gateway_key="gate-token", port=0))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        port = server.server_address[1]
        try:
            health = self._request(port, "GET", "/health")
            self.assertEqual(health["provider"], "fake")
            self.assertNotIn("api_key", health)

            denied = self._status(port, "/v1/inference/solve", {"stem_text": "1+1"}, token="")
            self.assertEqual(denied, 401)

            solved = self._request(
                port,
                "POST",
                "/v1/inference/solve",
                {"stem_text": "1 + 1 = ?", "student_answer": "3"},
                token="gate-token",
            )
            self.assertEqual(solved["text"], "2")

            rejected = self._status(
                port,
                "/v1/inference/solve",
                {"stem_text": "1+1", "image_base64": "aaaa"},
                token="gate-token",
            )
            self.assertEqual(rejected, 400)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)

    def _request(self, port, method, path, payload=None, token=""):
        status, body = self._raw(port, method, path, payload, token)
        self.assertEqual(status, 200, body)
        return json.loads(body)

    def _status(self, port, path, payload, token):
        status, _body = self._raw(port, "POST", path, payload, token)
        return status

    def _raw(self, port, method, path, payload, token):
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}{path}",
            data=data,
            method=method,
        )
        request.add_header("Content-Type", "application/json")
        if token:
            request.add_header("Authorization", f"Bearer {token}")
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, response.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            return exc.code, exc.read().decode("utf-8")


class SecretFileTests(unittest.TestCase):
    def test_tracked_config_does_not_contain_a_provider_key(self):
        for relative in ("Config/Secrets.xcconfig", "Config/Inference.xcconfig", "gateway/.env.example"):
            with open(os.path.join(ROOT, relative), encoding="utf-8") as handle:
                text = handle.read()
            self.assertNotIn("sk-", text)
            for line in text.splitlines():
                stripped = line.strip()
                if stripped.startswith("INFERENCE_API_KEY") or stripped.startswith("GATEWAY_API_KEY"):
                    self.assertTrue(stripped.endswith("=") or stripped.endswith("= "), stripped)


if __name__ == "__main__":
    unittest.main()
