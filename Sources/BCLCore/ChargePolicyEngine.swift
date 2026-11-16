import Foundation
import BCLShared

public enum ChargeRequest: String {
    case allow
    case inhibit
}

/// Hysteresis for the charge band: inhibit at the limit, re-arm only once the charge falls
/// `BCLSettings.rearmBandPercent` below it, so the pack takes one charge run back instead of a drip
/// of short top-ups.
public struct ChargePolicyEngine {
    private var limitState: ChargeRequest = .allow

    public init() {}

    public mutating func evaluate(settings: BCLSettings, socPercent: Int) -> ChargeRequest {
        switch limitState {
        case .allow:
            if socPercent >= settings.limitPercent { limitState = .inhibit }
        case .inhibit:
            if socPercent <= settings.rearmPercent { limitState = .allow }
        }
        return limitState
    }
}
