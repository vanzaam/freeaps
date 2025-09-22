import Foundation

struct Preferences: JSON {
    var maxIOB: Decimal = 0
    var maxDailySafetyMultiplier: Decimal = 3
    var currentBasalSafetyMultiplier: Decimal = 4
    var autosensMax: Decimal = 1.2
    var autosensMin: Decimal = 0.7
    var rewindResetsAutosens: Bool = true
    var highTemptargetRaisesSensitivity: Bool = false
    var lowTemptargetLowersSensitivity: Bool = false
    var sensitivityRaisesTarget: Bool = true
    var resistanceLowersTarget: Bool = false
    var advTargetAdjustments: Bool = false
    var exerciseMode: Bool = false
    var halfBasalExerciseTarget: Decimal = 160
    var maxCOB: Decimal = 120
    var wideBGTargetRange: Bool = false
    var skipNeutralTemps: Bool = false
    var unsuspendIfNoTemp: Bool = false
    var bolusSnoozeDIADivisor: Decimal = 2
    var min5mCarbimpact: Decimal = 8
    var autotuneISFAdjustmentFraction: Decimal = 1.0
    var remainingCarbsFraction: Decimal = 1.0
    var remainingCarbsCap: Decimal = 90
    var enableUAM: Bool = false
    var a52RiskEnable: Bool = false
    var enableSMBWithCOB: Bool = false
    var enableSMBWithTemptarget: Bool = false
    var enableSMBAlways: Bool = false
    var enableSMBAfterCarbs: Bool = false
    var allowSMBWithHighTemptarget: Bool = false
    var maxSMBBasalMinutes: Decimal = 30
    var maxUAMSMBBasalMinutes: Decimal = 30
    var smbInterval: Decimal = 3
    var bolusIncrement: Decimal = 0.1
    var curve: InsulinCurve = .rapidActing
    var useCustomPeakTime: Bool = false
    var insulinPeakTime: Decimal = 75
    var carbsReqThreshold: Decimal = 1.0
    var noisyCGMTargetMultiplier: Decimal = 1.3
    var suspendZerosIOB: Bool = true

    // MARK: - Loop CarbStore SMB Settings

    var enableLoopCarbSMB: Bool = false
    var carbSMBMinDelta: Decimal = 5.0
    var carbSMBMaxDose: Decimal = 1.0
    var carbSMBSafetyMultiplier: Decimal = 0.8

    // MARK: - Test Setting (будет удалена после тестирования)

    var testSettingStub: Bool = false

    var timestamp: Date?
}

extension Preferences {
    private enum CodingKeys: String, CodingKey {
        case maxIOB = "max_iob"
        case maxDailySafetyMultiplier = "max_daily_safety_multiplier"
        case currentBasalSafetyMultiplier = "current_basal_safety_multiplier"
        case autosensMax = "autosens_max"
        case autosensMin = "autosens_min"
        case rewindResetsAutosens = "rewind_resets_autosens"
        case highTemptargetRaisesSensitivity = "high_temptarget_raises_sensitivity"
        case lowTemptargetLowersSensitivity = "low_temptarget_lowers_sensitivity"
        case sensitivityRaisesTarget = "sensitivity_raises_target"
        case resistanceLowersTarget
        case advTargetAdjustments = "adv_target_adjustments"
        case exerciseMode = "exercise_mode"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case wideBGTargetRange = "wide_bg_target_range"
        case skipNeutralTemps = "skip_neutral_temps"
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case bolusSnoozeDIADivisor = "bolussnooze_dia_divisor"
        case min5mCarbimpact = "min_5m_carbimpact"
        case autotuneISFAdjustmentFraction = "autotune_isf_adjustmentFraction"
        case remainingCarbsFraction
        case remainingCarbsCap
        case enableUAM
        case a52RiskEnable = "A52_risk_enable"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case smbInterval = "SMBInterval"
        case bolusIncrement = "bolus_increment"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case carbsReqThreshold
        case noisyCGMTargetMultiplier
        case suspendZerosIOB = "suspend_zeros_iob"

        // MARK: - Loop CarbStore SMB Settings

        case enableLoopCarbSMB = "enable_loop_carb_smb"
        case carbSMBMinDelta = "carb_smb_min_delta"
        case carbSMBMaxDose = "carb_smb_max_dose"
        case carbSMBSafetyMultiplier = "carb_smb_safety_multiplier"
        case testSettingStub = "test_setting_stub"
        case timestamp
    }
}

extension Preferences {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Декодируем стандартные поля
        maxIOB = try container.decode(Decimal.self, forKey: .maxIOB)
        maxDailySafetyMultiplier = try container.decode(Decimal.self, forKey: .maxDailySafetyMultiplier)
        currentBasalSafetyMultiplier = try container.decode(Decimal.self, forKey: .currentBasalSafetyMultiplier)
        autosensMax = try container.decode(Decimal.self, forKey: .autosensMax)
        autosensMin = try container.decode(Decimal.self, forKey: .autosensMin)
        rewindResetsAutosens = try container.decode(Bool.self, forKey: .rewindResetsAutosens)
        highTemptargetRaisesSensitivity = try container.decode(Bool.self, forKey: .highTemptargetRaisesSensitivity)
        lowTemptargetLowersSensitivity = try container.decode(Bool.self, forKey: .lowTemptargetLowersSensitivity)
        sensitivityRaisesTarget = try container.decode(Bool.self, forKey: .sensitivityRaisesTarget)
        resistanceLowersTarget = try container.decode(Bool.self, forKey: .resistanceLowersTarget)
        advTargetAdjustments = try container.decode(Bool.self, forKey: .advTargetAdjustments)
        exerciseMode = try container.decode(Bool.self, forKey: .exerciseMode)
        halfBasalExerciseTarget = try container.decode(Decimal.self, forKey: .halfBasalExerciseTarget)
        maxCOB = try container.decode(Decimal.self, forKey: .maxCOB)
        wideBGTargetRange = try container.decode(Bool.self, forKey: .wideBGTargetRange)
        skipNeutralTemps = try container.decode(Bool.self, forKey: .skipNeutralTemps)
        unsuspendIfNoTemp = try container.decode(Bool.self, forKey: .unsuspendIfNoTemp)
        bolusSnoozeDIADivisor = try container.decode(Decimal.self, forKey: .bolusSnoozeDIADivisor)
        min5mCarbimpact = try container.decode(Decimal.self, forKey: .min5mCarbimpact)
        autotuneISFAdjustmentFraction = try container.decode(Decimal.self, forKey: .autotuneISFAdjustmentFraction)
        remainingCarbsFraction = try container.decode(Decimal.self, forKey: .remainingCarbsFraction)
        remainingCarbsCap = try container.decode(Decimal.self, forKey: .remainingCarbsCap)
        enableUAM = try container.decode(Bool.self, forKey: .enableUAM)
        a52RiskEnable = try container.decode(Bool.self, forKey: .a52RiskEnable)
        enableSMBWithCOB = try container.decode(Bool.self, forKey: .enableSMBWithCOB)
        enableSMBWithTemptarget = try container.decode(Bool.self, forKey: .enableSMBWithTemptarget)
        enableSMBAlways = try container.decode(Bool.self, forKey: .enableSMBAlways)
        enableSMBAfterCarbs = try container.decode(Bool.self, forKey: .enableSMBAfterCarbs)
        allowSMBWithHighTemptarget = try container.decode(Bool.self, forKey: .allowSMBWithHighTemptarget)
        maxSMBBasalMinutes = try container.decode(Decimal.self, forKey: .maxSMBBasalMinutes)
        maxUAMSMBBasalMinutes = try container.decode(Decimal.self, forKey: .maxUAMSMBBasalMinutes)
        smbInterval = try container.decode(Decimal.self, forKey: .smbInterval)
        bolusIncrement = try container.decode(Decimal.self, forKey: .bolusIncrement)
        curve = try container.decode(InsulinCurve.self, forKey: .curve)
        useCustomPeakTime = try container.decode(Bool.self, forKey: .useCustomPeakTime)
        insulinPeakTime = try container.decode(Decimal.self, forKey: .insulinPeakTime)
        carbsReqThreshold = try container.decode(Decimal.self, forKey: .carbsReqThreshold)
        noisyCGMTargetMultiplier = try container.decode(Decimal.self, forKey: .noisyCGMTargetMultiplier)
        suspendZerosIOB = try container.decode(Bool.self, forKey: .suspendZerosIOB)

        // Безопасно декодируем новые Loop CarbStore SMB поля (с fallback на default значения)
        enableLoopCarbSMB = try container.decodeIfPresent(Bool.self, forKey: .enableLoopCarbSMB) ?? false
        carbSMBMinDelta = try container.decodeIfPresent(Decimal.self, forKey: .carbSMBMinDelta) ?? 5.0
        carbSMBMaxDose = try container.decodeIfPresent(Decimal.self, forKey: .carbSMBMaxDose) ?? 1.0
        carbSMBSafetyMultiplier = try container.decodeIfPresent(Decimal.self, forKey: .carbSMBSafetyMultiplier) ?? 0.8

        // Тестовая заглушка (будет удалена)
        testSettingStub = try container.decodeIfPresent(Bool.self, forKey: .testSettingStub) ?? false

        timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp)
    }
}

enum InsulinCurve: String, JSON, Identifiable, CaseIterable {
    case rapidActing = "rapid-acting"
    case ultraRapid = "ultra-rapid"
    case bilinear

    var id: InsulinCurve { self }
}
