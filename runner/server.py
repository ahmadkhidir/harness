#!/usr/bin/env python3
"""Harness external runner.

A small, dependency-free HTTP service that executes Python, Node.js, or Bash
scripts in a child process and returns stdout, stderr, and the exit code.

API
---
GET  /health
POST /execute
     {"language": "python|node|bash", "code": "...",
      "env": {"NAME": "value"}, "timeoutSeconds": 30}

Every execution is bounded by a timeout, an output cap, and a concurrency
limit. The container limits in docker-compose.yml are the primary resource
guard; this service adds request validation and process cleanup.

This service executes untrusted code. It is not a hardened sandbox on its own.
Run it on a private network, keep RUNNER_TOKEN set, and use a dedicated
VM/microVM or gVisor/Firecracker if the code is genuinely hostile.
"""

from __future__ import annotations

import hmac
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

MAX_BODY_BYTES = 2 * 1024 * 1024
MAX_CODE_BYTES = 256 * 1024
MAX_OUTPUT_BYTES = 1024 * 1024
MAX_TIMEOUT_SECONDS = 120
DEFAULT_TIMEOUT_SECONDS = 30
MAX_CONCURRENCY = max(1, int(os.environ.get("RUNNER_MAX_CONCURRENCY", "4")))
MAX_ENV_VARS = 64
MAX_ENV_BYTES = 16 * 1024

TOKEN = os.environ.get("RUNNER_TOKEN", "").strip()
ALLOW_UNAUTHENTICATED = os.environ.get("RUNNER_ALLOW_UNAUTHENTICATED") == "1"
HOST = os.environ.get("RUNNER_HOST", "0.0.0.0")
PORT = int(os.environ.get("RUNNER_PORT", "8080"))

_ENV_KEY = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_slots = threading.BoundedSemaphore(MAX_CONCURRENCY)


def _resolve_commands() -> dict[str, list[str]]:
    """Resolve interpreters once so a request cannot alter PATH lookup."""
    python = sys.executable
    node = shutil.which("node")
    bash = shutil.which("bash")

    # On Windows, C:\Windows\System32\bash.exe is the WSL launcher and will
    # not run the script against the host filesystem. Prefer Git Bash.
    if os.name == "nt" and bash and "system32" in bash.lower():
        bash = None
        for candidate in (
            r"C:\Program Files\Git\bin\bash.exe",
            r"C:\Program Files\Git\usr\bin\bash.exe",
        ):
            if os.path.exists(candidate):
                bash = candidate
                break

    missing = [
        name
        for name, path in (("python", python), ("node", node), ("bash", bash))
        if not path
    ]
    if missing:
        raise SystemExit(f"Missing required interpreter(s): {', '.join(missing)}")

    return {
        "python": [python, "-u"],
        "node": [node],
        "bash": [bash],
    }


LANGUAGES = _resolve_commands()
_EXTENSIONS = {"python": "py", "node": "js", "bash": "sh"}


class ValidationError(ValueError):
    """Request is well-formed JSON but cannot be executed."""


def _read_json(handler: BaseHTTPRequestHandler) -> dict:
    if handler.headers.get("Transfer-Encoding"):
        raise ValidationError("Chunked request bodies are not supported.")
    raw_length = handler.headers.get("Content-Length")
    if raw_length is None:
        raise ValidationError("Content-Length is required.")
    try:
        length = int(raw_length)
    except ValueError as exc:
        raise ValidationError("Invalid Content-Length.") from exc

    if length <= 0:
        raise ValidationError("Request body is empty.")
    if length > MAX_BODY_BYTES:
        raise ValidationError(f"Request body exceeds {MAX_BODY_BYTES} bytes.")

    body = handler.rfile.read(length)
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValidationError("Request body must be UTF-8 JSON.") from exc
    if not isinstance(payload, dict):
        raise ValidationError("Request body must be a JSON object.")
    return payload


def _validated_env(raw: object) -> dict[str, str]:
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        raise ValidationError('"env" must be an object of string values.')
    if len(raw) > MAX_ENV_VARS:
        raise ValidationError(f'"env" may contain at most {MAX_ENV_VARS} entries.')

    total = 0
    parsed: dict[str, str] = {}
    for key, value in raw.items():
        if not isinstance(key, str) or not isinstance(value, str):
            raise ValidationError('"env" keys and values must be strings.')
        if not _ENV_KEY.match(key):
            raise ValidationError(f'Invalid environment variable name: "{key}".')
        if "\x00" in key or "\x00" in value:
            raise ValidationError("Environment variables may not contain NUL bytes.")
        total += len(key.encode("utf-8")) + len(value.encode("utf-8"))
        parsed[key] = value

    if total > MAX_ENV_BYTES:
        raise ValidationError(f'"env" exceeds {MAX_ENV_BYTES} bytes.')
    return parsed


def _validate(payload: dict) -> tuple[str, str, dict[str, str], int]:
    language = payload.get("language")
    if not isinstance(language, str) or language not in LANGUAGES:
        raise ValidationError(
            f'"language" must be one of: {", ".join(sorted(LANGUAGES))}.'
        )

    code = payload.get("code")
    if not isinstance(code, str) or not code.strip():
        raise ValidationError('"code" must be a non-empty string.')
    if len(code.encode("utf-8")) > MAX_CODE_BYTES:
        raise ValidationError(f'"code" exceeds {MAX_CODE_BYTES} bytes.')

    timeout = payload.get("timeoutSeconds", DEFAULT_TIMEOUT_SECONDS)
    if isinstance(timeout, bool) or not isinstance(timeout, int):
        raise ValidationError('"timeoutSeconds" must be an integer.')
    if timeout < 1 or timeout > MAX_TIMEOUT_SECONDS:
        raise ValidationError(
            f'"timeoutSeconds" must be between 1 and {MAX_TIMEOUT_SECONDS}.'
        )

    return language, code, _validated_env(payload.get("env")), timeout


def _cap_output(raw: bytes) -> tuple[str, bool]:
    truncated = len(raw) > MAX_OUTPUT_BYTES
    text = raw[:MAX_OUTPUT_BYTES].decode("utf-8", errors="replace")
    if truncated:
        text += "\n[output truncated by runner]"
    return text, truncated


def _kill_process_tree(process: subprocess.Popen) -> None:
    """Kill the process and any children, portably."""
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(process.pid)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=5,
        )
        return

    try:
        os.killpg(os.getpgid(process.pid), signal.SIGKILL)
    except ProcessLookupError:
        pass


def execute(
    language: str,
    code: str,
    env: dict[str, str],
    timeout_seconds: int,
) -> dict:
    """Run one script and return the runner response payload."""
    started = time.monotonic()

    with tempfile.TemporaryDirectory(prefix="harness-run-") as work_dir:
        script_path = os.path.join(work_dir, f"script.{_EXTENSIONS[language]}")
        with open(script_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(code)

        child_env = {
            "PATH": os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
            "HOME": work_dir,
            "TMPDIR": work_dir,
            "TMP": work_dir,
            "TEMP": work_dir,
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "PYTHONDONTWRITEBYTECODE": "1",
            "PYTHONUNBUFFERED": "1",
        }
        # Node's crypto and Windows DLL loading rely on these on Windows.
        for key in (
            "SystemRoot",
            "WINDIR",
            "ComSpec",
            "PROCESSOR_ARCHITECTURE",
            "NUMBER_OF_PROCESSORS",
            "USERPROFILE",
            "APPDATA",
            "LOCALAPPDATA",
        ):
            if key in os.environ:
                child_env[key] = os.environ[key]
        child_env.update(env)

        process = subprocess.Popen(
            [*LANGUAGES[language], script_path],
            cwd=work_dir,
            env=child_env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )

        timed_out = False
        try:
            stdout_raw, stderr_raw = process.communicate(timeout=timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            _kill_process_tree(process)
            stdout_raw, stderr_raw = process.communicate()

        stdout, stdout_truncated = _cap_output(stdout_raw or b"")
        stderr, stderr_truncated = _cap_output(stderr_raw or b"")
        elapsed_ms = int((time.monotonic() - started) * 1000)

        if timed_out:
            stderr += f"\n[runner killed the process after {timeout_seconds}s]"

        return {
            "exitCode": process.returncode if process.returncode is not None else -1,
            "stdout": stdout,
            "stderr": stderr,
            "executionTimeMs": elapsed_ms,
            "timedOut": timed_out,
            "stdoutTruncated": stdout_truncated,
            "stderrTruncated": stderr_truncated,
        }


class RunnerHandler(BaseHTTPRequestHandler):
    server_version = "HarnessRunner/1.0"
    sys_version = ""
    protocol_version = "HTTP/1.1"

    def setup(self) -> None:
        super().setup()
        # Bound request read time so an idle connection cannot hold a slot.
        self.connection.settimeout(30)

    def log_message(self, fmt: str, *args) -> None:
        sys.stdout.write(
            f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} "
            f"{self.address_string()} {fmt % args}\n"
        )
        sys.stdout.flush()

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(body)

    def _authorized(self) -> bool:
        if not TOKEN:
            return ALLOW_UNAUTHENTICATED
        header = self.headers.get("Authorization", "")
        scheme, _, supplied = header.partition(" ")
        if scheme.lower() != "bearer" or not supplied:
            return False
        return hmac.compare_digest(supplied.strip(), TOKEN)

    def do_GET(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/health":
            self._send_json(404, {"error": "Not found."})
            return
        self._send_json(
            200,
            {
                "status": "ok",
                "languages": sorted(LANGUAGES),
                "maxTimeoutSeconds": MAX_TIMEOUT_SECONDS,
                "authRequired": bool(TOKEN),
            },
        )

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/execute":
            self._send_json(404, {"error": "Not found."})
            return

        if not self._authorized():
            self._send_json(
                401,
                {"error": "Unauthorized. Send an Authorization: Bearer token."},
            )
            return

        if not _slots.acquire(timeout=5):
            self._send_json(429, {"error": "Runner is at capacity. Retry shortly."})
            return

        try:
            payload = _read_json(self)
            language, code, env, timeout_seconds = _validate(payload)
            result = execute(language, code, env, timeout_seconds)
            self._send_json(200, result)
        except ValidationError as exc:
            self._send_json(400, {"error": str(exc)})
        except Exception:
            traceback.print_exc()
            self._send_json(500, {"error": "Runner failed to execute the script."})
        finally:
            _slots.release()


class RunnerServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main() -> None:
    if not TOKEN and not ALLOW_UNAUTHENTICATED:
        raise SystemExit(
            "RUNNER_TOKEN is required. Set it, or set "
            "RUNNER_ALLOW_UNAUTHENTICATED=1 for local development only."
        )

    if not TOKEN:
        print(
            "WARNING: RUNNER_TOKEN is not set. The runner accepts unauthenticated "
            "execution because RUNNER_ALLOW_UNAUTHENTICATED=1.",
            file=sys.stderr,
        )

    server = RunnerServer((HOST, PORT), RunnerHandler)
    print(
        f"Harness runner listening on http://{HOST}:{PORT} "
        f"(languages={','.join(sorted(LANGUAGES))}, "
        f"concurrency={MAX_CONCURRENCY}, auth={'on' if TOKEN else 'off'})"
    )

    def shutdown(_signum, _frame) -> None:
        print("Shutting down runner.")
        # shutdown() must run off the serve_forever thread.
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    server.serve_forever()
    server.server_close()


if __name__ == "__main__":
    main()
