# Implementation Plan — First-Run Onboarding (seed the coach's memory)

**Status:** ready to execute. Self-contained — no other docs needed. Backend is live; no server changes.
**Goal:** after login, a new athlete sees a skippable 4-question flow (goal / 30-min check / injuries / availability), preceded by the HealthKit permission ask. Each answer becomes a plan note (`conversationId: "ios-onboarding"`) via the existing training API. Skipping everything must leave the app fully functional and write nothing.

Verified against the backend source (`aderaaij/training-api`, `backend/app/routes/plan_notes.py` + `schemas/plan_note.py`) — the wire contract in §2 is exact, not aspirational.

---

## 0. Codebase facts (verified 2026-07-18 — trust these)

- Project uses **folder-synced groups** (`PBXFileSystemSynchronizedRootGroup`): any `.swift` file dropped into `OpenHealthSync/OpenHealthSync/` is auto-included in the target. **No pbxproj edits.** Do NOT put new source files at repo root.
- Root branching lives in `appRoot` in `OpenHealthSync/OpenHealthSyncApp.swift:71-154`: `!session.isAuthenticated` → `LoginView`, else `MainTabView`. Post-login work (HealthKit auth + first `syncMetrics()`, plan loading, observers) runs in the `.task` at `:113-134`; notification permission in `.onAppear` at `:107-111`.
- HealthKit: `HealthMetricsSyncer` (actor) — `requestAuthorization()` at `HealthMetricsSyncer.swift:51-60` (read types at `:20-43`), `syncMetrics()` at `:64-84`. Gated by `@AppStorage("healthMetricsSyncEnabled")`.
- API idiom: `actor WorkoutAPIClient` (`WorkoutAPIClient.swift`), raw `URLRequest` per method, bearer header set manually (`request.setValue("Bearer \(apiKey)", ...)`), `try validate(response)` after every call (posts `.trainingAPIUnauthorized` on 401 → app lands on login automatically — QA item "401 → re-auth path" comes for free). Per-call `JSONDecoder()` with explicit `CodingKeys` on models — **no** `.convertFromSnakeCase`. Copy `fetchQueue()` / `syncInventory(_:)` (`WorkoutAPIClient.swift:156-186`) as templates.
- State pattern: `ObservableObject` + `@StateObject`/`@ObservedObject` (MVVM-lite). No `@Observable` macro anywhere — don't introduce it.
- Design system: `enum LB` in `Theme.swift` — `LB.bg/surface/accent(0xFF6A3D)/textPrimary…textFaint`, radii `LB.rCard/rHero/rPill`, fonts `.lbDisplay/.lbMono/.lbBody`, components `.lbCard()`, `LBSectionHeader`, `LBStatusChip`, `LBSegmentToggle`, helpers `.lbScreen()`. App is forced dark. Build a **branded custom flow** (like `MainTabView`'s styling), not a `Form` — this is a first-impression screen.
- `ServerConfigView.Mode.onboarding` exists but is dead/preview-only. Ignore it (don't wire it in, don't delete it).
- There is currently **no first-run flag** of any kind.

---

## 1. Files

**New — create in `OpenHealthSync/OpenHealthSync/`:**

| File | Contents |
|---|---|
| `PlanNoteModels.swift` | `PlanNote` (response), `PlanNoteCreate`, `PlanNoteUpdate` structs |
| `OnboardingView.swift` | The whole flow: `OnboardingView`, step subviews, `OnboardingModel: ObservableObject` |

**Modified:**

| File | Change |
|---|---|
| `WorkoutAPIClient.swift` | + `fetchPlanNotes(conversationId:)`, `createPlanNote(_:)`, `updatePlanNote(id:_:)` |
| `OpenHealthSyncApp.swift` | onboarding gate in `appRoot` + gate the HK-auth block in the post-login `.task` |
| `HealthMetricsSyncer.swift` | add `.dateOfBirth` characteristic to read types; small `dateOfBirthComponents()` accessor |
| `TrainingTabView.swift` | (optional polish, §7) one dismissible "tell your coach" nudge card |

---

## 2. Wire contract (verified against backend source — copy exactly)

Base path `api/plan-notes` on the existing `baseURL`. Bearer token on every call. Casing is **mixed** and intentional:

- **Request bodies** (POST/PATCH): camelCase aliases — `conversationId`, `expiresAt`, `planId`. Other keys (`kind`, `summary`, `body`, `importance`) are single words.
- **Query params**: snake_case — `GET api/plan-notes?conversation_id=ios-onboarding&limit=50`.
- **Responses** (`PlanNoteRead`): `id` (UUID string), `planId`, `kind`, `summary`, `body`, `importance`, `conversationId`, `expiresAt` are camelCase, but `created_at`/`updated_at` are snake_case.

**Date-decoding trap:** backend datetimes carry fractional seconds, which `JSONDecoder.dateDecodingStrategy = .iso8601` cannot parse. We don't need any dates → **omit `created_at`/`updated_at`/`expiresAt` from the Swift response model entirely** (Codable ignores unknown keys). Model only what we use:

```swift
struct PlanNote: Codable, Identifiable {
    let id: String            // UUID string
    let kind: String
    let summary: String
    let body: String?
    let importance: Int
    let conversationId: String?
    // camelCase keys throughout the fields we decode → no CodingKeys needed,
    // but keep an explicit CodingKeys enum anyway to match codebase idiom.
}

struct PlanNoteCreate: Encodable {
    let kind: String          // "decision" | "preference" | "constraint" | "observation"
    let summary: String       // server caps at 280 chars — enforce client-side
    let body: String?
    let importance: Int       // 1...3
    let conversationId: String // always "ios-onboarding" here
    // deliberately no planId / expiresAt — global, non-expiring notes
}

struct PlanNoteUpdate: Encodable {
    let summary: String
    let body: String?
    // PATCH is partial: only send what changes (kind/importance stay as created)
}
```

Endpoints used: `POST api/plan-notes` (201 → `PlanNote`), `GET api/plan-notes?conversation_id=…&limit=50` (→ `[PlanNote]`), `PATCH api/plan-notes/{id}` (→ `PlanNote`). Never DELETE.

**API client methods** — follow the existing idiom exactly (manual `URLRequest`, bearer header, `try validate(response)`, fresh `JSONDecoder()` — plain, no date strategy needed here). For the GET, build the query with `URLComponents` (snake_case params).

---

## 3. Gate & flow wiring (`OpenHealthSyncApp.swift`)

1. Add `@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false` to `LoopbackApp`.
2. In `appRoot`, branch: `!isAuthenticated` → login (unchanged); `isAuthenticated && !hasCompletedOnboarding` → `OnboardingView(...)`; else → `MainTabView` (unchanged). Existing users will see it once post-update — acceptable, everything is skippable.
3. **HealthKit ordering (QA item):** the post-login `.task` currently fires `requestAuthorization()` immediately, which would throw the system sheet over the onboarding intro. Gate the HealthKit-auth/first-sync block inside that `.task` on `hasCompletedOnboarding`. Onboarding owns the request instead (§4, step 0). Verify the rest of the `.task` (plan loading, schedule auth, observers) still runs during onboarding — it should; only skip the HK block.
4. **After onboarding flips the flag**, the root swaps to `MainTabView`, but the `.task` will NOT re-run (same view identity). So `OnboardingView`'s completion path must itself kick off `healthMetricsSyncer.syncMetrics()` + `BackgroundSyncManager` setup — i.e. whatever the gated block would have done. Cleanest: extract that block into a private `func startHealthPipeline() async` on `LoopbackApp` (or a closure passed to `OnboardingView`) and call it from both places. Double-calling `requestAuthorization()` is harmless (system sheet shows once ever), so idempotency is fine.
5. Pass `OnboardingView` what it needs: `healthMetricsSyncer`, `apiClient` (however `WorkoutAPIClient` is reached today — check how `SessionStore`/managers hold it and mirror that), and an `onFinished: () -> Void` that sets `hasCompletedOnboarding = true`.

---

## 4. The flow (`OnboardingView.swift`)

One `OnboardingModel: ObservableObject` holds all answers + step index. Steps advance via a bottom primary button (accent-filled, `LB.rPill`) with a quiet "Skip" (`LB.textTertiary`) top-trailing on every question screen. Progress dots under the header. All screens on `LB.bg`, `.lbScreen()`, generous `.lbDisplay` titles. Match the polished `MainTabView`/card idiom, not `Form`.

**Step 0 — Welcome + HealthKit.** Brand moment ("Loopback", one line: "Your training history is your coach's memory."). Button "Connect Apple Health" → `await healthMetricsSyncer.requestAuthorization()`, then fire `syncMetrics()` in a detached background `Task` (don't await — sync runs while they answer), advance. "Skip" advances without requesting. Also attempt DOB read here (§5).

**Step A — Goal.** *"What are you working toward?"* Single-select list of tappable cards:

| Label | `playbookValue` |
|---|---|
| My first 5K — I'm new to running (or coming back from nothing) | `first_5k` |
| A faster 5K | `5k` |
| A 10K | `10k` |
| A half marathon | `half_marathon` |
| A marathon | `marathon` |
| Just running regularly — no race | `general_fitness` |

If a **race** goal is selected (anything except `general_fitness`), reveal an optional "Racing on a specific date?" toggle + graphical `DatePicker` (date only, min = today).

**Step B — 30-minute check.** *"Can you currently run about 30 minutes without stopping?"* — three options: yes / no / not sure. **Auto-skipped entirely when goal == `first_5k`** (also when reached via back-navigation after changing the goal — derive visibility from the goal, don't cache it).

**Step C — Injuries.** *"Any injuries we should train around?"* Multi-select chips: **shin splints · knee/ITB · plantar fasciitis · achilles · stress fracture · other**, plus a "None" chip that clears/excludes the rest. When ≥1 real chip selected, show optional free-text field ("when, which side, how it resolved"). "None" (or skip) → no note.

**Step D — Availability.** *"Which days can you usually train?"* Weekday multi-select (7 pills, Mon–Sun; respect `@AppStorage("weekStartsOnMonday")` for ordering if trivial). Below: optional "Preferred time" segmented choice — morning / lunch / evening / no preference (`LBSegmentToggle` if it fits, else custom).

**Final step — seed + done.** "Finishing up…" writes the notes (§6). On success (or nothing to write): a short confirmation — if a goal was set: *"Tell your coach you're ready and they'll build your plan."* — then "Done" → `onFinished()`. On network failure: inline error with **Retry** and **Skip for now** (Skip completes onboarding without notes — never trap the user). A 401 during writes is handled globally (unauthorized notification → login) — don't special-case it.

Back navigation between steps should work (simple chevron), preserving answers.

---

## 5. Date of birth (no screen)

- Add `HKCharacteristicType(.dateOfBirth)` to `HealthMetricsSyncer.readTypes` and expose `func dateOfBirthComponents() -> DateComponents?` (wrap `store.dateOfBirthComponents()` in try?; characteristic perms can't be checked — just attempt the read after authorization).
- If a birth year comes back, queue one extra observation note (§6). Silent no-op on failure/denial.

---

## 6. Note writing (in `OnboardingModel`, on the final step)

Build the list of notes from answers — **skipped/none answers produce no note**:

| Source | kind | importance | summary (≤280 chars) | body |
|---|---|---|---|---|
| Goal, race + date | `decision` | 3 | `Goal: half marathon on 2026-10-04 (set in app onboarding)` | `Playbook goal: half_marathon. Target date 2026-10-04.` |
| Goal, race, no date | `decision` | 3 | `Goal: half marathon — no target date yet (set in app onboarding)` | `Playbook goal: half_marathon.` |
| Goal, general fitness | `decision` | 3 | `Goal: general fitness — no race (set in app onboarding)` | `Playbook goal: general_fitness.` |
| 30-min = no | `observation` | 2 | `Says they cannot yet run 30 min continuously (app onboarding)` | – |
| 30-min = yes | `observation` | 2 | `Says they can run 30 min continuously (app onboarding)` | – |
| 30-min = not sure | `observation` | 2 | `Unsure whether they can run 30 min continuously (app onboarding)` | – |
| Injuries | `constraint` | 3 | `Injury history: shin splints, knee/ITB` (chip labels, comma-joined) | athlete's free text, verbatim (nil if empty) |
| Availability | `preference` | 2 | `Available to train Tue/Thu/Sat, prefers mornings (app onboarding)` — omit the prefers-clause if no time chosen | – |
| DOB (silent) | `observation` | 2 | `Born 1985 — 41 at onboarding` | – |

Goal-note `body` must contain the machine-readable `Playbook goal: <value>` exactly (the coach parses it). Dates formatted `yyyy-MM-dd`. Every note gets `conversationId: "ios-onboarding"`.

**Dedupe / re-run safety (append-only server):**
1. `GET api/plan-notes?conversation_id=ios-onboarding&limit=50`.
2. For each note to write, look for an existing match and **PATCH** it instead of POSTing. Matching on `kind` alone is NOT enough — the 30-min check and the DOB note are both `observation`. Match on `kind` **+ summary prefix**:
   - `decision` + summary starts `"Goal:"`
   - `constraint` + starts `"Injury history:"`
   - `preference` + starts `"Available to train"`
   - `observation` + starts `"Born"` → DOB; `observation` + (starts `"Says"` or `"Unsure"`) → 30-min check
3. POST only when no match. Never DELETE.

Write sequentially (4-5 requests max, simplicity > parallelism). Collect failures; any failure → the Retry/Skip UI in §4's final step.

---

## 7. Optional polish (do last, skip if anything above ran long)

Nudge card on the training home (`TrainingTabView`): if onboarding seeded a goal, show one dismissible `.lbCard` — *"Tell your coach you're ready and they'll build your plan"* — gated by `@AppStorage("onboardingNudgeDismissed")` + a flag `@AppStorage("onboardingSeededGoal")` set during §6. Dismiss = set flag, card never returns.

## 8. Verify

Build via XcodeBuildMCP (`session_show_defaults` first, then `build_sim`). Then walk the QA list:

- [ ] Fresh state (`hasCompletedOnboarding` unset), logged in → onboarding appears; HealthKit sheet only appears after tapping "Connect Apple Health", never before.
- [ ] Skipping every screen → zero network writes (watch the console/proxy), lands in normal app, flag set, app fully functional.
- [ ] Each answered screen → exactly one note with `conversationId: "ios-onboarding"`; goal note body contains `Playbook goal: <value>` from §4's table.
- [ ] Goal `first_5k` → Step B never shown (including after going back and changing the goal).
- [ ] "None" on injuries → no constraint note.
- [ ] Re-run (reset the flag in Settings ➝ or via defaults delete) → answers PATCH existing notes; `GET …conversation_id=ios-onboarding` shows no duplicates.
- [ ] Existing authenticated session after update → sees onboarding once; skip → normal app.
- [ ] Kill the network on the final step → Retry/Skip UI; Skip still completes onboarding.
