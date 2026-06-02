#\!/usr/bin/env bash
WEB_DB="arcboxdemo"
if [[ \! "${WEB_DB}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
    echo "WEB_DB must be a lowercase PostgreSQL identifier" >&2
    exit 1
fi
echo "Valid"
