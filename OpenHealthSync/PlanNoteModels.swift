//
//  PlanNoteModels.swift
//  OpenHealthSync
//
//  Wire models for the training API's plan-notes endpoints. These seed the
//  coach LLM's memory during first-run onboarding (conversationId
//  "ios-onboarding"). Casing is deliberately mixed to match the backend:
//  request bodies use camelCase aliases, responses mix camelCase fields with
//  snake_case timestamps (which we don't decode — see below).
//
//  Marked `nonisolated` because the project defaults types to @MainActor
//  (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor); without this their Codable
//  conformances couldn't be used from the WorkoutAPIClient actor.
//

import Foundation

/// A plan note as returned by the API. We only model the fields we read.
///
/// The backend's `created_at` / `updated_at` / `expiresAt` carry fractional
/// seconds, which `.iso8601` date decoding can't parse — so we omit them
/// entirely (Codable ignores unknown keys) and decode with a plain decoder.
nonisolated struct PlanNote: Codable, Identifiable, Sendable {
    let id: String            // UUID string
    let kind: String
    let summary: String
    let body: String?
    let importance: Int
    let conversationId: String?

    // Fields are already camelCase; explicit CodingKeys kept to match the
    // codebase idiom (no `.convertFromSnakeCase` anywhere).
    enum CodingKeys: String, CodingKey {
        case id, kind, summary, body, importance, conversationId
    }
}

/// POST body — a new global, non-expiring note. Deliberately omits
/// `planId` / `expiresAt`.
nonisolated struct PlanNoteCreate: Encodable, Sendable {
    let kind: String          // "decision" | "preference" | "constraint" | "observation"
    let summary: String       // server caps at 280 chars — enforced client-side
    let body: String?
    let importance: Int       // 1...3
    let conversationId: String // always "ios-onboarding" here
}

/// PATCH body — partial update. Only the fields that change on re-run;
/// `kind` / `importance` stay as originally created.
nonisolated struct PlanNoteUpdate: Encodable, Sendable {
    let summary: String
    let body: String?
}
