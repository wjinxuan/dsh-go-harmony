`phone-catalog.json` is a mechanical extraction of all 13 tools, descriptions and
schemas in `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneToolCatalog.kt`
at dsh-Go commit `a9877420ab9aee121134faf01b6a92a39ce0b05b`.
https://github.com/ccch1mneyyy/dsh-Go/blob/a9877420ab9aee121134faf01b6a92a39ce0b05b/app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneToolCatalog.kt

The source repository is licensed AGPL-3.0; the full license is included as
`PHONE_UPSTREAM_LICENSE.txt`. The Harmony service/provider and native adapter
implement an independent authenticated control path. Unsupported tool operations
return an explicit failure before queueing; the fixed catalog never invents ready
state or changes according to permission state.
