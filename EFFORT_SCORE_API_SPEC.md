# Workout Effort Score — Server-Side Spec

The iOS app now reads two new HealthKit signals per workout (iOS 18+ /
watchOS 11+) and includes them in the existing `POST /api/workouts` payload:

- **`effortScore`** — user-rated RPE on a 1–10 scale, captured via the
  Apple Watch post-workout effort prompt (`HKQuantityType(.workoutEffortScore)`).
- **`estimatedEffortScore`** — system-estimated RPE on the same 1–10 scale,
  computed by Apple from heart rate / activity data
  (`HKQuantityType(.estimatedWorkoutEffortScore)`).

Both fields are **optional**. They will be `null` when:

- the workout predates iOS 18 / watchOS 11,
- the user dismissed the watchOS effort prompt without rating (for `effortScore`),
- the system did not produce an estimate (for `estimatedEffortScore`),
- HealthKit read authorization for these types was not granted.

---

## Payload Change — `POST /api/workouts`

The existing endpoint contract is unchanged. Two new optional fields are
appended to the `DetailedWorkout` JSON object:

```jsonc
{
  "id": "…",
  "planWorkoutId": "…",
  "activityType": "running",
  "startDate": "2026-04-25T07:30:00Z",
  "endDate":   "2026-04-25T08:15:00Z",
  // … existing fields (duration, route, heartRate, splits, …) …

  "effortScore": 7,            // NEW — nullable, 1–10, user-rated RPE
  "estimatedEffortScore": 6.5  // NEW — nullable, 1–10, system-estimated RPE
}
```

**Field details:**

| Field                  | Type           | Required | Range  | Description |
|------------------------|----------------|----------|--------|-------------|
| `effortScore`          | number \| null | No       | 1–10   | User-rated post-workout RPE from Apple Watch. |
| `estimatedEffortScore` | number \| null | No       | 1–10   | Apple's algorithmic effort estimate. |

Both are encoded as JSON numbers (not strings). The server should accept
fractional values (`6.5`) — Apple stores `estimatedWorkoutEffortScore` with
sub-integer precision. `effortScore` from the watch UI is integer in
practice but should be stored as the same numeric type to keep the schema
uniform.

---

## Database Schema

Add two nullable numeric columns to whichever table holds the per-workout
record posted by `/api/workouts` (assumed `workouts` below — adjust the
table name to match the existing schema).

```sql
ALTER TABLE workouts
  ADD COLUMN effort_score           NUMERIC(3, 1),
  ADD COLUMN estimated_effort_score NUMERIC(3, 1);

ALTER TABLE workouts
  ADD CONSTRAINT effort_score_range
    CHECK (effort_score IS NULL OR (effort_score BETWEEN 1 AND 10)),
  ADD CONSTRAINT estimated_effort_score_range
    CHECK (estimated_effort_score IS NULL
           OR (estimated_effort_score BETWEEN 1 AND 10));
```

`NUMERIC(3, 1)` covers `1.0`–`10.0` with one decimal place — enough for the
estimated score's precision and harmless for the integer user score.

No new index needed: these columns are filtered/aggregated rather than
joined on. If the MCP starts running queries like "show me runs where
estimatedEffortScore > 8", a partial index can be added later.

---

## API Handler Change

In the `POST /api/workouts` handler:

1. Accept the two new fields on the request body. Treat both as optional.
2. Validate range when present (`1 ≤ x ≤ 10`); reject with `400` otherwise.
3. Persist to the new columns (`NULL` when absent).
4. On the read side (`GET` of a single workout, list endpoints, MCP tool
   responses), include both fields verbatim.

The endpoint's response shape, status codes, and idempotency contract do
not change.

---

## MCP Tool Changes

The existing recent-runs / device-workouts MCP tool(s) should add both
fields to their response schema so the LLM can read them. No new tool is
required.

Suggested LLM usage hints (for tool descriptions):

- `effortScore` is the **user's perception** of the workout. Trust it as
  the primary signal.
- `estimatedEffortScore` is **Apple's algorithmic estimate**, useful for
  cross-referencing against `effortScore`.
- A large gap between the two (e.g. user rates 8 but estimate is 5) can
  indicate **non-cardiovascular load** (heat, sleep debt, dehydration,
  illness, life stress) that HR-based estimates miss — worth surfacing
  during weekly review when it appears repeatedly.
- Treat `null` as **no signal**, not as "low effort." Don't infer absence
  of effort from a missing rating.

---

## Source on the iOS Side (for reference)

The fields are populated in `WorkoutExtractor.extractWorkout` via
`HKQuery.predicateForWorkoutEffortSamplesRelated(workout:activity:)`. Read
authorization is requested alongside other HealthKit metrics in
`HealthMetricsSyncer.readTypes`.

Older workouts re-synced after the iOS update will have `null` for both
fields (Apple does not retroactively backfill effort samples), so the
data will only become populated for workouts completed from the update
date onwards.
