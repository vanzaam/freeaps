import Foundation

/// Данные глюкозы для графиков
struct GlucoseReading {
    let value: Decimal
    let date: Date
}

/// Прогнозируемая глюкоза
struct PredictedGlucose {
    let value: Decimal
    let date: Date
}

/// Данные IOB для графиков
struct IOBData {
    let value: Decimal
    let date: Date
}

/// Данные COB для графиков
struct COBData {
    let value: Decimal
    let date: Date
}

/// События подачи инсулина для графиков
struct DeliveryEvent {
    let amount: Decimal
    let date: Date
    let type: DeliveryType
}

enum DeliveryType {
    case bolus
    case basal
    case tempBasal
}
