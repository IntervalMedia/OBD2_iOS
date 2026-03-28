import Foundation

struct LiveSample: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let rpm: Double?
    let speedKph: Int?
    let coolantTempC: Int?
    let throttlePositionPercent: Double?
    let batteryVoltage: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        rpm: Double?,
        speedKph: Int?,
        coolantTempC: Int?,
        throttlePositionPercent: Double?,
        batteryVoltage: Double?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.rpm = rpm
        self.speedKph = speedKph
        self.coolantTempC = coolantTempC
        self.throttlePositionPercent = throttlePositionPercent
        self.batteryVoltage = batteryVoltage
    }
}
