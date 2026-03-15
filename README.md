# Somatic

A personal health data hub for iOS that syncs Apple HealthKit data to your own server, extracts detailed workout metrics, and schedules training plans on Apple Watch.

## Features

### Health Data Sync

Continuously syncs HealthKit data to a self-hosted [Open Wearables](https://github.com/open-wearables) server using the OpenWearablesHealthSDK. Supports background delivery and incremental sync with three data tiers:

- **Activity & Fitness** — Steps, heart rate, HRV, VO2 Max, oxygen saturation, respiratory rate, sleep, workouts, body measurements, walking metrics
- **Nutrition** — Dietary energy, protein, carbohydrates, fats, water
- **Clinical & Metabolic** — Blood glucose, blood pressure, body temperature, advanced walking metrics, six-minute walk test

### Workout Extraction & Upload

Pulls detailed workout data from HealthKit and sends it to your training API as structured JSON:

- GPS routes with altitude, speed, and course data
- Heart rate, cadence, power, speed, stride length, vertical oscillation, and ground contact time series
- Auto-computed 1km splits with elevation gain/loss and average metrics
- Multi-activity segment support with per-segment metrics
- Workout events (pause, resume, lap, segment, marker)
- Deduplication based on >90% time overlap

Supports 30+ activity types including running, cycling, swimming, strength training, yoga, HIIT, and more.

### Workout Scheduling

Fetches planned workouts from your training API and schedules them on Apple Watch via WorkoutKit:

- Structured workouts with warm-up, interval blocks, and cooldown
- Training goals (distance, time, energy, open)
- Training alerts for heart rate zones, pace, cadence, and power
- Repeatable interval blocks with work/recovery steps

## Requirements

- iOS 26+
- Xcode 26+
- A self-hosted [Open Wearables](https://github.com/open-wearables) server (for health data sync)
- A self-hosted Training API server (for workout extraction and scheduling)

## Server Overview

Somatic connects to two backend services:

| Server | Purpose | Used by |
|---|---|---|
| Open Wearables | Receives and stores HealthKit health data (activity, sleep, nutrition, clinical) | Health Data Sync |
| Training API | Stores extracted workouts, serves planned workout compositions to Apple Watch | Workout Extraction & Scheduling |

Both servers are designed to run on a home server or VPS. The app communicates with them over HTTPS (e.g., via [Tailscale Funnel](https://tailscale.com/kb/1223/funnel/) or a reverse proxy).

### Open Wearables

The Open Wearables server receives health data from the app via the [OpenWearablesHealthSDK](https://github.com/open-wearables).

1. Follow the setup instructions at [open-wearables](https://github.com/open-wearables)
2. Note your server URL and API key — you'll enter these in the app's onboarding screen

### Training API

The Training API stores workout data uploaded from the app and serves planned workout compositions for Apple Watch scheduling.

Quick start with Docker Compose:

```bash
git clone https://github.com/your-username/training-api.git
cd training-api
cp .env.example .env  # Edit with your DATABASE_URL and API_KEY
docker compose up -d
```

The API runs on port 8001 by default. You'll need to expose it over HTTPS for the app to connect — for example, using [Tailscale Funnel](https://tailscale.com/kb/1223/funnel/) or a reverse proxy like Caddy/nginx.

Required endpoints:

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/workouts` | Accepts extracted workout JSON (upserts by workout ID) |
| `GET` | `/api/workouts/queue` | Returns pending workout compositions for Apple Watch |
| `DELETE` | `/api/workouts/queue/{id}` | Removes a workout from the queue after scheduling |

All endpoints require `Authorization: Bearer <API_KEY>`.

#### Workout queue format

The `/api/workouts/queue` endpoint returns an array of workout compositions that the app decodes and schedules on Apple Watch via WorkoutKit:

```json
{
  "id": "uuid",
  "displayName": "6x400m Intervals",
  "activityType": "running",
  "location": "outdoor",
  "scheduledDate": "2026-03-18T07:00:00Z",
  "warmup": {
    "goal": { "type": "distance", "value": 800, "unit": "meters" }
  },
  "blocks": [
    {
      "iterations": 6,
      "steps": [
        { "purpose": "work", "goal": { "type": "distance", "value": 400, "unit": "meters" } },
        { "purpose": "recovery", "goal": { "type": "distance", "value": 400, "unit": "meters" } }
      ]
    }
  ],
  "cooldown": {
    "goal": { "type": "distance", "value": 800, "unit": "meters" }
  }
}
```

See the [Training API repository](https://github.com/your-username/training-api) for full schema documentation including goal types, alert types, and supported activity types.

### Optional: MCP Integration

Both servers can be paired with [MCP](https://modelcontextprotocol.io/) gateways to let AI assistants (like Claude) query your health data and create workout plans that sync to your Apple Watch. See the respective server repositories for MCP setup instructions.

## App Setup

### 1. Clone the repository

```bash
git clone https://github.com/your-username/OpenHealthSync.git
cd OpenHealthSync
```

### 2. Configure secrets

Copy the example config and fill in your values:

```bash
cp Secrets.example.xcconfig Secrets.xcconfig
```

Edit `Secrets.xcconfig`:

```
WORKOUT_API_BASE_URL = https://your-training-api.example.com:8443
WORKOUT_API_KEY = your-training-api-key-here
```

> The Open Wearables server URL and API key are configured in-app during onboarding.
> `Secrets.xcconfig` is git-ignored and will never be committed.

### 3. Open in Xcode and set the configuration file

```bash
open OpenHealthSync.xcodeproj
```

Then set `Secrets.xcconfig` as the base configuration for the target:

1. Select the **OpenHealthSync** project in the navigator
2. Go to the **Info** tab → **Configurations**
3. Under both **Debug** and **Release**, set the **OpenHealthSync target** row to `Secrets`

The OpenWearablesHealthSDK Swift package dependency will resolve automatically.

### 4. Run

Build and run on a physical device (HealthKit is not available in the simulator). On first launch, configure your Open Wearables server URL, user ID, and API key in the onboarding screen.

## Architecture

| Component | Role |
|---|---|
| `HealthManager` | Manages OpenWearablesHealthSDK lifecycle, HealthKit authorization, and background sync |
| `WorkoutManager` | Fetches workouts from HealthKit, deduplicates, tracks sent state, coordinates extraction and upload |
| `WorkoutExtractor` | Actor that concurrently extracts routes, time series, splits, and events from individual workouts |
| `WorkoutAPIClient` | Actor-based HTTP client for the training API (send workouts, fetch/delete workout queue) |
| `WorkoutScheduleManager` | Fetches planned workouts from the API and schedules them on Apple Watch via WorkoutKit |
| `SyncProgress` | Tracks real-time sync status by parsing SDK log messages |

### Key patterns

- `@MainActor` isolation for all UI-bound state managers
- Swift actors for thread-safe async operations (`WorkoutExtractor`, `WorkoutAPIClient`)
- `async/await` throughout — no completion handler chains
- `@AppStorage` for lightweight config persistence
- `autoreleasepool` for memory optimization during large data extractions

## License

TBD
