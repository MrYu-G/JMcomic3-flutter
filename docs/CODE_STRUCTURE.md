# Code ownership and maintenance

The Flutter application and embedded Rust library are independent repositories.
Keep backend source and generated FRB adapters in the backend repository. The
active application uses `MethodChannel('methods')`, Android JNI and the Windows
C ABI; it does not run a separate HTTP server.

The public frontend must contain no backend Rust source, Cargo manifests or FRB
backend adapters. Keep them in the private backend checkout. Compiled native
libraries are necessary app inputs and can still be reverse engineered; never
embed signing private keys or long-lived service credentials in them. Repository
checks reject backend-source paths and common credential files/token patterns.

## Flutter ownership

| Location | Responsibility |
| --- | --- |
| `lib/screens/` | Page state, navigation and user interaction |
| `lib/screens/components/` | Shared presentation, dialogs, feedback, file-picking/save actions and comic sorting choices |
| `lib/screens/components/login_form.dart` | Shared credential fields, validation, request state and input lifecycle |
| `lib/screens/components/login_agreement.dart` | Localized Terms of Use, login hint and one shared sheet for login and settings |
| `lib/screens/reader/` | Reader viewers, controls, visible-position calculation and information bar |
| `lib/basic/methods.dart` | Named backend calls, method-specific parameters and typed entities |
| `lib/basic/bridge/method_channel_transport.dart` | Native channel, string request/response envelope and operation timing |
| `lib/basic/bridge/response_cache.dart` | Bounded serialized-response caching, shared pending loads and invalidation ownership |
| `lib/basic/method_response_decoder.dart`, `entities.dart` | Existing wire-shape compatibility and typed data |
| `lib/basic/image_files.dart` | Image file resolution, validation, path/dimension caches and invalidation |
| `lib/basic/page_image_provider.dart`, `image_decode_targets.dart` | Flutter image identity/decoding/eviction and bounded decode sizing |
| `lib/basic/reader_image_session.dart`, `reader_image_queue.dart` | Reader lifetimes and bounded request scheduling |
| `lib/configs/`, `lib/l10n/` | Persisted preferences, theme, typography and translations |
| `scripts/build_common.ps1` | Shared backend checkout resolution and build-output path validation |

Import the concrete owner directly. The retired `commons.dart` mixed dialogs,
clipboard access, permissions, file operations and formatting; do not recreate
it as a catch-all barrel or utility module. A helper needing navigation,
`BuildContext` or toasts belongs with presentation. Image file/provider code
must not depend on screens. Text-input dialogs own and dispose their controllers
per route; clipboard actions use Flutter's platform API.

Keep serialized responses in caches and decode them for each caller so widgets
do not share mutable entities. Clearing a cache invalidates pending ownership:
an older request may finish for its original caller but cannot repopulate the
cache or remove a newer request. Account and route changes invalidate on both
sides of their asynchronous mutation. Preserve established stale-data policies
and strict errors for malformed envelopes.

Export selection is shared by completed and unfinished downloads. Keep their
distinct format execution paths: unfinished exports can include partial data,
while completed exports retain their existing format and rename behavior.

## Backend and packaging boundaries

Backend `rust/README.md` documents the router and private domain modules. Default
native builds omit the optional FRB runtime; migration/Cargokit consumers select
the `frb` Cargo feature explicitly. Do not remove compatibility parsing or
stored-data formats solely because their callers are less common.

Only declared application assets are bundled. Required ABI libraries are not
duplicate files: ARM32, ARM64 and emulator x86_64 serve different targets.
Single-ABI releases select that ABI explicitly. Package inspection checks the
archive's actual ABI directories, required native libraries, duplicate entries
and application assets, and reports measured bytes. Source line counts and
dependency counts do not establish final package savings.

See [BUILDING.md](BUILDING.md) for checks and native prerequisites and
[RELEASING.md](RELEASING.md) for artifact validation and repository-file policy.
Task plans, test images, screenshots and execution logs stay local. Tests
generate image fixtures at runtime; source control retains only product icons.
