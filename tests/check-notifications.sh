#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/ui" "$test_dir/dsh"
cp "$project_dir/entry/src/main/ets/dsh/DshWire.ets" "$test_dir/dsh/DshWire.ts"
sed "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|g" "$project_dir/entry/src/main/ets/ui/NotificationData.ets" > "$test_dir/ui/NotificationData.ts"
sed -e "s|'./SettingsLocale'|'../settings-locale-fixture.mjs'|" -e "s|'@kit.AbilityKit'|'../notification-fixture.mjs'|" -e "s|'@kit.ArkData'|'../notification-fixture.mjs'|" \
 -e '/^import.*BusinessError.*$/d' \
 -e "s|'@kit.NotificationKit'|'../notification-fixture.mjs'|" -e "s|DshClient, DshSubscription|DshClient|" \
 -e "s|'../dsh/DshClient'|'../notification-fixture.mjs'|" -e "s|string, WireObject|string|" \
 -e "s|'../dsh/DshWire'|'../dsh/DshWire.ts'|" -e 's|ChatNotification, NotificationPreferences, ||' \
 -e "s|'./BackgroundCompletion'|'./BackgroundCompletion.ts'|" -e "s|'./NotificationData'|'./NotificationData.ts'|" "$project_dir/entry/src/main/ets/ui/ChatNotifications.ets" > "$test_dir/ui/ChatNotifications.ts"
if [ -f "$project_dir/entry/src/main/ets/ui/BackgroundCompletion.ets" ]; then
 sed -e "s|'@kit.BackgroundTasksKit'|'../notification-fixture.mjs'|" -e "s|'@kit.PerformanceAnalysisKit'|'../notification-fixture.mjs'|" -e '/^import.*BusinessError.*$/d' "$project_dir/entry/src/main/ets/ui/BackgroundCompletion.ets" > "$test_dir/ui/BackgroundCompletion.ts"
fi
cp "$project_dir/tests/settings-locale-fixture.mjs" "$project_dir/tests/notification-fixture.mjs" "$project_dir/tests/notifications.test.mjs" "$project_dir/tests/notification-background.test.mjs" "$test_dir/"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/notifications.test.mjs" "$project_dir"
node --disable-warning=ExperimentalWarning --experimental-strip-types "$test_dir/notification-background.test.mjs" "$project_dir"
