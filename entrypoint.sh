#!/bin/sh
set -e

# Start the Python backend in the background on the internal port
poetry run uvicorn main:app \
    --host 127.0.0.1 \
    --port "${BACKEND_PORT:-9000}" &

# Run nginx in the foreground (keeps the container alive), which serves the
# built frontend and reverse-proxies API/WebSocket traffic to the backend.
exec nginx -g 'daemon off;'