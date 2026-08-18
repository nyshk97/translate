#!/usr/bin/env python3
"""Groq 候補モデルの TTFT・翻訳品質をアプリの実プロンプトで実測する。

使い方:
    python3 scripts/bench-models.py                          # 現行モデルの実測（既定セット）
    python3 scripts/bench-models.py openai/gpt-oss-20b ...   # モデルを指定
    python3 scripts/bench-models.py --effort low <model>     # reasoning_effort を指定

pass の目安: ttf_content <= 0.5s / 出力に <think> 等の reasoning が混入していない /
両方向とも自然な訳文。
"""
import argparse
import json
import subprocess
import time
import urllib.error
import urllib.request

# TranslationDirection.swift の systemPrompt と一致させること
PROMPT_JA2EN = (
    "Translate Japanese into natural, idiomatic English. Preserve the meaning, tone, "
    "names, numbers, URLs, and formatting. Do not translate word-for-word; rewrite "
    "awkward literal phrasing. Output only the translation."
)
PROMPT_EN2JA = (
    "Translate the text into natural, idiomatic Japanese. Preserve the meaning, tone, "
    "names, numbers, URLs, and formatting. Do not translate word-for-word; rewrite "
    'awkward literal phrasing. Use Japanese that reads as if originally written in '
    'Japanese. Prefer common Japanese phrasing over stiff dictionary wording, e.g. '
    'translate "too literal" as "直訳っぽい" when natural. Output only the translation.'
)

TEXT_EN = (
    "Apps I build for myself and use in my daily life. They are open source and you "
    "are welcome to install them — but I ship breaking changes without notice, so "
    "forking is the recommended way to depend on one."
)
TEXT_JA = "初動の速さを最優先にしているので、ショートカットを押した瞬間に最初のトークンが出てくる体感を大事にしています。"


def api_key() -> str:
    return subprocess.run(
        ["security", "find-generic-password",
         "-s", "com.d0ne1s.translate", "-a", "groq-api-key", "-w"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def run(key: str, model: str, system: str, text: str, effort: str | None) -> None:
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": text},
        ],
        "stream": True,
        "temperature": 0.3,
    }
    if effort:
        body["reasoning_effort"] = effort
    req = urllib.request.Request(
        "https://api.groq.com/openai/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            # Cloudflare が Python デフォルト UA を 403 (error 1010) で弾くため必須
            "User-Agent": "curl/8.7.1",
        },
    )
    t0 = time.time()
    ttf_content = None
    content: list[str] = []
    reasoning_len = 0
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    chunk = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                delta = chunk.get("choices", [{}])[0].get("delta", {})
                if delta.get("reasoning"):
                    reasoning_len += len(delta["reasoning"])
                if delta.get("content"):
                    if ttf_content is None:
                        ttf_content = time.time() - t0
                    content.append(delta["content"])
    except urllib.error.HTTPError as e:
        print(f"  HTTP {e.code}: {e.read().decode()[:300]}")
        return
    total = time.time() - t0
    out = "".join(content)
    ttf = f"{ttf_content:.2f}s" if ttf_content is not None else "N/A"
    think = " ⚠️ <think> 混入!" if "<think>" in out else ""
    print(f"  ttf_content={ttf} total={total:.2f}s reasoning_chars={reasoning_len}{think}")
    print(f"  output: {out[:400]}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("models", nargs="*", default=None,
                   help="計測するモデル ID（省略時は既定セット）")
    p.add_argument("--effort", default="low",
                   help="reasoning_effort（low/medium/high/none。'off' で未指定）")
    args = p.parse_args()

    models = args.models or ["openai/gpt-oss-120b"]
    effort = None if args.effort == "off" else args.effort
    key = api_key()
    for m in models:
        print(f"\n=== {m} (effort={effort}) / en->ja ===")
        run(key, m, PROMPT_EN2JA, TEXT_EN, effort)
        print(f"=== {m} (effort={effort}) / ja->en ===")
        run(key, m, PROMPT_JA2EN, TEXT_JA, effort)


if __name__ == "__main__":
    main()
