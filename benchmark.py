import time
import json
import urllib.request

start = time.time()
print("Sending test request to http://10.0.0.73:8000/v1/chat/completions ...")

payload = {
    "model": "Qwen3.8-27B",
    "messages": [
        {"role": "user", "content": "What is 3 + 5? Reply with only the single digit number."}
    ],
    "max_tokens": 40,
    "temperature": 0.7
}

req = urllib.request.Request(
    "http://10.0.0.73:8000/v1/chat/completions",
    data=json.dumps(payload).encode("utf-8"),
    headers={"Content-Type": "application/json"}
)

with urllib.request.urlopen(req, timeout=120) as resp:
    data = json.loads(resp.read().decode("utf-8"))

total_time = time.time() - start

print("="*60)
print(f"⏱️ Total Response Time: {total_time:.2f} seconds")
msg = data["choices"][0]["message"]
if "reasoning_content" in msg and msg["reasoning_content"]:
    print(f"💭 Thinking:\n{msg['reasoning_content'].strip()}")
print(f"🤖 Answer:\n{msg['content'].strip()}")
usage = data.get("usage", {})
prompt_tokens = usage.get("prompt_tokens", 0)
comp_tokens = usage.get("completion_tokens", 0)
total_tokens = usage.get("total_tokens", 0)
print(f"📊 Token Stats: {prompt_tokens} prompt tokens, {comp_tokens} completion tokens ({total_tokens} total)")
if comp_tokens > 0:
    print(f"⚡ Generation Speed: ~{comp_tokens / total_time:.2f} tokens/sec (end-to-end)")
print("="*60)
