# Harmony phone control: implementation and platform evidence

Baseline: dsh-Go `a9877420ab9aee121134faf01b6a92a39ce0b05b`, Android `phone/PhoneToolCatalog.kt`, `SafetyGate.kt`, `PhoneBridge.kt`. The 13-tool schema is retained with AGPL provenance in `runtime/phone-catalog.json`, `PHONE_SOURCE.md` and `PHONE_UPSTREAM_LICENSE.txt`.

The implemented path is the real DSH agent preset → caller/turn-bound queue → authenticated loopback control → native confirmation → private file RPC → actual AccessibilityExtensionAbility → native result → model. Model tools default off. Every operation requires confirmation, expires after 30 seconds (handoff 10 minutes), and supports cancellation. Stop disables further calls. Acknowledging an SDK operation never claims its business task succeeded. Usage counts the first approved execution in each committed engine session/turn, not each tool call.

## Implemented tools

| Tool | Native path and checks |
|---|---|
| screen | Actual root/attributes/actions, bounded 128-node tree with parent IDs and rectangles. Password text is masked. `image:true` requests actual permission/capture; before/after trees must match. PNG is scaled and bounded, validated by the actual attachment store, then rendered as a model image block. Failure returns an explicit image error. |
| tap, type | Fresh same-bundle/snapshot verification, actual `performAction(click/longClick/setText)`. Password, verification-code and payment inputs are refused. Automatic submit is unavailable as explained below. |
| scroll | Vertical node actions; horizontal public `injectGesture` inside the validated scrollable node rectangle. |
| collect | Revalidates the original list before reading, collects descendants, scrolls/reads the same list, deduplicates text, stops at match/no-new-items/page/size limit, cancellation or changed app. Partial results are labelled. |
| key | Public accessibility actions back/home/recentTask/notificationCenter, fresh screen and protected-page checks. |
| tap_xy | Only after a screenshot was actually validated and returned to the same committed task. One coordinate attempt per screenshot, 30-second lifetime, bounds/rotation/application/tree checks. Image coordinates map to the captured device viewport, then actual GesturePath/GesturePoint/injectGesture performs tap/long/swipe. |
| open | Public `UIAbilityContext.openLink` for validated app links; executable/file/self callback schemes and URL credentials are refused. Package/name discovery needs a privileged lookup. |
| clipboard | Actual pasteboard. Reads require the OS PasteButton gesture token, without declaring restricted READ_PASTEBOARD. Writes use setData. |
| notify | Actual notification authorization and publication. |
| intent | Actual makeCall dialer, CalendarManager.editEvent system editor, ShareKit chooser, navigation type picker, documented SMS draft Want, WLAN and this app's notification settings. NFC settings requires API 24; mobile-network/display/sound pages require API 26. Calendar cancellation is returned, not counted as creation. |
| handoff | Explicit continue/stop, bounded to 10 minutes. |
| apps | Explicit unsupported result with the concrete system/enterprise permission reason below; no fabricated installed-app list. |

Accessibility operations require an actual system service connection. A supported user activation entry for an ordinary debug-signed HAP has not been established on the tested API 26 commercial HarmonyOS phone. The settings inspection reached the bottom of the accessibility page without finding a third-party services entry; activation and cross-app operations have not passed device acceptance. One-time system-authorized screen capture and text recognition remain available independently.

The [Huawei English API documentation](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-application-accessibilityextensionability/) states that the connection/event/key callback capabilities are no longer available from API 12; the [context documentation](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-inner-application-accessibilityextensioncontext/) carries the same notice for legacy window-tree/action APIs. The Chinese callback page marks deprecation without that explicit removal sentence. SDK 26.0.0.105 retains the types, but its `hms/ets/api/device-define/api-version/AccessibilityKit.json` method entries for `onConnect`, `getWindowRootElement` and `injectGestureSync` identify OpenHarmony and mark phone support and deprecation both at API 12. Compilation is not evidence of activation on this commercial device.

OpenHarmony accessibility source at `3ffbe3513f07cb1df2bd98d74089582dff5eb33a` retains legacy action implementations, but that does not establish commercial HarmonyOS phone availability. Huawei's [installed/downloaded-services settings instructions](https://consumer.huawei.com/cn/support/content/zh-cn00410039/) explicitly apply only to HarmonyOS 4.X and earlier. The exact OEM registration/filtering cause on this phone is still unknown; this finding does not assert permanent unavailability on every HarmonyOS device. No restricted permission or forced service activation substitutes for supported user authorization.

Deny rules are reread from an atomic private policy file before each extension operation. Settings, permission/package-installer/system UI and DSH Go itself are not writable. Requests/responses are 0600, expire, and are removed after consumption/cancel. No screen/input text is logged. An already executing OS operation cannot be undone by cancellation.

## Exact platform boundaries

The installed SDK's `openharmony/toolchains/lib/PermissionDefinitions.json` declares:

| Permission/API | SDK restriction |
|---|---|
| GET_BUNDLE_INFO_PRIVILEGED / getLaunchWantForBundleSync | system_basic/system_grant; ordinary phone app cannot discover another app's launch Want. |
| GET_INSTALLED_BUNDLE_LIST | system_basic, availableType SYSTEM. |
| ENTERPRISE_GET_INSTALLED_BUNDLE_LIST | system_basic, enterprise, 2in1 (API 26). |
| ACCESS_VIRTUAL_SCREEN / display.createVirtualScreen | system_basic/system_grant. No Android-style invisible background display is created. |
| CONTROL_DEVICE / inputEventClient keyboard injection | system_basic/manual settings, 2in1 only. The public legacy node action list does not expose IME Enter, so `type(submit:true)` is explicitly refused. |
| SYSTEM_FLOAT_WINDOW / WindowType.TYPE_FLOAT | system_basic/system_grant plus controlled distribution. Official guidance permits approved scenarios on 2in1, not this ordinary phone target. No unreachable pet overlay adapter or fake enabled switch is shipped. |

Other Android settings pages and Android AlarmClock/timer intents have no corresponding public route in the inspected SDK. Harmony reminder-agent alarm/timer capability is entitlement-controlled on phones; it is not silently replaced with a different reminder. `settings(app_notifications, app=other)` cannot call this-app-only notification settings on behalf of another application. Users can use handoff for these requests. Android Shizuku/Sui/root/self-ADB channels are not Harmony APIs.

Public screenshot capture supports phone from API 21 and tablet/2in1 from API 14. Separate manual capture/OCR uses CoreVision; pixels are released on errors/cancel and ownership transfers only on success. Screenshots reach the model only through an explicitly approved model request. All optional UI/SDK failures remain observable errors.

## Host evidence

- `tests/check-phone.sh`: pure policy, collector, usage dedup; actual ArkTS extension/private file bridge against synthetic OS objects, including real file I/O, node actions, global key, gesture, changed screen/password/deny/replay/cancel checks; SDK intent adapter and screenshot geometry/cleanup tests.
- `node --test tests/phone-service.test.mjs`: authenticated endpoint, opt-in, caller/task isolation, one-use picture mapping, abort/stop, unsupported boundaries.
- `node tests/phone-live.mjs <runtime>`: actual jitless/no-addons DSH preset contains 13 tools; synthetic model calls screen(image:true), real attachment validation/storage/rendering sends an image to the provider, the same turn requests tap_xy, native fixture completion resumes the model. A later turn cancellation clears the queue. Model/native OS completion are synthetic; no device success is claimed.
- Unified hvigor verifies ArkTS/SDK/C++ compilation. No device test occurs before host verification completes.

Primary references checked 2026-11-16:

- [Accessibility context](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-inner-application-accessibilityextensioncontext)
- [Accessibility actions](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-accessibility/)
- [Screenshot](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-screenshot/)
- [System application routes](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/system-app-startup/)
- [Navigation type picker](https://developer.huawei.com/consumer/en/doc/harmonyos-guides-V14/start-navigation-apps-V14/)
- [SMS draft guidance](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/telephony-sms-V13/)
- [Reminder entitlement](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/agent-powered-reminder/)
- [Controlled permissions](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/restricted-permissions/)
- [Floating window device restrictions](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V5/application-window-stage-V5/)

Local declaration files: `application/AccessibilityExtensionContext.d.ts`, `@ohos.accessibility.GesturePath.d.ts`, `@ohos.accessibility.GesturePoint.d.ts`, `@ohos.bundle.bundleManager.d.ts`, `@ohos.display.d.ts`, `@ohos.settings.d.ts`, `@ohos.multimodalInput.inputEventClient.d.ts`, `@ohos.calendarManager.d.ts`, and HMS `@hms.collaboration.systemShare.d.ts`.
