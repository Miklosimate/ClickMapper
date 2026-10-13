#!/bin/sh
set -eu
# Only this app's Accessibility approval is reset; other apps are untouched.
/usr/bin/osascript -e 'if application id "local.clickmapper.diagnostic" is running then tell application id "local.clickmapper.diagnostic" to quit'
/usr/bin/tccutil reset Accessibility local.clickmapper.diagnostic
printf '%s\n' 'ClickMapper permission reset. Reopen the app, grant Accessibility access, then fully quit and reopen once more.'
