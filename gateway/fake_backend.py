"""Deterministic stand-in that matches StubInferenceClient on the phone."""

from __future__ import annotations


LOCK_THRESHOLD = 0.85


def normalize_answer(text: str) -> str:
    return (text or "").strip().replace(" ", "").replace("\u3000", "").lower()


def looks_objective(canonical: str, question_type: str) -> bool:
    trimmed = (canonical or "").strip()
    if not trimmed or len(trimmed) > 12:
        return False
    if question_type in {"选择题", "填空题", "计算题"}:
        return True
    if len(trimmed) == 1 and (trimmed.isalpha() or trimmed.isdigit()):
        return True
    return all(char.isdigit() or char in ".-/" for char in trimmed)


def clip(text: str) -> str:
    trimmed = (text or "").strip()
    if len(trimmed) <= 40:
        return trimmed
    return trimmed[:40] + "…"


def solve(payload: dict) -> dict:
    stem = (payload.get("stem_text") or "").replace(" ", "")
    filename = payload.get("teacher_key_filename") or ""
    refs = [f"teacher-key:{filename}"] if filename else []
    if "1+1" in stem:
        return {
            "text": "2",
            "steps": ["1 加 1 得 2。"],
            "explanation": "这是一步加法。",
            "question_type": "计算题",
            "confidence": 0.93,
            "source_refs": refs,
        }
    return {
        "text": "（模拟标答）请核对本题最终答案",
        "steps": ["低置信模拟步骤：确认前不会锁定对错，也不会进入错题本。"],
        "explanation": "开放题在离线桩里保持待确认。",
        "question_type": "解答题",
        "confidence": 0.58,
        "source_refs": refs,
    }


def grade(payload: dict) -> dict:
    student = normalize_answer(payload.get("student_answer") or "")
    canonical = normalize_answer(payload.get("canonical_text") or "")
    if not student or not canonical:
        return {"result": "pending", "confidence": 0.2, "suggested_authority": "none"}
    if student == canonical:
        return {"result": "correct", "confidence": 0.96, "suggested_authority": "auto_objective"}
    try:
        confidence = float(payload.get("canonical_confidence") or 0)
    except (TypeError, ValueError):
        confidence = 0
    if confidence >= LOCK_THRESHOLD and looks_objective(
        payload.get("canonical_text") or "",
        payload.get("question_type") or "",
    ):
        return {"result": "wrong", "confidence": 0.91, "suggested_authority": "auto_objective"}
    return {"result": "wrong", "confidence": 0.6, "suggested_authority": "none"}


def error_analysis(payload: dict) -> dict:
    student = clip(payload.get("student_answer") or "")
    canonical = clip(payload.get("canonical_text") or "")
    question_type = payload.get("question_type") or ""
    subject = payload.get("subject") or ""
    return {
        "points": [
            f"作答「{student}」和系统标答「{canonical}」不一致。",
            f"核对这道{question_type}的关键步骤，不要只看最后几个字。",
        ],
        "avoidance_tips": [
            "先自己把步骤写完整，再对照标答逐行看。",
            f"下次做{subject}的{question_type}，先圈出已知条件。",
        ],
    }


def summary_groups(payload: dict) -> dict:
    grouped: dict[str, list] = {}
    for item in payload.get("questions") or []:
        question_type = item.get("question_type") or "未分类"
        grouped.setdefault(question_type, []).append(item)
    groups = []
    for question_type in sorted(grouped):
        items = grouped[question_type]
        correct = sum(1 for item in items if item.get("result") == "correct")
        wrong = sum(1 for item in items if item.get("result") == "wrong")
        pending = sum(1 for item in items if item.get("result") == "pending")
        bullets = [f"共 {len(items)} 题：正确 {correct}，错误 {wrong}，待确认 {pending}。"]
        if pending > 0:
            bullets.append("待确认的题会留在这次总结里。确认判错之后才会进入错题本。")
        if wrong > 0:
            bullets.append("错误题可以先看自己的作答和系统标答，错因会补在错题本里。")
        if wrong == 0 and pending == 0:
            bullets.append("这一类目前没有待处理的错题。")
        groups.append(
            {
                "question_type": question_type,
                "correct_count": correct,
                "wrong_count": wrong,
                "pending_count": pending,
                "bullets": bullets,
            }
        )
    return {"groups": groups}


def handle(kind: str, payload: dict) -> dict:
    if kind == "solve":
        return solve(payload)
    if kind == "grade":
        return grade(payload)
    if kind == "error-analysis":
        return error_analysis(payload)
    if kind == "summary-groups":
        return summary_groups(payload)
    raise KeyError(kind)
