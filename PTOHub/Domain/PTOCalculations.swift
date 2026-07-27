import Foundation

enum PTOCalculation {
    static func balance(entries: [LedgerEntry], employeeID: UUID) -> Double {
        entries.lazy.filter { $0.employeeID == employeeID }.reduce(0) { $0 + $1.hours }
    }

    static func reservedHours(requests: [PTORequest], employeeID: UUID, today: DateOnly) -> Double {
        requests.lazy
            .filter { $0.employeeID == employeeID && ($0.status == .pending || $0.status == .approved) }
            .flatMap(\.days)
            .filter { $0.date >= today }
            .reduce(0) { $0 + Double($1.hours) }
    }

    static func usedYearToDate(entries: [LedgerEntry], employeeID: UUID, year: Int) -> Double {
        abs(entries.lazy.filter {
            $0.employeeID == employeeID && $0.type == "usage" && $0.effectiveDate.year == year
        }.reduce(0) { $0 + $1.hours })
    }

    static func earnedYearToDate(entries: [LedgerEntry], employeeID: UUID, year: Int) -> Double {
        entries.lazy.filter {
            $0.employeeID == employeeID && ($0.type == "accrual" || $0.type == "accrual_adjustment") && $0.effectiveDate.year == year
        }.reduce(0) { $0 + $1.hours }
    }

    static func tier(for profile: StaffProfile, tiers: [PolicyTier], today: DateOnly) -> PolicyTier? {
        let calendar = Calendar(identifier: .gregorian)
        let start = profile.hireDate.date()
        let end = today.date()
        let months = calendar.dateComponents([.month], from: start, to: end).month ?? 0
        return tiers.first { months >= $0.minimumMonths && ($0.maximumMonths == nil || months < $0.maximumMonths!) }
    }
}

enum PTORequestValidator {
    static func validate(
        draft: PTORequestDraft,
        available: Double,
        alreadyReserved: Double,
        blackouts: [BlackoutPeriod],
        policy: PolicySettings,
        today: DateOnly
    ) throws {
        guard !draft.days.isEmpty else { throw ValidationError("Add at least one requested date.") }
        guard draft.days.allSatisfy({ policy.allowedRequestHours.contains($0.hours) }) else {
            throw ValidationError("Choose an allowed number of hours for each date.")
        }
        guard Set(draft.days.map(\.date)).count == draft.days.count else {
            throw ValidationError("Each requested date can appear only once.")
        }
        guard draft.days.allSatisfy({ $0.date >= today }) else {
            throw ValidationError("PTO dates cannot be in the past.")
        }
        if draft.category.isPlanned {
            let firstAllowed = today.adding(days: policy.plannedNoticeDays)
            guard draft.days.allSatisfy({ $0.date >= firstAllowed }) else {
                throw ValidationError("Vacation and personal PTO require \(policy.plannedNoticeDays) days’ notice.")
            }
            guard !draft.days.contains(where: { day in blackouts.contains(where: { $0.contains(day.date) }) }) else {
                throw ValidationError("Planned PTO cannot overlap a blackout period.")
            }
        } else if draft.privateNote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw ValidationError("Illness and bereavement requests require a private note.")
        }
        let requested = Double(draft.days.reduce(0) { $0 + $1.hours })
        guard available - alreadyReserved - requested >= 0 else {
            throw ValidationError("This request exceeds projected available PTO.")
        }
    }
}

enum RequestDecisionValidator {
    static func validatedNote(for status: PTORequestStatus, note: String?) throws -> String? {
        guard status == .approved || status == .rejected else {
            throw ValidationError("Choose approve or reject.")
        }
        guard status == .rejected else { return nil }

        let reason = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reason.isEmpty else {
            throw ValidationError("Enter a reason before rejecting this request.")
        }
        return reason
    }
}

enum RequestPermission {
    static func canReview(
        request: PTORequest,
        requester: StaffProfile?,
        actor: StaffProfile
    ) -> Bool {
        guard actor.role.isManager,
              request.status == .pending,
              request.employeeID != actor.id else { return false }
        if requester?.role.isManager == true { return actor.role == .ownerAdmin }
        return true
    }

    static func canCancel(
        request: PTORequest,
        profile: StaffProfile,
        today: DateOnly
    ) -> Bool {
        guard request.employeeID == profile.id,
              request.status == .pending || request.status == .approved,
              let firstDate = request.firstDate else { return false }
        return firstDate >= today
    }
}

struct ValidationError: LocalizedError, Equatable, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
