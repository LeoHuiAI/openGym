import Foundation
import CoreFoundation
import HealthKit
import Capacitor
import UIKit

/**
 * Writes openGym workouts and weigh-ins to Apple Health. The JavaScript side owns the provider-
 * neutral records and device-local sync file; this plugin only maps those records to HealthKit.
 *
 * HealthKit is write-only here. The permission request deliberately contains no read types, and
 * every record carries openGym's external UUID so the app can find only its own records again.
 */
@objc(HealthKitPlugin)
public class HealthKitPlugin: CAPPlugin {

    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()
    private let bodyMassType = HKObjectType.quantityType(forIdentifier: .bodyMass)!
    // A serial queue keeps a remove behind the write that produced the record.
    private let operationQueue = DispatchQueue(label: "ch.duartesantos.opengym.healthkit")

    private static let titleMetadataKey = "ch.duartesantos.opengym.title"
    private static let notesMetadataKey = "ch.duartesantos.opengym.notes"

    // Pure conversion seams are internal so the AppTests target can verify the shared contract
    // without requesting HealthKit permission or saving a real sample.
    static func activityType(for value: String?) -> HKWorkoutActivityType {
        switch value {
        case "strength_training": return .traditionalStrengthTraining
        case "walking": return .walking
        case "running": return .running
        case "biking_stationary": return .cycling
        case "elliptical": return .elliptical
        case "stair_climbing_machine": return .stairClimbing
        case "other_workout": return .other
        default: return .other
        }
    }

    static func bodyMassQuantity(for kilograms: Double) -> HKQuantity {
        HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: kilograms)
    }

    @objc func status(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.resolve(["status": "unsupported", "granted": false])
            return
        }
        call.resolve(["status": "available", "granted": hasWriteAuthorization()])
    }

    @objc func requestPermissions(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("HealthKit is not available", "unavailable")
            return
        }

        // Do not add read types: openGym only writes the records it creates itself.
        let typesToShare: Set<HKSampleType> = [workoutType, bodyMassType]
        store.requestAuthorization(toShare: typesToShare, read: []) { [weak self] success, error in
            guard let self else {
                call.reject("HealthKit plugin is unavailable", "failed")
                return
            }
            if let error {
                call.reject(error.localizedDescription, self.errorCode(for: error), error)
                return
            }
            call.resolve(["granted": success && self.hasWriteAuthorization()])
        }
    }

    @objc func write(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("HealthKit is not available", "unavailable")
            return
        }

        let sessions = call.getArray("sessions", JSObject.self) ?? []
        let weights = call.getArray("weights", JSObject.self) ?? []
        operationQueue.async { [weak self] in
            guard let self else {
                call.reject("HealthKit plugin is unavailable", "failed")
                return
            }
            do {
                guard self.hasWriteAuthorization() else {
                    call.reject("Apple Health write permission is required", "permission")
                    return
                }
                let workouts = try sessions.map { try self.workout(from: $0) }
                let weighIns = try weights.map { try self.weightSample(from: $0) }
                for record in workouts {
                    try self.replace(record, type: self.workoutType, externalID: record.metadata?[HKMetadataKeyExternalUUID] as? String ?? "")
                }
                for record in weighIns {
                    try self.replace(record, type: self.bodyMassType, externalID: record.metadata?[HKMetadataKeyExternalUUID] as? String ?? "")
                }
                call.resolve()
            } catch {
                call.reject(error.localizedDescription, self.errorCode(for: error), error)
            }
        }
    }

    @objc func remove(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else {
            call.reject("HealthKit is not available", "unavailable")
            return
        }

        let sessionIDs = call.getArray("sessions", String.self) ?? []
        let weightIDs = call.getArray("weights", String.self) ?? []
        operationQueue.async { [weak self] in
            guard let self else {
                call.reject("HealthKit plugin is unavailable", "failed")
                return
            }
            do {
                for id in sessionIDs {
                    try self.deleteMatches(type: self.workoutType, externalID: id)
                }
                for id in weightIDs {
                    try self.deleteMatches(type: self.bodyMassType, externalID: id)
                }
                call.resolve()
            } catch {
                call.reject(error.localizedDescription, self.errorCode(for: error), error)
            }
        }
    }

    @objc func openSettings(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                call.reject("Unable to open Settings", "failed")
                return
            }
            UIApplication.shared.open(url, options: [:]) { opened in
                if opened {
                    call.resolve()
                } else {
                    call.reject("Unable to open Settings", "failed")
                }
            }
        }
    }

    private func hasWriteAuthorization() -> Bool {
        store.authorizationStatus(for: workoutType) == .sharingAuthorized &&
            store.authorizationStatus(for: bodyMassType) == .sharingAuthorized
    }

    private func workout(from record: JSObject) throws -> HKWorkout {
        let id = try requiredString(record, key: "id")
        let start = try date(record, key: "start")
        let end = try date(record, key: "end")
        guard end > start else {
            throw HealthKitPluginError.invalid("Workout end must be after start")
        }

        var metadata: [String: Any] = [HKMetadataKeyExternalUUID: id]
        if let title = record["title"] as? String, !title.isEmpty {
            metadata[Self.titleMetadataKey] = title
        }
        if let notes = record["notes"] as? String, !notes.isEmpty {
            metadata[Self.notesMetadataKey] = notes
        }

        return HKWorkout(
            activityType: Self.activityType(for: record["type"] as? String),
            start: start,
            end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: nil,
            totalDistance: nil,
            device: nil,
            metadata: metadata
        )
    }

    private func weightSample(from record: JSObject) throws -> HKQuantitySample {
        let id = try requiredString(record, key: "id")
        let time = try date(record, key: "time")
        guard let kg = number(record["kg"]), kg > 0 else {
            throw HealthKitPluginError.invalid("Weight must be a positive number")
        }
        let quantity = Self.bodyMassQuantity(for: kg)
        return HKQuantitySample(
            type: bodyMassType,
            quantity: quantity,
            start: time,
            end: time,
            metadata: [HKMetadataKeyExternalUUID: id]
        )
    }

    // HealthKit does not replace a sample by metadata UUID. Delete an existing openGym record
    // first, then save the new value, so edited workouts and weigh-ins remain idempotent.
    private func replace(_ object: HKObject, type: HKSampleType, externalID: String) throws {
        guard !externalID.isEmpty else {
            throw HealthKitPluginError.invalid("Record id is required")
        }
        try deleteMatches(type: type, externalID: externalID)
        try save(object)
    }

    private func save(_ object: HKObject) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var saveError: Error?
        store.save(object) { success, error in
            saveError = error
            if !success && saveError == nil {
                saveError = HealthKitPluginError.failed("HealthKit did not save the requested record")
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let saveError { throw saveError }
    }

    private func deleteMatches(type: HKSampleType, externalID: String) throws {
        guard !externalID.isEmpty else { return }
        let externalIDPredicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            operatorType: .equalTo,
            value: externalID
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            externalIDPredicate,
            HKQuery.predicateForObjects(from: HKSource.default())
        ])
        let semaphore = DispatchSemaphore(value: 0)
        var matches: [HKSample] = []
        var queryError: Error?
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, error in
            matches = samples ?? []
            queryError = error
            semaphore.signal()
        }
        store.execute(query)
        semaphore.wait()
        if let queryError { throw queryError }
        guard !matches.isEmpty else { return }

        let deleteSemaphore = DispatchSemaphore(value: 0)
        var deleteError: Error?
        store.delete(matches.map { $0 as HKObject }) { success, error in
            deleteError = error
            if !success && deleteError == nil {
                deleteError = HealthKitPluginError.failed("HealthKit did not delete the requested records")
            }
            deleteSemaphore.signal()
        }
        deleteSemaphore.wait()
        if let deleteError { throw deleteError }
    }

    private func requiredString(_ record: JSObject, key: String) throws -> String {
        guard let value = record[key] as? String, !value.isEmpty else {
            throw HealthKitPluginError.invalid("Record \(key) is required")
        }
        return value
    }

    private func date(_ record: JSObject, key: String) throws -> Date {
        guard let milliseconds = number(record[key]), milliseconds > 0 else {
            throw HealthKitPluginError.invalid("Record \(key) is required")
        }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private func number(_ value: JSValue?) -> Double? {
        let result: Double
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            result = number.doubleValue
        } else {
            return nil
        }
        return result.isFinite ? result : nil
    }

    private func errorCode(for error: Error) -> String {
        if !HKHealthStore.isHealthDataAvailable() { return "unavailable" }
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return "failed" }
        switch nsError.code {
        case HKError.Code.errorHealthDataUnavailable.rawValue: return "unavailable"
        case HKError.Code.errorHealthDataRestricted.rawValue,
             HKError.Code.errorAuthorizationDenied.rawValue,
             HKError.Code.errorAuthorizationNotDetermined.rawValue: return "permission"
        default: return "failed"
        }
    }

    private enum HealthKitPluginError: LocalizedError {
        case invalid(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let message), .failed(let message): return message
            }
        }
    }
}
