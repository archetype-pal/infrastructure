#!/bin/sh
set -e

# Install gettext (contains envsubst) if not available
if ! command -v envsubst > /dev/null 2>&1; then
    apk add --no-cache gettext
fi

# Process the nginx template with environment variables
envsubst '${DOMAIN}' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf

# Start nginx
exec nginx -g 'daemon off;'
