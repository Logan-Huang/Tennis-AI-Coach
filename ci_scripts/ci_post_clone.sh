#!/bin/sh
#
# Xcode Cloud: write the AppsFlyer dev key, which stays out of this public
# repository, from the workflow's APPSFLYER_DEV_KEY secret. A build without it
# still succeeds; the app just never starts AppsFlyer.

set -e

KEYS="$CI_PRIMARY_REPOSITORY_PATH/Tennis AI Coach/AppsFlyerKeys.plist"

if [ -z "$APPSFLYER_DEV_KEY" ]; then
    echo "warning: APPSFLYER_DEV_KEY is not set, so this build won't report installs to AppsFlyer."
    exit 0
fi

rm -f "$KEYS"
/usr/libexec/PlistBuddy -c "Add :DevKey string $APPSFLYER_DEV_KEY" "$KEYS" > /dev/null
echo "Wrote AppsFlyerKeys.plist"
