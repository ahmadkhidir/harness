# Harness External Runner

A small HTTP service that executes Python, Node.js, and Bash for the Harness app's `execute_script` command.

The mobile app never runs arbitrary code in its own process. It sends the script to a runner you host; this container is that runner.

> **Danger:** this service executes untrusted code by design. A Docker container is a deployment boundary, not a hardened security boundary. Do not expose it directly to the public internet. Run it on a private network behind an authenticating reverse proxy, and use a dedicated VM, gVisor, or Firecracker if the scripts may be hostile.

---

## What It Provides

- `POST /execute` for Python, Node.js, and Bash.
- `GET /health` for readiness checks.
- Bearer-token authentication.
- Per-request timeout, code-size, body-size, and output caps.
- A concurrency limit so one caller cannot exhaust the container.
- Process-group kill on timeout, so child processes do not survive the request.
- A non-root container user, read-only root filesystem, dropped capabilities, a tmpfs `/tmp`, and pid/memory/CPU limits in Compose.

---

## Quick Start

```bash
cd runner
cp .env.example .env

# Set a long random token; do not ship the example value.
# openssl rand -hex 32
# then edit RUNNER_TOKEN in .env

docker compose up --build -d
```

Check it:

```bash
curl http://localhost:8080/health
```

Run a script:

```bash
curl -s http://localhost:8080/execute \
  -H "Authorization: Bearer $RUNNER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "code": "print(2 + 2)",
    "timeoutSeconds": 10
  }'
```

Expected response:

```json
{
  "exitCode": 0,
  "stdout": "4\n",
  "stderr": "",
  "executionTimeMs": 42,
  "timedOut": false,
  "stdoutTruncated": false,
  "stderrTruncated": false
}
```

In Harness **Settings → External Bridges → External Runner**, set:

- **Runner Endpoint:** `http://<host>:8080`
- **Runner Token:** the same value as `RUNNER_TOKEN`

Use HTTPS through a reverse proxy when the app and runner are not on the same trusted network.

---

## API

### `GET /health`

Unauthenticated. Returns readiness, supported languages, the timeout ceiling, and whether auth is enabled.

```json
{
  "status": "ok",
  "languages": ["bash", "node", "python"],
  "maxTimeoutSeconds": 120,
  "authRequired": true
}
```

### `POST /execute`

Requires `Authorization: Bearer <RUNNER_TOKEN>` when a token is configured.

Request:

```json
{
  "language": "python",
  "code": "print('hello')",
  "env": {"NAME": "value"},
  "timeoutSeconds": 30
}
```

| Field | Required | Rules |
|---|---|---|
| `language` | yes | `python`, `node`, or `bash` |
| `code` | yes | non-empty, up to 256 KB |
| `env` | no | object of string values, up to 64 entries / 16 KB |
| `timeoutSeconds` | no | integer 1–120, default 30 |

Response fields:

| Field | Meaning |
|---|---|
| `exitCode` | Process exit code; `-1` if unavailable |
| `stdout` | Captured standard output, capped at 1 MB |
| `stderr` | Captured standard error, capped at 1 MB |
| `executionTimeMs` | Wall-clock execution time |
| `timedOut` | Whether the runner killed the process |
| `stdoutTruncated` / `stderrTruncated` | Whether an output cap was hit |

Errors return a non-2xx status with `{"error": "..."}`:

- `400` invalid request
- `401` missing or wrong bearer token
- `404` unknown path
- `429` runner at capacity
- `500` execution infrastructure failure

---

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `RUNNER_TOKEN` | none | Bearer token. Required unless unauthenticated mode is explicitly enabled. |
| `RUNNER_ALLOW_UNAUTHENTICATED` | `0` | Set to `1` for local development only. Never use in a hosted deployment. |
| `RUNNER_HOST` | `0.0.0.0` | Bind address inside the container. |
| `RUNNER_PORT` | `8080` | Bind port inside the container. |
| `RUNNER_MAX_CONCURRENCY` | `4` | Maximum simultaneous executions. |

Limits are intentionally fixed in code: 2 MB request body, 256 KB code, 1 MB per output stream, 120 s maximum timeout.

---

## Hosting Notes

- Put the runner behind HTTPS and an authenticating proxy when it is reachable from outside the host.
- Keep the runner on a private network or VPN. Do not publish it to the open internet.
- Do not mount secrets, SSH keys, cloud credentials, or the Docker socket into the container.
- Do not mount the host filesystem. The tmpfs `/tmp` is the only writable location.
- Keep the image patched: rebuild after base-image or Node.js security updates.
- Rotate `RUNNER_TOKEN` if it is ever exposed.
- Apply ingress rate limits. The service limits concurrency, not request rate.
- If the code is genuinely untrusted, run the container inside a stronger sandbox such as gVisor or a microVM. Process-level limits and a container do not prevent kernel-level escape in the face of a container breakout.

---

## Local Development Without Docker

```bash
cd runner
export RUNNER_TOKEN=dev-token
export RUNNER_ALLOW_UNAUTHENTICATED=0
python3 server.py
```

Python 3.10+ and Node.js are required for all three language modes. Without `RUNNER_TOKEN`, the server exits unless `RUNNER_ALLOW_UNAUTHENTICATED=1` is set.
