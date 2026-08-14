#!/usr/bin/env python3
"""
Comprehensive test client for Qwen3.8-27B OpenAI-compatible endpoint.
Demonstrates standard OpenAI chat completions, reasoning_content extraction, and streaming.
"""
import sys
import json
import urllib.request

BASE_URL = sys.argv[1] if len(sys.argv) > 1 else "http://10.0.0.73:8000"

def test_models():
    print(f"\n=======================================================")
    print(f"[1] Testing GET {BASE_URL}/v1/models")
    print(f"=======================================================")
    req = urllib.request.Request(f"{BASE_URL}/v1/models")
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        print(json.dumps(data, indent=2))

def test_chat_non_streaming():
    print(f"\n=======================================================")
    print(f"[2] Testing Non-Streaming POST {BASE_URL}/v1/chat/completions")
    print(f"=======================================================")
    payload = {
        "model": "Qwen3.8-27B",
        "messages": [
            {"role": "system", "content": "You are a helpful assistant."},
            {"role": "user", "content": "What is 2 + 2? Give just the final number."}
        ],
        "temperature": 0.7,
        "max_tokens": 80,
        "stream": False
    }
    req = urllib.request.Request(
        f"{BASE_URL}/v1/chat/completions",
        data=json.dumps(payload).encode('utf-8'),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read().decode('utf-8'))
        msg = data['choices'][0]['message']
        reasoning = msg.get('reasoning_content', '')
        content = msg.get('content', '')
        if reasoning:
            print(f"💭 Reasoning/Thinking:\n{reasoning}")
        print(f"🤖 Final Answer:\n{content}")
        print(f"📊 Usage: {data.get('usage')}")

def test_chat_streaming():
    print(f"\n=======================================================")
    print(f"[3] Testing Streaming POST {BASE_URL}/v1/chat/completions")
    print(f"=======================================================")
    payload = {
        "model": "Qwen3.8-27B",
        "messages": [
            {"role": "user", "content": "Write one sentence about space exploration."}
        ],
        "temperature": 0.7,
        "max_tokens": 80,
        "stream": True
    }
    req = urllib.request.Request(
        f"{BASE_URL}/v1/chat/completions",
        data=json.dumps(payload).encode('utf-8'),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=180) as resp:
        for line in resp:
            line_str = line.decode('utf-8').strip()
            if line_str.startswith("data: ") and line_str != "data: [DONE]":
                try:
                    chunk = json.loads(line_str[6:])
                    delta = chunk['choices'][0].get('delta', {})
                    r_content = delta.get('reasoning_content', '')
                    content = delta.get('content', '')
                    if r_content:
                        print(f"{r_content}", end="", flush=True)
                    if content:
                        print(f"{content}", end="", flush=True)
                except Exception:
                    pass
    print("\n")

if __name__ == "__main__":
    try:
        test_models()
        test_chat_non_streaming()
        test_chat_streaming()
        print("✅ All OpenAI compatibility tests completed successfully!")
    except Exception as e:
        print(f"\n❌ Error during test: {e}")
        sys.exit(1)
