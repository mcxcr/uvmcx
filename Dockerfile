# syntax=docker/dockerfile:1.7

FROM python:3.14-slim-bookworm AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_LINK_MODE=copy

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

# Install uv and place the **real binary** into /usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    install -m 0755 /root/.local/bin/uv /usr/local/bin/uv

WORKDIR /app

# Builder (has compilers)
FROM base AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential pkg-config \
    libjpeg62-turbo-dev zlib1g-dev libpng-dev libffi-dev git && \
    rm -rf /var/lib/apt/lists/*

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY app ./app

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

RUN python -m compileall -q /usr/local/lib/python3.14

########################
# Runtime (slim)
########################
FROM python:3.14-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libjpeg62-turbo zlib1g libpng16-16 && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Bring in Python libs & console scripts
COPY --from=builder /usr/local/lib/python3.14 /usr/local/lib/python3.14
COPY --from=builder /usr/local/bin /usr/local/bin
# Ensure uv binary is present (not a broken symlink)
# COPY --from=builder /usr/local/bin/uv /usr/local/bin/uv

# Bring in your app code
COPY --from=builder /app /app

EXPOSE 8005

# Prod suggestion:
# CMD ["gunicorn", "-b", "0.0.0.0:8000", "app.wsgi:application"]

# Dev default:
CMD ["uv", "run", "python", "app/manage.py", "runserver", "0.0.0.0:8005"]