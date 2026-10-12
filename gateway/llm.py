"""Turn a provider text completion into the gateway JSON contract."""

from __future__ import annotations

import json
import re

ALLOWED_AUTHORITY = {"user_confirm", "auto_canonical", "auto_objective", "none"}
ALLOWED_RESULT = {"correct", "wrong", "pending"}
FORBIDDEN_KEYS = {
    "image",
    "images",
    "image_base64",
    "image_url",
    "oss",
    "cos",
    "file_url",
    "page_image",
}


class GatewayError(Exception):
    def __init__(self, status: int, code: str):
        super().__init__(code)
        self.status = status
        self.code = code


def contains_forbidden(value) -> bool:
    if isinstance(value, dict):
        for key, item in value.items():
            if str(key).lower() in FORBIDDEN_KEYS or contains_forbidden(item):
                return True
        return False
    if isinstance(value, list):
        return any(contains_forbidden(item) for item in value)
    return False


def system_prompt(kind: str) -> str:
    schemas = {
        "solve": {
            "text": "最终答案",
            "steps": ["至少一条解题步骤"],
            "explanation": "简短讲解",
            "question_type": "计算题",
            "confidence": 0.9,
            "source_refs": [],
        },
        "grade": {
            "result": "correct | wrong | pending",
            "confidence": 0.9,
            "suggested_authority": "auto_objective | auto_canonical | none",
        },
        "error-analysis": {
            "points": ["1 到 3 条错因"],
            "avoidance_tips": ["避坑建议"],
        },
        "summary-groups": {
            "groups": [
                {
                    "question_type": "计算题",
                    "correct_count": 0,
                    "wrong_count": 0,
                    "pending_count": 0,
                    "bullets": ["这一类的中文总结"],
                }
            ]
        },
    }
    schema = json.dumps(schemas[kind], ensure_ascii=False)
    return (
        "你是作业批改助手。只返回一个 JSON 对象，不要使用 Markdown。"
        "讲解、步骤、错因和总结用中文。"
        "输入只有文字，不要索要照片。"
        "suggested_authority 只能是 auto_objective、auto_canonical 或 none。"
        "result 只能是 correct、wrong 或 pending。"
        f"字段形状：{schema}"
    )


def parse_json_object(text: str) -> dict:
    cleaned = (text or "").strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?", "", cleaned, flags=re.IGNORECASE).strip()
        cleaned = re.sub(r"```$", "", cleaned).strip()
    start = cleaned.find("{")
    end = cleaned.rfind("}")
    if start < 0 or end <= start:
        raise GatewayError(502, "invalid_model_json")
    try:
        value = json.loads(cleaned[start : end + 1])
    except json.JSONDecodeError as exc:
        raise GatewayError(502, "invalid_model_json") from exc
    if not isinstance(value, dict):
        raise GatewayError(502, "invalid_model_json")
    return value


def _strings(value, limit: int) -> list[str]:
    if not isinstance(value, list):
        return []
    cleaned = []
    for item in value:
        text = str(item).strip()
        if text:
            cleaned.append(text)
        if len(cleaned) >= limit:
            break
    return cleaned


def coerce(kind: str, data: dict) -> dict:
    if kind == "solve":
        steps = _strings(data.get("steps"), 8)
        if not steps:
            steps = ["（步骤待补充）"]
        text = str(data.get("text") or "").strip() or "（待确认）"
        try:
            confidence = float(data.get("confidence") or 0)
        except (TypeError, ValueError):
            confidence = 0
        return {
            "text": text,
            "steps": steps,
            "explanation": str(data.get("explanation") or "").strip(),
            "question_type": str(data.get("question_type") or "解答题").strip() or "解答题",
            "confidence": confidence,
            "source_refs": _strings(data.get("source_refs"), 8),
        }
    if kind == "grade":
        result = data.get("result")
        if result not in ALLOWED_RESULT:
            result = "pending"
        authority = data.get("suggested_authority")
        if authority not in ALLOWED_AUTHORITY:
            authority = "none"
        try:
            confidence = float(data.get("confidence") or 0)
        except (TypeError, ValueError):
            confidence = 0
        return {
            "result": result,
            "confidence": confidence,
            "suggested_authority": authority,
        }
    if kind == "error-analysis":
        points = _strings(data.get("points"), 3)
        tips = _strings(data.get("avoidance_tips"), 4)
        if not points or not tips:
            raise GatewayError(502, "invalid_model_json")
        return {"points": points, "avoidance_tips": tips}
    if kind == "summary-groups":
        raw_groups = data.get("groups") if isinstance(data.get("groups"), list) else []
        groups = []
        for item in raw_groups[:12]:
            if not isinstance(item, dict):
                continue
            try:
                correct = int(item.get("correct_count") or 0)
                wrong = int(item.get("wrong_count") or 0)
                pending = int(item.get("pending_count") or 0)
            except (TypeError, ValueError):
                correct = wrong = pending = 0
            groups.append(
                {
                    "question_type": str(item.get("question_type") or "未分类"),
                    "correct_count": correct,
                    "wrong_count": wrong,
                    "pending_count": pending,
                    "bullets": _strings(item.get("bullets"), 6) or ["这一类已汇总。"],
                }
            )
        return {"groups": groups}
    raise GatewayError(404, "not_found")
