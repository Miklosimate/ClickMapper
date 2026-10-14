# Shared by build-app.sh and package-app.sh; source from the repository root.
CLICKMAPPER_VERSION=${CLICKMAPPER_VERSION:-0.1.0}
if ! printf '%s\n' "$CLICKMAPPER_VERSION" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s\n' 'CLICKMAPPER_VERSION must be a numeric version such as 0.1.0.' >&2
    exit 2
fi
export CLICKMAPPER_VERSION
