# Workout Feedback API — Server-Side Spec

The iOS app collects lightweight feedback when a user misses a scheduled workout. Feedback is stored locally (SwiftData) and synced to the server so the LLM can access it during coaching conversations.

---

## New Endpoints

### 1. `POST /api/workouts/feedback`

Records feedback for a missed workout.

**Headers:**
```
Authorization: Bearer <api_key>
Content-Type: application/json
```

**Request body:**
```json
{
  "id": "f1a2b3c4-...",
  "workoutId": "e5f6g7h8-...",
  "workoutName": "Easy 6K",
  "scheduledDate": "2026-03-19T00:00:00Z",
  "detectedAt": "2026-03-20T08:15:00Z",
  "acknowledgedAt": "2026-03-20T08:16:30Z",
  "reason": "tired",
  "reasonNote": null,
  "action": "move",
  "newDate": "2026-03-22T00:00:00Z",
  "dismissed": false
}
```

**Request fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | UUID | Yes | Unique feedback entry ID (generated on device). |
| `workoutId` | UUID | Yes | The scheduled workout plan UUID this feedback is about. |
| `workoutName` | string | Yes | Display name of the workout (denormalized for readability). |
| `scheduledDate` | ISO 8601 | Yes | When the workout was originally scheduled. |
| `detectedAt` | ISO 8601 | Yes | When the app first flagged this workout as missed. |
| `acknowledgedAt` | ISO 8601 | No | When the user responded to the prompt. `null` if dismissed without responding. |
| `reason` | string | Yes | One of: `"busy"`, `"tired"`, `"weather"`, `"soreness"`, `"motivation"`, `"other"` |
| `reasonNote` | string | No | Free text note. Only present when `reason` is `"other"`. |
| `action` | string | Yes | One of: `"move"`, `"adjust"`, `"skip"` |
| `newDate` | ISO 8601 | No | The date the workout was rescheduled to. Only present when `action` is `"move"`. |
| `dismissed` | boolean | Yes | `true` if the user dismissed the prompt without providing feedback. |

**Response `201 Created`:**
```json
{ "ok": true, "id": "f1a2b3c4-..." }
```

**Response `409 Conflict`** — feedback with this `id` already exists (idempotent upsert is preferred).

---

### 2. `GET /api/workouts/feedback`

Retrieves feedback history, newest first.

**Headers:**
```
Authorization: Bearer <api_key>
```

**Query parameters:**

| Param | Type | Default | Description |
|---|---|---|---|
| `since` | ISO 8601 date | (none) | Only return feedback entries with `scheduledDate` on or after this date. |
| `limit` | integer | 20 | Maximum number of entries to return. |
| `action` | string | (none) | Filter by action type: `"move"`, `"adjust"`, or `"skip"`. |

**Example:**
```
GET /api/workouts/feedback?since=2026-03-01&limit=10&action=adjust
```

**Response `200 OK`:**
```json
[
  {
    "id": "f1a2b3c4-...",
    "workoutId": "e5f6g7h8-...",
    "workoutName": "Easy 6K",
    "scheduledDate": "2026-03-19T00:00:00Z",
    "detectedAt": "2026-03-20T08:15:00Z",
    "acknowledgedAt": "2026-03-20T08:16:30Z",
    "reason": "tired",
    "reasonNote": null,
    "action": "move",
    "newDate": "2026-03-22T00:00:00Z",
    "dismissed": false
  }
]
```

---

## Database Schema

```sql
CREATE TABLE workout_feedback (
  id              UUID PRIMARY KEY,
  workout_id      UUID NOT NULL,
  workout_name    TEXT NOT NULL,
  scheduled_date  TIMESTAMPTZ NOT NULL,
  detected_at     TIMESTAMPTZ NOT NULL,
  acknowledged_at TIMESTAMPTZ,
  reason          TEXT NOT NULL CHECK (reason IN ('busy', 'tired', 'weather', 'soreness', 'motivation', 'other')),
  reason_note     TEXT,
  action          TEXT NOT NULL CHECK (action IN ('move', 'adjust', 'skip')),
  new_date        TIMESTAMPTZ,
  dismissed       BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- For querying by date range
CREATE INDEX idx_workout_feedback_scheduled ON workout_feedback (scheduled_date DESC);

-- For finding feedback by workout
CREATE INDEX idx_workout_feedback_workout ON workout_feedback (workout_id);

-- For filtering by action (e.g. find all "adjust" entries for LLM)
CREATE INDEX idx_workout_feedback_action ON workout_feedback (action);
```

---

## MCP Tool Definitions

These tools are exposed to Claude via the Training MCP server.

### `get_workout_feedback`

Retrieve feedback entries, optionally filtered by date range or action type. Used by the LLM to understand patterns in missed workouts and inform coaching decisions.

**Parameters:**

| Param | Type | Required | Description |
|---|---|---|---|
| `since` | ISO 8601 date | No | Only return entries with `scheduledDate` on or after this date. |
| `limit` | integer | No | Max entries to return (default 20). |
| `action` | string | No | Filter: `"move"`, `"adjust"`, or `"skip"`. |

**Returns:** Array of feedback entries (same schema as `GET /api/workouts/feedback` response).

**Usage by LLM:**
- Query `action=adjust` to find workouts the user flagged for plan adjustment
- Query without filters to see recent missed workout patterns
- Cross-reference with `get_device_workouts` and `get_recent_runs` for full context

### `get_missed_workouts`

Convenience tool: returns currently past-due, incomplete workouts that don't yet have feedback entries. Saves the LLM from manually filtering `get_device_workouts`.

**Parameters:** None.

**Returns:**
```json
[
  {
    "workoutId": "e5f6g7h8-...",
    "displayName": "Easy 6K",
    "scheduledDate": "2026-03-19",
    "daysMissed": 1
  }
]
```

**Server logic:** Query `workout_inventory` for `complete = false` AND `scheduled date < today`, then exclude any `workout_id` that appears in `workout_feedback`.

---

## iOS App Sync Behavior

### Current (implemented)

Feedback is stored locally in SwiftData (`WorkoutFeedback` model). No server sync yet.

### Planned sync flow

When the server endpoints above are ready:

1. On feedback creation (user completes the feedback sheet), the app calls `POST /api/workouts/feedback` in the background.
2. On app launch or sync, the app can reconcile local SwiftData entries against the server to handle edge cases (e.g., app was offline when feedback was created).
3. The sync is fire-and-forget — local SwiftData is the source of truth for the UI. The server copy exists so the LLM can read it.

### Implementation notes for the iOS side

Add to `WorkoutAPIClient.swift`:

```swift
// POST /api/workouts/feedback
func submitFeedback(_ feedback: WorkoutFeedbackPayload) async throws {
    let url = baseURL.appendingPathComponent("api/workouts/feedback")
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    request.httpBody = try encoder.encode(feedback)

    let (_, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse,
          (200...299).contains(http.statusCode) else {
        throw WorkoutAPIError.serverError(
            (response as? HTTPURLResponse)?.statusCode ?? 0
        )
    }
}
```

The `WorkoutFeedbackPayload` is a Codable struct that mirrors the `WorkoutFeedback` SwiftData model but without the `@Model` macro (for encoding).

---

## Action Semantics — What the LLM Should Do

| Action | Meaning | LLM behavior |
|---|---|---|
| `"move"` | User rescheduled the workout themselves. `newDate` contains the new date. | Treat as resolved. Note for pattern analysis but no action needed. The workout was already moved on-device via `edit_scheduled_workout`. |
| `"adjust"` | User wants LLM help adjusting the plan. | **Proactively raise** when the user next asks about their plan/runs: *"Looks like you missed Wednesday's Easy 6K and flagged it for adjustment — want to figure out how to handle it?"* |
| `"skip"` | User chose to skip, no changes wanted. | Note silently. Only surface if a pattern emerges (e.g., 3+ skips in a week marked "tired" → suggest reducing volume). |
| `dismissed: true` | User saw the prompt but closed it without responding. | Treat like `"skip"` but with even less signal. Don't mention unless asked. |

### Pattern detection (for weekly review)

When the LLM has access to accumulated feedback, it can surface patterns:

- **Fatigue signal:** Multiple entries with `reason: "tired"` → suggest reducing volume or adding recovery days
- **Schedule conflict:** Multiple entries with `reason: "busy"` → suggest shifting workout days or shorter sessions
- **Weather pattern:** Multiple entries with `reason: "weather"` → suggest indoor alternatives
- **Motivation dip:** Multiple entries with `reason: "motivation"` → check if plan variety is sufficient, suggest different workout types

These should be raised during the weekly review flow, not as immediate reactions.

---

## Endpoint Summary

### Existing (unchanged)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/workouts/queue` | Fetch queued new workouts |
| `DELETE` | `/api/workouts/queue/:id` | Remove item from queue after scheduling |
| `POST` | `/api/workouts` | Upload workout data |
| `PUT` | `/api/workouts/inventory` | Sync on-device workout list |
| `GET` | `/api/workouts/actions` | Fetch pending edit/delete actions |
| `POST` | `/api/workouts/actions` | Create edit/delete action (LLM) |
| `DELETE` | `/api/workouts/actions/:id` | Acknowledge processed action |

### New

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/workouts/feedback` | Record missed workout feedback (iOS app) |
| `GET` | `/api/workouts/feedback` | Retrieve feedback history (LLM via MCP) |
