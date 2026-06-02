#\!/usr/bin/env bash
WEB_DB="arcboxdemo"
if [[ \! "${WEB_DB}" =~ ^[a-z_][a-z0-9_]*$ ]]; then
    echo fail
fi
