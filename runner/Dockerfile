# syntax=docker/dockerfile:1

FROM node:22-bookworm-slim

# Python and Bash are required because the runner executes all three
# languages supported by the Harness runner contract.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        python3 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --uid 10001 --shell /usr/sbin/nologin runner

WORKDIR /app
COPY --chown=runner:runner server.py /app/server.py

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/tmp \
    RUNNER_HOST=0.0.0.0 \
    RUNNER_PORT=8080

USER runner
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)"

CMD ["python3", "/app/server.py"]
