import Foundation

enum OBDCommandBuilder {
    static let initSequence: [String] = [
        "ATZ",
        "ATE0",
        "ATL0",
        "ATS0",
        "ATH0",
        "ATSP0"
    ]

    static let supportedPIDs = "0100"
    static let rpm = "010C"
    static let speed = "010D"
    static let coolantTemp = "0105"
    static let throttlePosition = "0111"
    static let storedDTCs = "03"
    static let clearDTCs = "04"
    static let vin = "0902"
    static let batteryVoltage = "ATRV"
}
