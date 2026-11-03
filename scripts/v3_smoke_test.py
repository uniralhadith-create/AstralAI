#!/usr/bin/env python3
"""Astral AI V3 networking smoke test.

Validates the ALGORITHM behind the V3-A networking fixes end-to-end against
a local mock provider, without needing a Swift toolchain:

  1. A threaded HTTP server speaks the OpenAI-compatible protocol
     (POST /v1/chat/completions with CRLF-framed SSE written in small
     chunks, GET /v1/models) and validates the requests it receives.
  2. The Swift logic is ported faithfully to Python:
     - EndpointResolver.normalizeBaseURL / hasVersionSuffix /
       chatEndpointCandidates / modelsEndpointCandidates
     - LLMService.orderedMessages / sanitizedForWire / encodeMessage /
       encodeTool / makeChatRequests (body building)
     - LineSplitter (ByteLineReader's pure core)
     - SSEParser (feed/flush/consume)
     - LLMService.streamOpenAI's payload handling (delta.content,
       tool_calls assembly, finish_reason, [DONE])
  3. The full pipeline runs against the live server: candidates are
     probed, the request is built by the ported builder, the response is
     read byte-by-byte through LineSplitter -> SSEParser -> extraction.

Exit code 0 = all groups green; 1 = any failure.
"""

import json
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional
from urllib.parse import urlparse

MODEL = "llama-3.3-70b-versatile"
API_KEY = "test-key"

# ---------------------------------------------------------------------------
# Port: EndpointResolver (Infra/EndpointResolver.swift)
# ---------------------------------------------------------------------------

_ENDPOINT_SUFFIXES = [
    "/chat/completions",
    "/completions",
    "/models",
    "/messages",
    "/converse",
    "/converse-stream",
]
_VERSION_SEGMENTS = ["/v1", "/v2", "/v3", "/v4", "/v1beta"]


def normalize_base_url(raw: str) -> Optional[str]:
    """Port of EndpointResolver.normalizeBaseURL."""
    value = raw.strip()
    if not value:
        return None
    if "://" not in value:
        value = "https://" + value
    while value.endswith("/"):
        value = value[:-1]
    lowered = value.lower()
    for suffix in _ENDPOINT_SUFFIXES:
        if lowered.endswith(suffix):
            value = value[: -len(suffix)]
            break
    while value.endswith("/"):
        value = value[:-1]
    parsed = urlparse(value)
    if not parsed.scheme or not parsed.netloc:
        return None
    return value


def has_version_suffix(base: str) -> bool:
    """Port of EndpointResolver.hasVersionSuffix."""
    parsed = urlparse(base)
    path = parsed.path.lower()
    if not path:
        return False
    return any(path == version or path.endswith(version) for version in _VERSION_SEGMENTS)


def chat_endpoint_candidates(raw_base: str) -> List[str]:
    """Port of EndpointResolver.chatEndpointCandidates."""
    base = normalize_base_url(raw_base)
    if base is None:
        return []
    if has_version_suffix(base):
        return [base + "/chat/completions"]
    return [base + "/v1/chat/completions", base + "/chat/completions"]


def models_endpoint_candidates(raw_base: str) -> List[str]:
    """Port of EndpointResolver.modelsEndpointCandidates."""
    base = normalize_base_url(raw_base)
    if base is None:
        return []
    if has_version_suffix(base):
        return [base + "/models"]
    return [base + "/v1/models", base + "/models"]


# ---------------------------------------------------------------------------
# Port: LineSplitter (Infra/ByteLineReader.swift)
# ---------------------------------------------------------------------------


class LineSplitter:
    """Port of LineSplitter: splits only on "\\n" (stripping a trailing
    "\\r"), always preserves empty lines."""

    def __init__(self) -> None:
        self.buffer = bytearray()
        self.pending_cr = False

    def feed(self, data: bytes) -> List[str]:
        lines: List[str] = []
        for byte in data:
            if byte == 0x0A:  # "\n"
                if self.pending_cr:
                    self.buffer.pop()
                    self.pending_cr = False
                lines.append(self.buffer.decode("utf-8", errors="replace"))
                self.buffer.clear()
            else:
                if byte == 0x0D:  # "\r"
                    self.pending_cr = True
                else:
                    self.pending_cr = False
                self.buffer.append(byte)
        return lines

    def finish(self) -> Optional[str]:
        self.pending_cr = False
        if not self.buffer:
            return None
        line = self.buffer.decode("utf-8", errors="replace")
        self.buffer.clear()
        return line


# ---------------------------------------------------------------------------
# Port: SSEParser (Infra/SSEParser.swift)
# ---------------------------------------------------------------------------


class SSEParser:
    """Port of SSEParser: incremental Server-Sent Events parsing."""

    def __init__(self) -> None:
        self.buffer = ""
        self.data_lines: List[str] = []
        self.has_data = False

    def feed(self, text: str) -> List[str]:
        self.buffer += text
        payloads: List[str] = []
        while "\n" in self.buffer:
            line, self.buffer = self.buffer.split("\n", 1)
            if line.endswith("\r"):
                line = line[:-1]
            self._consume(line, payloads)
        return payloads

    def flush(self) -> List[str]:
        payloads: List[str] = []
        if self.buffer:
            line = self.buffer
            self.buffer = ""
            if line.endswith("\r"):
                line = line[:-1]
            self._consume(line, payloads)
        if self.has_data:
            payloads.append("\n".join(self.data_lines))
            self.data_lines = []
            self.has_data = False
        return payloads

    def _consume(self, line: str, payloads: List[str]) -> None:
        if not line:
            if self.has_data:
                payloads.append("\n".join(self.data_lines))
                self.data_lines = []
                self.has_data = False
            return
        if line.startswith(":"):
            return  # comment / keep-alive
        if ":" not in line:
            if line == "data":
                self.data_lines.append("")
                self.has_data = True
            return
        field, value = line.split(":", 1)
        if value.startswith(" "):
            value = value[1:]
        if field == "data":
            self.data_lines.append(value)
            self.has_data = True


# ---------------------------------------------------------------------------
# Port: history handling (LLMService.orderedMessages / sanitizedForWire)
# ---------------------------------------------------------------------------
# Messages are plain dicts mirroring ChatMessage:
#   {"role", "content", "tool_calls": [{"id", "name", "arguments"}] | None,
#    "tool_call_id": str | None}


def ordered_messages(messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Port of LLMService.orderedMessages (system hoisting)."""
    system = [m for m in messages if m["role"] == "system"]
    if not system:
        return list(messages)
    rest = [m for m in messages if m["role"] != "system"]
    return system + rest


def sanitized_for_wire(messages: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Port of LLMService.sanitizedForWire."""
    defined = set()
    for message in messages:
        if message["role"] == "assistant":
            for call in message.get("tool_calls") or []:
                if call["id"]:
                    defined.add(call["id"])

    answered = set()
    for message in messages:
        if message["role"] == "tool":
            call_id = message.get("tool_call_id") or ""
            if call_id and call_id in defined and call_id not in answered:
                answered.add(call_id)

    result: List[Dict[str, Any]] = []
    for message in messages:
        role = message["role"]
        if role in ("system", "user"):
            result.append(message)
        elif role == "assistant":
            calls = message.get("tool_calls") or []
            if not calls:
                if message["content"]:
                    result.append(message)
                continue
            supported = [c for c in calls if c["id"] in answered]
            if len(supported) == len(calls):
                result.append(message)
            elif not supported:
                if message["content"]:
                    result.append({**message, "tool_calls": None})
            else:
                result.append({**message, "tool_calls": supported})
        else:  # tool: filtered in the second pass
            result.append(message)

    seen_tool_responses = set()
    cleaned: List[Dict[str, Any]] = []
    for message in result:
        if message["role"] != "tool":
            cleaned.append(message)
            continue
        call_id = message.get("tool_call_id") or ""
        if call_id in answered and call_id not in seen_tool_responses:
            seen_tool_responses.add(call_id)
            cleaned.append(message)
    while cleaned and cleaned[0]["role"] == "tool":
        cleaned.pop(0)
    return cleaned


# ---------------------------------------------------------------------------
# Port: payload encoding (LLMService.encodeMessage / encodeTool)
# ---------------------------------------------------------------------------


def encode_message(message: Dict[str, Any]) -> Dict[str, Any]:
    """Port of LLMService.encodeMessage for the smoke-test subset
    (system / user plain, assistant with tool_calls + null content, tool)."""
    role = message["role"]
    if role in ("system", "user"):
        return {"role": role, "content": message["content"]}
    if role == "assistant":
        dictionary: Dict[str, Any] = {
            "role": "assistant",
            "content": message["content"] if message["content"] else None,
        }
        calls = message.get("tool_calls") or []
        if calls:
            dictionary["tool_calls"] = [
                {
                    "id": call["id"],
                    "type": "function",
                    "function": {
                        "name": call["name"],
                        "arguments": call["arguments"],
                    },
                }
                for call in calls
            ]
        return dictionary
    return {
        "role": "tool",
        "tool_call_id": message.get("tool_call_id") or "",
        "content": message["content"],
    }


def encode_tool(tool: Dict[str, Any]) -> Dict[str, Any]:
    """Port of LLMService.encodeTool: `parameters` is ALWAYS present."""
    function = {
        "name": tool["name"],
        "description": tool["description"],
    }
    parameters = tool.get("parameters")
    if parameters is not None:
        function["parameters"] = parameters
    else:
        function["parameters"] = {"type": "object", "properties": {}}
    return {"type": tool.get("type", "function"), "function": function}


def make_chat_body(
    config: Dict[str, Any],
    messages: List[Dict[str, Any]],
    tools: Optional[List[Dict[str, Any]]],
    model: Optional[str],
    stream: bool,
) -> Dict[str, Any]:
    """Port of the body half of LLMService.makeChatRequests."""
    body: Dict[str, Any] = {
        "messages": [
            encode_message(m)
            for m in ordered_messages(sanitized_for_wire(messages))
        ],
        "stream": stream,
        "temperature": config["temperature"],
    }
    resolved = model or config.get("main_model") or ""
    if resolved:
        body["model"] = resolved
    if config.get("max_tokens"):
        body["max_tokens"] = config["max_tokens"]
    if tools:
        body["tools"] = [encode_tool(t) for t in tools]
    return body


# ---------------------------------------------------------------------------
# Port: LLMService.streamOpenAI payload handling
# ---------------------------------------------------------------------------


class OpenAIStreamAssembler:
    """Faithful port of streamOpenAI's handlePayload + line loop state."""

    def __init__(self) -> None:
        self.parser = SSEParser()
        self.tool_parts: Dict[int, Dict[str, Any]] = {}
        self.finish_reason: Optional[str] = None
        self.done = False
        self.text_parts: List[str] = []

    def handle_payload(self, payload: str) -> None:
        if payload == "[DONE]":
            self.done = True
            return
        try:
            chunk = json.loads(payload)
        except json.JSONDecodeError:
            return
        if not isinstance(chunk, dict):
            return
        choices = chunk.get("choices")
        if not isinstance(choices, list) or not choices:
            return
        choice = choices[0]
        if not isinstance(choice, dict):
            return

        delta = choice.get("delta")
        if not isinstance(delta, dict):
            delta = choice.get("message")
        if not isinstance(delta, dict):
            delta = {}

        # "reasoning_content" is deliberately NOT treated as content.
        content = delta.get("content")
        if isinstance(content, str) and content:
            self.text_parts.append(content)

        calls = delta.get("tool_calls")
        if isinstance(calls, list):
            for call in calls:
                if not isinstance(call, dict):
                    continue
                index = call.get("index")
                if not isinstance(index, int):
                    index = len(self.tool_parts)
                part = self.tool_parts.get(index, {"id": None, "name": None, "arguments": ""})
                call_id = call.get("id")
                if isinstance(call_id, str) and part["id"] is None:
                    part["id"] = call_id
                function = call.get("function")
                if isinstance(function, dict):
                    name = function.get("name")
                    if isinstance(name, str) and part["name"] is None:
                        part["name"] = name
                    arguments = function.get("arguments")
                    if isinstance(arguments, str):
                        part["arguments"] += arguments
                self.tool_parts[index] = part

        reason = choice.get("finish_reason")
        if isinstance(reason, str) and reason:
            self.finish_reason = reason

    def feed_line(self, line: str) -> None:
        """Mirrors `for payload in parser.feed(line + "\\n")`."""
        for payload in self.parser.feed(line + "\n"):
            self.handle_payload(payload)

    def finish_stream(self) -> None:
        """Mirrors `if !done { for payload in parser.flush() ... }`."""
        if not self.done:
            for payload in self.parser.flush():
                self.handle_payload(payload)

    def result(self) -> Dict[str, Any]:
        """Mirrors emitToolCalls + the final .finished event."""
        calls = []
        for index in sorted(self.tool_parts):
            part = self.tool_parts[index]
            if not part["name"]:
                continue
            call_id = part["id"] if part["id"] else f"call_{index}"
            arguments = part["arguments"] if part["arguments"] else "{}"
            calls.append({"id": call_id, "name": part["name"], "arguments": arguments})
        return {
            "text": "".join(self.text_parts),
            "finish_reason": self.finish_reason,
            "done": self.done,
            "tool_calls": calls,
        }


def stream_openai(response: Any) -> Dict[str, Any]:
    """Port of streamOpenAI's ByteLineReader loop: byte-by-byte reads."""
    assembler = OpenAIStreamAssembler()
    splitter = LineSplitter()
    while True:
        byte = response.read(1)
        if not byte:
            break
        for line in splitter.feed(byte):
            if assembler.done:
                break
            assembler.feed_line(line)
        if assembler.done:
            break
    rest = splitter.finish()
    if rest is not None:
        assembler.feed_line(rest)
    assembler.finish_stream()
    return assembler.result()


def stream_openai_from_bytes(data: bytes, chunk_size: int = 1) -> Dict[str, Any]:
    """In-process variant: feeds scripted SSE bytes through the exact same
    LineSplitter -> SSEParser -> assembler pipeline."""
    assembler = OpenAIStreamAssembler()
    splitter = LineSplitter()
    for i in range(0, len(data), chunk_size):
        for line in splitter.feed(data[i : i + chunk_size]):
            assembler.feed_line(line)
    rest = splitter.finish()
    if rest is not None:
        assembler.feed_line(rest)
    assembler.finish_stream()
    return assembler.result()


# ---------------------------------------------------------------------------
# Mock provider server
# ---------------------------------------------------------------------------


def sse(*events: str) -> bytes:
    """Builds a CRLF-framed SSE byte stream (each event = lines + blank)."""
    out = bytearray()
    for event in events:
        out += event.encode("utf-8") + b"\r\n\r\n"
    return bytes(out)


SSE_HELLO = sse(
    ": keep-alive comment",
    'data: {"choices":[{"delta":{"role":"assistant"}}]}',
    'data: {"choices":[{"delta":{"content":"Hello "}}]}',
    'data: {"choices":[{"delta":{"content":"from Astral"}}]}',
    'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}',
    "data: [DONE]",
)

SSE_TOOL_CALLS = sse(
    'data: {"choices":[{"delta":{"role":"assistant","tool_calls":['
    '{"index":0,"id":"call_abc123","type":"function","function":{"name":"web_search","arguments":""}},'
    '{"index":1,"id":"call_def456","type":"function","function":{"name":"file_write","arguments":""}}]}}]}',
    'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"query\\":"}}]}}]}',
    'data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\\"path\\":\\"/tmp/a.txt\\",\\"content\\":\\"hi\\"}"}}]}}]}',
    'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"latest news\\"}"}}]}}]}',
    'data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
    "data: [DONE]",
)

RECEIVED: List[Dict[str, Any]] = []
RECEIVED_LOCK = threading.Lock()


class MockProviderHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # Paths this mock serves (everything else 404s, so candidate probing
    # and its fallback are both exercised).
    chat_paths = {
        "/v1/chat/completions",
        "/chat/completions",
        "/api/chat/completions",
    }

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        pass

    def do_GET(self) -> None:
        if self.path == "/v1/models" or self.path == "/models":
            body = json.dumps({"data": [{"id": MODEL}]}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self._json_error(404, {"error": {"message": "Not found"}})

    def do_POST(self) -> None:
        if self.path not in self.chat_paths:
            self._json_error(404, {"error": {"message": "Not found"}})
            return
        if self.headers.get("Authorization") != f"Bearer {API_KEY}":
            self._json_error(401, {"error": {"message": "Bad key"}})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            payload = json.loads(self.rfile.read(length))
        except (ValueError, json.JSONDecodeError):
            self._json_error(400, {"error": {"message": "Bad body"}})
            return

        with RECEIVED_LOCK:
            RECEIVED.append(
                {
                    "path": self.path,
                    "auth": self.headers.get("Authorization"),
                    "payload": payload,
                }
            )

        if payload.get("model") != MODEL:
            self._json_error(400, {"error": {"message": f"Bad model {payload.get('model')!r}"}})
            return
        messages = payload.get("messages")
        if not isinstance(messages, list) or not messages:
            self._json_error(400, {"error": {"message": "messages must be a non-empty list"}})
            return
        if payload.get("stream") is not True:
            self._json_error(400, {"error": {"message": "stream must be true"}})
            return

        wants_tools = bool(payload.get("tools"))
        marker = any(
            m.get("role") == "user" and "USE_TOOL" in m.get("content", "")
            for m in messages
        )
        script = SSE_TOOL_CALLS if (wants_tools and marker) else SSE_HELLO

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        # Small chunks with tiny sleeps: simulate network chunking so the
        # reader must survive boundaries inside SSE lines.
        for i in range(0, len(script), 7):
            self.wfile.write(script[i : i + 7])
            self.wfile.flush()
            time.sleep(0.001)

    def _json_error(self, status: int, body: Dict[str, Any]) -> None:
        data = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


# ---------------------------------------------------------------------------
# Client pipeline (probeStream port)
# ---------------------------------------------------------------------------


def probe_and_stream(
    base_url: str,
    body: Dict[str, Any],
    api_key: str,
    timeout: float = 15.0,
):
    """Port of probeStream's candidate loop: probe until one answers."""
    last_error: Optional[Exception] = None
    for url in chat_endpoint_candidates(base_url):
        request = urllib.request.Request(
            url,
            data=json.dumps(body).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            return urllib.request.urlopen(request, timeout=timeout), url
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code in (404, 400, 422):
                continue
            raise
    raise last_error or RuntimeError("No endpoint reachable")


# ---------------------------------------------------------------------------
# Test harness
# ---------------------------------------------------------------------------

FAILURES: List[str] = []


def group(title: str) -> None:
    print(f"\n== {title} ==")


def check(name: str, ok: bool, detail: str = "") -> None:
    ok = bool(ok)
    status = "PASS" if ok else "FAIL"
    suffix = f"  [{detail}]" if (detail and not ok) else ""
    print(f"  [{status}] {name}{suffix}")
    if not ok:
        FAILURES.append(name)


def msg(role: str, content: str, calls=None, call_id=None) -> Dict[str, Any]:
    return {
        "role": role,
        "content": content,
        "tool_calls": calls,
        "tool_call_id": call_id,
    }


def call(call_id: str, name: str = "web_search", arguments: str = "{}") -> Dict[str, Any]:
    return {"id": call_id, "name": name, "arguments": arguments}


# ---------------------------------------------------------------------------
# Assertion groups
# ---------------------------------------------------------------------------


def test_line_splitter() -> None:
    group("LineSplitter (byte-exact lines, empty lines preserved)")

    splitter = LineSplitter()
    check(
        "a\\n\\nb\\n -> [a, '', b]",
        splitter.feed(b"a\n\nb\n") == ["a", "", "b"],
    )

    splitter = LineSplitter()
    check(
        "a\\n\\nb -> [a, ''] now, 'b' via finish()",
        splitter.feed(b"a\n\nb") == ["a", ""] and splitter.finish() == "b",
    )

    splitter = LineSplitter()
    check(
        "CRLF tolerated, empty lines preserved",
        splitter.feed(b"a\r\n\r\nb\r\n") == ["a", "", "b"],
    )

    splitter = LineSplitter()
    lines = []
    for byte in b"data: hi\n\ndata: bye\n\n":
        lines += splitter.feed(bytes([byte]))
    check(
        "1-byte feeds (SSE framing intact)",
        lines == ["data: hi", "", "data: bye", ""],
    )

    splitter = LineSplitter()
    check("lone CR is data", splitter.feed(b"a\rb\n") == ["a\rb"])

    splitter = LineSplitter()
    check("CR split across feeds", splitter.feed(b"a\r") == [] and splitter.feed(b"\n") == ["a"])

    splitter = LineSplitter()
    check("empty input -> no lines", splitter.feed(b"") == [] and splitter.finish() is None)

    splitter = LineSplitter()
    check("trailing partial via finish()", splitter.feed(b"a\nbc") == ["a"] and splitter.finish() == "bc")

    splitter = LineSplitter()
    check(
        "trailing CR without LF survives as data",
        splitter.feed(b"abc\r") == [] and splitter.finish() == "abc\r",
    )


def test_sse_parser() -> None:
    group("SSEParser (CRLF, comments, multi-line data)")

    parser = SSEParser()
    check("two events in one chunk", parser.feed("data: hello\n\ndata: world\n\n") == ["hello", "world"])

    parser = SSEParser()
    check("event split across chunks", parser.feed("data: hel") == [] and parser.feed("lo\n\n") == ["hello"])

    parser = SSEParser()
    check("[DONE] sentinel as payload", parser.feed("data: [DONE]\n\n") == ["[DONE]"])

    parser = SSEParser()
    check("CRLF endings", parser.feed("data: a\r\n\r\n") == ["a"])

    parser = SSEParser()
    check("comment lines ignored", parser.feed(": keepalive\n\ndata: hi\n\n") == ["hi"])

    parser = SSEParser()
    check("multi data lines joined with newline", parser.feed("data: x\ndata: y\n\n") == ["x\ny"])

    parser = SSEParser()
    check("flush emits partial event", parser.feed("data: tail") == [] and parser.flush() == ["tail"])


def test_endpoint_resolver() -> None:
    group("EndpointResolver (base normalization + candidates)")

    check(
        "bare host -> /v1 candidate first",
        chat_endpoint_candidates("https://api.groq.com")
        == ["https://api.groq.com/v1/chat/completions", "https://api.groq.com/chat/completions"],
    )
    check(
        "base with /v1 -> single candidate",
        chat_endpoint_candidates("https://api.groq.com/v1")
        == ["https://api.groq.com/v1/chat/completions"],
    )
    check(
        "pasted full endpoint reduced to base",
        chat_endpoint_candidates("https://api.x.ai/v1/chat/completions")
        == ["https://api.x.ai/v1/chat/completions"],
    )
    check(
        "trailing slash + /v1beta suffix detected",
        chat_endpoint_candidates("https://genai.googleapis.com/v1beta/")
        == ["https://genai.googleapis.com/v1beta/chat/completions"],
    )
    check(
        "models candidates",
        models_endpoint_candidates("https://api.groq.com")
        == ["https://api.groq.com/v1/models", "https://api.groq.com/models"],
    )
    check("empty base -> no candidates", chat_endpoint_candidates("   ") == [])


def test_request_builder() -> None:
    group("Request builder (encodeMessage / encodeTool)")

    encoded = encode_message(msg("assistant", "", calls=[call("a", "web_search", '{"q":1}')]))
    check(
        "assistant tool_calls use JSON null content",
        encoded == {
            "role": "assistant",
            "content": None,
            "tool_calls": [
                {
                    "id": "a",
                    "type": "function",
                    "function": {"name": "web_search", "arguments": '{"q":1}'},
                }
            ],
        },
        detail=json.dumps(encoded),
    )

    encoded = encode_message(msg("assistant", "plain text"))
    check(
        "plain assistant keeps string content",
        encoded == {"role": "assistant", "content": "plain text"},
    )

    encoded = encode_message(msg("tool", "result", call_id="a"))
    check(
        "tool message shape",
        encoded == {"role": "tool", "tool_call_id": "a", "content": "result"},
    )

    tool = encode_tool({"name": "web_search", "description": "Search the web", "parameters": None})
    check(
        "parameters always present (empty schema injected)",
        tool["function"]["parameters"] == {"type": "object", "properties": {}},
    )

    schema = {"type": "object", "properties": {"q": {"type": "string"}}}
    tool = encode_tool({"name": "web_search", "description": "d", "parameters": schema})
    check("declared parameters passed through", tool["function"]["parameters"] == schema)


def test_history_sanitizer() -> None:
    group("History sanitizer (sanitizedForWire)")

    result = sanitized_for_wire(
        [
            msg("tool", "r1", call_id="a"),
            msg("tool", "r2", call_id="b"),
            msg("user", "continue"),
        ]
    )
    check("orphan tool messages dropped", result == [msg("user", "continue")], detail=json.dumps(result))

    result = sanitized_for_wire(
        [
            msg("system", "sys"),
            msg("user", "hi"),
            msg("assistant", "checking", calls=[call("a"), call("b")]),
            msg("tool", "ra", call_id="a"),
        ]
    )
    check(
        "assistant trimmed to answered calls",
        result
        == [
            msg("system", "sys"),
            msg("user", "hi"),
            msg("assistant", "checking", calls=[call("a")]),
            msg("tool", "ra", call_id="a"),
        ],
        detail=json.dumps(result),
    )

    result = sanitized_for_wire(
        [
            msg("user", "hi"),
            msg("assistant", "let me check", calls=[call("a"), call("b")]),
        ]
    )
    check(
        "all calls unanswered -> plain assistant text",
        result == [msg("user", "hi"), msg("assistant", "let me check", calls=None)],
        detail=json.dumps(result),
    )

    result = sanitized_for_wire(
        [
            msg("assistant", "", calls=[call("a")]),
            msg("tool", "first", call_id="a"),
            msg("tool", "second", call_id="a"),
            msg("user", "go on"),
        ]
    )
    check(
        "duplicate tool responses: first wins",
        result
        == [
            msg("assistant", "", calls=[call("a")]),
            msg("tool", "first", call_id="a"),
            msg("user", "go on"),
        ],
        detail=json.dumps(result),
    )

    result = sanitized_for_wire(
        [
            msg("tool", "r", call_id="a"),
            msg("assistant", "", calls=[call("a")]),
            msg("tool", "r", call_id="a"),
            msg("user", "next"),
        ]
    )
    check(
        "window never starts with a tool message",
        bool(result) and result[0]["role"] != "tool",
        detail=json.dumps(result),
    )

    valid = [
        msg("system", "sys"),
        msg("user", "search"),
        msg("assistant", "", calls=[call("a"), call("b")]),
        msg("tool", "ra", call_id="a"),
        msg("tool", "rb", call_id="b"),
        msg("user", "thanks"),
        msg("assistant", "done"),
    ]
    check("valid tool conversation untouched", sanitized_for_wire(valid) == valid)

    result = sanitized_for_wire(
        [msg("system", "s1"), msg("user", "u1"), msg("system", "s2"), msg("user", "u2")]
    )
    check(
        "system/user untouched",
        result == [msg("system", "s1"), msg("user", "u1"), msg("system", "s2"), msg("user", "u2")],
    )

    check("empty history stays empty", sanitized_for_wire([]) == [])


def test_live_pipeline(base: str) -> None:
    group(f"Live pipeline vs mock server (base {base})")

    config = {"temperature": 0.4, "main_model": MODEL, "max_tokens": None}
    # Broken history on purpose: the orphan tool message must be sanitized
    # away before the bytes hit the wire.
    messages = [
        msg("system", "You are Astral."),
        msg("tool", "orphan result", call_id="zzz"),
        msg("user", "hello"),
    ]
    body = make_chat_body(config, messages, tools=None, model=None, stream=True)

    response, url = probe_and_stream(base, body, API_KEY)
    with response:
        result = stream_openai(response)

    check("probe picked a reachable candidate", url.endswith("/chat/completions"), detail=url)
    check("streamed text == 'Hello from Astral'", result["text"] == "Hello from Astral", detail=repr(result["text"]))
    check("finish_reason == stop", result["finish_reason"] == "stop", detail=repr(result["finish_reason"]))
    check("[DONE] sentinel seen", result["done"] is True)

    with RECEIVED_LOCK:
        received = list(RECEIVED)
    last = received[-1] if received else None
    check("server saw the Authorization header", bool(last) and last["auth"] == f"Bearer {API_KEY}")
    wire_messages = (last or {}).get("payload", {}).get("messages") or []
    check(
        "server saw sanitized messages (orphan gone)",
        wire_messages
        == [
            {"role": "system", "content": "You are Astral."},
            {"role": "user", "content": "hello"},
        ],
        detail=json.dumps(wire_messages),
    )


def test_live_pipeline_versioned_base(base: str) -> None:
    group(f"Live pipeline with version-suffixed base (base {base})")

    candidates = chat_endpoint_candidates(base)
    check("single candidate for /v1 base", len(candidates) == 1 and candidates[0].endswith("/v1/chat/completions"), detail=json.dumps(candidates))

    config = {"temperature": 0.4, "main_model": MODEL, "max_tokens": None}
    body = make_chat_body(config, [msg("user", "hello again")], tools=None, model=None, stream=True)
    response, url = probe_and_stream(base, body, API_KEY)
    with response:
        result = stream_openai(response)
    check("streamed text correct", result["text"] == "Hello from Astral", detail=repr(result["text"]))
    check("finish_reason == stop", result["finish_reason"] == "stop")


def test_candidate_fallback(base: str) -> None:
    group("Candidate probing falls back after 404")

    candidates = chat_endpoint_candidates(base)
    check(
        "two candidates, wrong one first",
        candidates
        == [
            base + "/v1/chat/completions",
            base + "/chat/completions",
        ],
        detail=json.dumps(candidates),
    )

    config = {"temperature": 0.4, "main_model": MODEL, "max_tokens": None}
    body = make_chat_body(config, [msg("user", "hello")], tools=None, model=None, stream=True)
    response, url = probe_and_stream(base, body, API_KEY)
    with response:
        result = stream_openai(response)
    check("fallback candidate answered", url == base + "/chat/completions", detail=url)
    check("streamed text correct via fallback", result["text"] == "Hello from Astral")


def test_models_endpoint(base: str) -> None:
    group("Models endpoint")

    urls = models_endpoint_candidates(base)
    ok = False
    model_ids: List[str] = []
    for url in urls:
        request = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {API_KEY}"}, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                body = json.loads(response.read().decode("utf-8"))
                model_ids = [entry["id"] for entry in body.get("data", [])]
                ok = MODEL in model_ids
                break
        except urllib.error.HTTPError:
            continue
    check(f"model list contains {MODEL}", ok, detail=json.dumps(model_ids))


def test_tool_calls_round_trip(base: str) -> None:
    group("Tool-calls round trip (HTTP + split-chunk assembly)")

    # 1. In-process: scripted SSE with fragments split across 1-byte chunks.
    result = stream_openai_from_bytes(SSE_TOOL_CALLS, chunk_size=1)
    calls = result["tool_calls"]
    check("two calls assembled", len(calls) == 2, detail=json.dumps(calls))
    if len(calls) == 2:
        first, second = calls
        check(
            "call 1 id/name/arguments",
            first == {"id": "call_abc123", "name": "web_search", "arguments": '{"query":"latest news"}'},
            detail=json.dumps(first),
        )
        check(
            "call 2 id/name/arguments",
            second == {"id": "call_def456", "name": "file_write", "arguments": '{"path":"/tmp/a.txt","content":"hi"}'},
            detail=json.dumps(second),
        )
    check("finish_reason == tool_calls", result["finish_reason"] == "tool_calls")
    check("no text content emitted", result["text"] == "", detail=repr(result["text"]))
    check("[DONE] sentinel seen", result["done"] is True)

    # 2. Over HTTP: the request carries tools (parameters always present);
    #    the scripted response exercises the same assembler live.
    config = {"temperature": 0.4, "main_model": MODEL, "max_tokens": None}
    tools = [
        {"name": "web_search", "description": "Search the web", "parameters": None},
        {"name": "file_write", "description": "Write a file", "parameters": None},
    ]
    messages = [msg("system", "You are Astral."), msg("user", "USE_TOOL please")]
    body = make_chat_body(config, messages, tools=tools, model=None, stream=True)

    response, url = probe_and_stream(base, body, API_KEY)
    with response:
        result = stream_openai(response)
    calls = result["tool_calls"]
    check("HTTP round trip assembled both calls", len(calls) == 2, detail=json.dumps(calls))
    if len(calls) == 2:
        check(
            "HTTP call 1 correct",
            calls[0] == {"id": "call_abc123", "name": "web_search", "arguments": '{"query":"latest news"}'},
            detail=json.dumps(calls[0]),
        )
        check(
            "HTTP call 2 correct",
            calls[1] == {"id": "call_def456", "name": "file_write", "arguments": '{"path":"/tmp/a.txt","content":"hi"}'},
            detail=json.dumps(calls[1]),
        )

    with RECEIVED_LOCK:
        received = list(RECEIVED)
    last = received[-1] if received else {}
    wire_tools = (last.get("payload") or {}).get("tools") or []
    check(
        "server saw tools with parameters always present",
        len(wire_tools) == 2
        and all(t["function"].get("parameters") == {"type": "object", "properties": {}} for t in wire_tools),
        detail=json.dumps(wire_tools),
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    server = ThreadingHTTPServer(("127.0.0.1", 0), MockProviderHandler)
    port = server.server_address[1]
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    base = f"http://127.0.0.1:{port}"
    versioned_base = f"http://127.0.0.1:{port}/v1"
    fallback_base = f"http://127.0.0.1:{port}/api"

    print(f"Astral AI V3 smoke test — mock provider at {base}")

    try:
        test_line_splitter()
        test_sse_parser()
        test_endpoint_resolver()
        test_request_builder()
        test_history_sanitizer()
        test_live_pipeline(base)
        test_live_pipeline_versioned_base(versioned_base)
        test_candidate_fallback(fallback_base)
        test_models_endpoint(base)
        test_tool_calls_round_trip(base)
    finally:
        server.shutdown()
        server.server_close()

    total = len(FAILURES)
    print(f"\n{'=' * 60}")
    if total:
        print(f"RESULT: FAIL — {total} check(s) failed:")
        for name in FAILURES:
            print(f"  - {name}")
        return 1
    print("RESULT: PASS — all checks green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
