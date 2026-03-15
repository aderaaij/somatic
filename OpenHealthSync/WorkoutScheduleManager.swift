//
//  WorkoutScheduleManager.swift
//  OpenHealthSync
//
//  Fetches queued workout compositions from the training API,
//  builds WorkoutKit CustomWorkout objects, and schedules them
//  on Apple Watch via WorkoutScheduler.
//

import Foundation
import Combine
import SwiftUI
import WorkoutKit
import HealthKit

enum RefreshState: Equatable {
    case idle
    case fetching
    case scheduling(current: Int, total: Int)
    case done(count: Int)
    case failed(message: String)
}

@MainActor
class WorkoutScheduleManager: ObservableObject {
    @Published var scheduledWorkouts: [ScheduledWorkoutPlan] = []
    @Published var refreshState: RefreshState = .idle
    @Published var authorizationState: WorkoutScheduler.AuthorizationState = .notDetermined

    private let apiClient: WorkoutAPIClient

    init(apiClient: WorkoutAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        let state = await WorkoutScheduler.shared.requestAuthorization()
        authorizationState = state
    }

    // MARK: - Load Scheduled Workouts

    func loadScheduledWorkouts() async {
        scheduledWorkouts = await WorkoutScheduler.shared.scheduledWorkouts
    }

    // MARK: - Refresh from Server

    func refreshFromServer() async {
        refreshState = .fetching

        do {
            let queue = try await apiClient.fetchQueue()

            if queue.isEmpty {
                refreshState = .done(count: 0)
                return
            }

            var scheduled = 0
            for (index, composition) in queue.enumerated() {
                refreshState = .scheduling(current: index + 1, total: queue.count)

                do {
                    let customWorkout = try buildCustomWorkout(from: composition)
                    let plan = WorkoutPlan(.custom(customWorkout))

                    let dateComponents = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: composition.scheduledDate
                    )

                    await WorkoutScheduler.shared.schedule(plan, at: dateComponents)
                    try await apiClient.deleteQueueItem(id: composition.id)
                    scheduled += 1
                } catch {
                    print("Failed to schedule '\(composition.displayName)': \(error)")
                }
            }

            await loadScheduledWorkouts()
            refreshState = .done(count: scheduled)

        } catch {
            refreshState = .failed(message: error.localizedDescription)
        }
    }

    // MARK: - Remove All

    func removeAll() async {
        await WorkoutScheduler.shared.removeAllWorkouts()
        await loadScheduledWorkouts()
    }

    // MARK: - Build CustomWorkout

    func buildCustomWorkout(from composition: QueuedWorkoutComposition) throws -> CustomWorkout {
        let activity = mapActivityType(composition.activityType)
        let location = mapLocation(composition.location)

        let warmup: WorkoutStep? = composition.warmup.map { step in
            WorkoutStep(goal: mapGoal(step.goal), alert: mapAlert(step.alert))
        }

        let blocks: [IntervalBlock] = composition.blocks.map { block in
            let steps: [IntervalStep] = block.steps.map { step in
                IntervalStep(
                    mapPurpose(step.purpose),
                    goal: mapGoal(step.goal),
                    alert: mapAlert(step.alert)
                )
            }
            return IntervalBlock(steps: steps, iterations: block.iterations)
        }

        let cooldown: WorkoutStep? = composition.cooldown.map { step in
            WorkoutStep(goal: mapGoal(step.goal), alert: mapAlert(step.alert))
        }

        return CustomWorkout(
            activity: activity,
            location: location,
            displayName: composition.displayName,
            warmup: warmup,
            blocks: blocks,
            cooldown: cooldown
        )
    }

    // MARK: - Mapping Helpers

    private func mapGoal(_ goal: CompositionGoal) -> WorkoutGoal {
        switch goal.type {
        case "distance":
            guard let value = goal.value else { return .open }
            let unit = mapLengthUnit(goal.unit)
            return .distance(value, unit)
        case "time":
            guard let value = goal.value else { return .open }
            let unit = mapDurationUnit(goal.unit)
            return .time(value, unit)
        case "energy":
            guard let value = goal.value else { return .open }
            let unit = mapEnergyUnit(goal.unit)
            return .energy(value, unit)
        default:
            return .open
        }
    }

    private func mapAlert(_ alert: CompositionAlert?) -> (any WorkoutAlert)? {
        guard let alert else { return nil }

        switch alert.type {
        case "speed":
            guard let min = alert.min, let max = alert.max else { return nil }
            let unit = mapSpeedUnit(alert.unit)
            return SpeedRangeAlert(
                target: Measurement(value: min, unit: unit)...Measurement(value: max, unit: unit),
                metric: .current
            )
        case "heartRate":
            guard let min = alert.min, let max = alert.max else { return nil }
            return HeartRateRangeAlert.heartRate(min...max)
        case "heartRateZone":
            guard let zone = alert.zone else { return nil }
            return HeartRateZoneAlert(zone: zone)
        case "cadence":
            guard let min = alert.min, let max = alert.max else { return nil }
            return CadenceRangeAlert.cadence(min...max)
        case "power":
            guard let min = alert.min, let max = alert.max else { return nil }
            return PowerRangeAlert.power(min...max, unit: .watts)
        case "powerZone":
            guard let zone = alert.zone else { return nil }
            return PowerZoneAlert.power(zone: zone)
        default:
            return nil
        }
    }

    private func mapPurpose(_ purpose: String) -> IntervalStep.Purpose {
        switch purpose {
        case "work": return .work
        case "recovery": return .recovery
        default: return .work
        }
    }

    private func mapActivityType(_ type: String) -> HKWorkoutActivityType {
        switch type {
        case "running": return .running
        case "cycling": return .cycling
        case "walking": return .walking
        case "hiking": return .hiking
        case "swimming": return .swimming
        default: return .running
        }
    }

    private func mapLocation(_ location: String) -> HKWorkoutSessionLocationType {
        switch location {
        case "outdoor": return .outdoor
        case "indoor": return .indoor
        default: return .unknown
        }
    }

    private func mapLengthUnit(_ unit: String?) -> UnitLength {
        switch unit {
        case "meters": return .meters
        case "kilometers": return .kilometers
        case "miles": return .miles
        default: return .meters
        }
    }

    private func mapDurationUnit(_ unit: String?) -> UnitDuration {
        switch unit {
        case "seconds": return .seconds
        case "minutes": return .minutes
        default: return .seconds
        }
    }

    private func mapEnergyUnit(_ unit: String?) -> UnitEnergy {
        switch unit {
        case "kilocalories": return .kilocalories
        default: return .kilocalories
        }
    }

    private func mapSpeedUnit(_ unit: String?) -> UnitSpeed {
        switch unit {
        case "metersPerSecond": return .metersPerSecond
        case "kilometersPerHour": return .kilometersPerHour
        default: return .metersPerSecond
        }
    }
}
