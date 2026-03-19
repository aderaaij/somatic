# Workout Actions API — Server-Side Spec

The iOS app now supports **editing** and **deleting** scheduled workouts via a new "pending actions" mechanism. When the app syncs (user taps "Check for New Workouts"), it first fetches pending actions, applies them locally via WorkoutKit, then acknowledges each action so the server can clean them up.

---

## New Endpoints

### 1. `GET /api/workouts/actions`

Returns all pending edit/delete actions that haven't been acknowledged yet.

**Headers:**
```
Authorization: Bearer <api_key>
```

**Response `200 OK`:**
```json
[
  {
    "id": "a1b2c3d4-...",
    "workoutId": "e5f6g7h8-...",
    "action": "delete",
    "composition": null
  },
  {
    "id": "b2c3d4e5-...",
    "workoutId": "f6g7h8i9-...",
    "action": "edit",
    "composition": {
      "id": "f6g7h8i9-...",
      "displayName": "Updated Tempo Run",
      "activityType": "running",
      "location": "outdoor",
      "scheduledDate": "2026-03-25T07:00:00Z",
      "warmup": {
        "goal": { "type": "time", "value": 600, "unit": "seconds" },
        "alert": null
      },
      "blocks": [
        {
          "iterations": 3,
          "steps": [
            {
              "purpose": "work",
              "goal": { "type": "distance", "value": 1600, "unit": "meters" },
              "alert": { "type": "speed", "min": 3.3, "max": 3.7, "zone": null, "unit": "metersPerSecond" }
            },
            {
              "purpose": "recovery",
              "goal": { "type": "time", "value": 120, "unit": "seconds" },
              "alert": null
            }
          ]
        }
      ],
      "cooldown": {
        "goal": { "type": "time", "value": 300, "unit": "seconds" },
        "alert": null
      }
    }
  }
]
```

**Response fields:**

| Field | Type | Description |
|---|---|---|
| `id` | UUID | Unique action ID. Used to acknowledge the action after processing. |
| `workoutId` | UUID | The workout plan's UUID. Must match the `id` originally used when queueing the workout. |
| `action` | string | `"edit"` or `"delete"` |
| `composition` | object \| null | Full workout composition (same schema as queue items). Present for `"edit"`, `null` for `"delete"`. |

---

### 2. `DELETE /api/workouts/actions/:actionId`

Acknowledges that a pending action has been applied on-device. The server should remove the action from the pending list.

**Headers:**
```
Authorization: Bearer <api_key>
```

**Response `200 OK`** (or `204 No Content`):
```json
{ "ok": true }
```

**Response `404 Not Found`** — action already acknowledged or doesn't exist.

---

## How the LLM Should Create Edit/Delete Actions

### To delete a workout from the user's watch:

```
POST /api/workouts/actions
```
```json
{
  "workoutId": "<original workout UUID>",
  "action": "delete"
}
```

### To edit a workout on the user's watch:

```
POST /api/workouts/actions
```
```json
{
  "workoutId": "<original workout UUID>",
  "action": "edit",
  "composition": {
    "id": "<same UUID as workoutId>",
    "displayName": "Updated Workout Name",
    "activityType": "running",
    "location": "outdoor",
    "scheduledDate": "2026-03-25T07:00:00Z",
    "warmup": { ... },
    "blocks": [ ... ],
    "cooldown": { ... }
  }
}
```

> **Important:** The `composition.id` in an edit action MUST match the `workoutId`. The app uses this UUID to find and replace the workout in WorkoutKit.

---

## Database Schema Suggestion

```sql
CREATE TABLE workout_actions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_id  UUID NOT NULL,
  action      TEXT NOT NULL CHECK (action IN ('edit', 'delete')),
  composition JSONB,            -- null for delete, full composition for edit
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for the GET endpoint
CREATE INDEX idx_workout_actions_created ON workout_actions (created_at);
```

When `DELETE /api/workouts/actions/:actionId` is called, delete the row.

---

### 3. `PUT /api/workouts/inventory`

The iOS app sends a full snapshot of all workouts currently scheduled on-device. This lets the server (and LLM) know what workout UUIDs exist and can be targeted for edit/delete — **including legacy workouts that were scheduled before the queue system existed.**

**Headers:**
```
Authorization: Bearer <api_key>
Content-Type: application/json
```

**Request body:**
```json
[
  {
    "id": "e5f6g7h8-...",
    "displayName": "Slow Burn – Week 1 Day 1",
    "date": { "year": 2026, "month": 3, "day": 20, "hour": 7, "minute": 0 },
    "complete": false
  },
  {
    "id": "a1b2c3d4-...",
    "displayName": "Easy 5K",
    "date": { "year": 2026, "month": 3, "day": 17, "hour": 8, "minute": 30 },
    "complete": true
  }
]
```

**Response `200 OK`:**
```json
{ "ok": true, "count": 2 }
```

**Server behavior:** Replace the stored inventory entirely (upsert all, delete any not in the list). This is an idempotent "here's everything on my device right now" sync.

**Database schema suggestion:**
```sql
CREATE TABLE workout_inventory (
  id           UUID PRIMARY KEY,
  display_name TEXT NOT NULL,
  year         INT,
  month        INT,
  day          INT,
  hour         INT,
  minute       INT,
  complete     BOOLEAN NOT NULL DEFAULT FALSE,
  synced_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

The LLM can query this table to discover available workout UUIDs when the user asks to edit or delete a workout.

---

## Endpoint Summary

### Existing (unchanged)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/workouts/queue` | Fetch queued new workouts |
| `DELETE` | `/api/workouts/queue/:id` | Remove item from queue after scheduling |
| `POST` | `/api/workouts` | Upload workout data |

### New

| Method | Path | Purpose |
|---|---|---|
| `PUT` | `/api/workouts/inventory` | Sync on-device workout list to server (called by iOS app) |
| `GET` | `/api/workouts/actions` | Fetch pending edit/delete actions |
| `POST` | `/api/workouts/actions` | Create a new edit/delete action (called by LLM) |
| `DELETE` | `/api/workouts/actions/:actionId` | Acknowledge a processed action (called by iOS app) |

---

## Sync Flow (iOS App Side — Already Implemented)

1. User taps "Check for New Workouts"
2. App calls `PUT /api/workouts/inventory` (reports all on-device workouts)
3. App calls `GET /api/workouts/actions`
4. For each action:
   - **delete**: removes workout from WorkoutKit scheduler, calls `DELETE /api/workouts/actions/:id`
   - **edit**: removes old workout, schedules updated version, calls `DELETE /api/workouts/actions/:id`
5. App calls `GET /api/workouts/queue` (existing flow)
6. Schedules any new workouts

---

## Composition Schema Reference

The `composition` object in edit actions uses the exact same schema as queue items:

```typescript
interface WorkoutComposition {
  id: string;                    // UUID
  displayName: string;
  activityType: "running" | "cycling" | "walking" | "hiking" | "swimming";
  location: "outdoor" | "indoor";
  scheduledDate: string;         // ISO 8601
  warmup?: CompositionStep;
  blocks: CompositionBlock[];
  cooldown?: CompositionStep;
}

interface CompositionBlock {
  iterations: number;
  steps: CompositionIntervalStep[];
}

interface CompositionIntervalStep {
  purpose: "work" | "recovery";
  goal: CompositionGoal;
  alert?: CompositionAlert;
}

interface CompositionStep {
  goal: CompositionGoal;
  alert?: CompositionAlert;
}

interface CompositionGoal {
  type: "open" | "distance" | "time" | "energy";
  value?: number;
  unit?: "meters" | "kilometers" | "miles" | "seconds" | "minutes" | "kilocalories";
}

interface CompositionAlert {
  type: "speed" | "heartRate" | "heartRateZone" | "cadence" | "power" | "powerZone";
  min?: number;
  max?: number;
  zone?: number;
  unit?: "metersPerSecond" | "kilometersPerHour";
}
```
