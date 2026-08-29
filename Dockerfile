# ---------- Stage 1: build the frontend into static assets ----------
FROM node:22-slim AS frontend-build

WORKDIR /tmp/frontend

# Install pnpm via corepack (uses the version pinned in package.json)
RUN corepack enable

# Copy manifests first for layer caching
COPY frontend/package.json frontend/pnpm-lock.yaml ./

# Install production + dev dependencies (dev deps are needed for `pnpm build`)
RUN pnpm install --frozen-lockfile

# Copy the rest and build
COPY frontend/ ./
RUN pnpm build

# ---------- Stage 2: runtime image (Python backend + nginx) ----------
FROM python:3.12.3-slim-bookworm

ENV POETRY_VERSION 1.8.0
ENV BACKEND_PORT 9000

# Install nginx (hosts the frontend and reverse-proxies API calls)
RUN apt-get update && apt-get install -y --no-install-recommends nginx \
    && rm -rf /var/lib/apt/lists/*

# Install system dependencies
RUN pip install "poetry==$POETRY_VERSION"

# Set work directory
WORKDIR /app

# Copy only requirements to cache them in docker layer
COPY backend/poetry.lock backend/pyproject.toml /app/

# Disable the creation of virtual environments
RUN poetry config virtualenvs.create false

# Install dependencies
RUN poetry install

# Install Chromium and Linux libraries needed by Playwright screenshot previews.
RUN playwright install --with-deps chromium

# Copy the backend source (unchanged)
COPY backend/ /app/

# Copy the built frontend (served by nginx)
COPY --from=frontend-build /tmp/frontend/dist /app/dist

# Copy nginx config and the startup script
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# nginx is the public entry point
EXPOSE 7001

CMD ["/entrypoint.sh"]