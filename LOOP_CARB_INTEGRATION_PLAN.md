# 🚀 План интеграции системы углеводов Loop в OpenAPS

## 📋 Обзор проекта

**Цель**: Интегрировать гениальную систему списания углеводов Loop в OpenAPS, сохранив лучшие идеи OpenAPS (SMB, ретроспективная коррекция) и заменив систему meal.js на более точную Loop-реализацию.

**Ключевые преимущества Loop**:
- Точное указание времени углеводов
- Правильное списание с учётом скорости абсорбции  
- Интеграция с HealthKit
- Научно обоснованные модели абсорбции

---

## 🎯 Этапы реализации (по приоритету)

### **Этап 1: Сервис списания углеводов (CarbStore)**
*Время: 3-5 дней | Приоритет: КРИТИЧЕСКИЙ*

#### 1.1 Создание CarbAccountingService
**Файл**: `FreeAPS/Sources/Services/Carbs/CarbAccountingService.swift`

**Функциональность**:
- Обёртка над LoopKit CarbStore
- Combine publishers для реактивного обновления UI
- Интеграция с Nightscout
- Безопасная обработка HealthKit (опционально)

**Ключевые методы**:
```swift
@MainActor
class CarbAccountingService: ObservableObject {
    @Published var cob: Decimal = 0
    @Published var activeCarbEntries: [CarbEntry] = []
    @Published var carbEffects: [GlucoseEffect] = []
    @Published var absorptionProgress: [Double] = []
    
    func addCarbEntry(amount: Decimal, date: Date, absorptionDuration: TimeInterval)
    func updateCarbEntry(_ entry: CarbEntry)
    func deleteCarbEntry(_ entry: CarbEntry)
    func syncToNightscout() async
    func calculateCOB() -> Decimal
}
```

#### 1.2 Интеграция с LoopKit CarbStore
- Использовать существующий `Dependencies/LoopKit/LoopKit/CarbKit/CarbStore.swift`
- Настроить HealthKit интеграцию (graceful fallback если недоступен)
- Реализовать конверсию в Nightscout treatments

#### 1.3 Dependency Injection
**Файл**: `FreeAPS/Sources/Services/DI/ServiceAssembly.swift`
```swift
container.register(CarbAccountingService.self) { resolver in
    let carbStore = CarbStore(healthStore: HKHealthStore(), observeHealthKitData: true)
    return CarbAccountingService(carbStore: carbStore)
}.inObjectScope(.container)
```

**Критерии готовности**:
- ✅ CarbAccountingService создан и зарегистрирован в DI
- ✅ Базовые CRUD операции с углеводами работают
- ✅ COB рассчитывается корректно
- ✅ Nightscout синхронизация работает

---

### **Этап 2: Новый ввод углеводов как в Loop**
*Время: 4-7 дней | Приоритет: ВЫСОКИЙ*

#### 2.1 UI для добавления углеводов
**Файл**: `FreeAPS/Sources/Modules/AddCarbsLoop/View/AddCarbsLoopView.swift`

**Компоненты**:
- `CarbQuantityInput` - ввод количества углеводов
- `MealTimeInput` - выбор времени приёма пищи
- `AbsorptionSpeedPicker` - выбор скорости абсорбции (быстро/средне/медленно)
- `FoodTypeRow` - тип пищи (опционально)
- `COBPreview` - предварительный расчёт COB

#### 2.2 ViewModel для ввода углеводов
**Файл**: `FreeAPS/Sources/Modules/AddCarbsLoop/AddCarbsLoopViewModel.swift`

```swift
@MainActor
class AddCarbsLoopViewModel: ObservableObject {
    @Published var amount: Decimal = 0
    @Published var mealTime: Date = Date()
    @Published var absorptionSpeed: AbsorptionSpeed = .medium
    @Published var estimatedCOB: Decimal = 0
    
    @Injected() private var carbService: CarbAccountingService?
    
    func addCarbEntry() async
    func calculateEstimatedCOB()
}
```

#### 2.3 Интеграция с существующим экраном
Заменить `FreeAPS/Sources/Modules/AddCarbs/View/AddCarbsRootView.swift` на новую реализацию

**Критерии готовности**:
- ✅ UI для ввода углеводов создан
- ✅ Интеграция с CarbAccountingService работает
- ✅ Предварительный расчёт COB отображается
- ✅ Nightscout синхронизация при добавлении

---

### **Этап 3: Обновление главного экрана**
*Время: 2-4 дня | Приоритет: СРЕДНИЙ*

#### 3.1 Новый DashboardView
**Файл**: `FreeAPS/Sources/Modules/Dashboard/View/DashboardRootView.swift`

**Макет как в Loop**:
- Header с ключевыми метриками (глюкоза, IOB, COB)
- Основной график с синхронизированными данными
- Вертикальная линия событий
- Bottom controls для быстрых действий

#### 3.2 График в стиле Loop (Path API)
**Файл**: `FreeAPS/Sources/Modules/Dashboard/Charts/LoopStyleMainChart.swift`

**Слои графика**:
- Глюкоза + предсказание (синяя линия + пунктир)
- IOB (Insulin on Board) - оранжевая заливка
- COB (Carbs on Board) - жёлтая заливка  
- Подача инсулина - вертикальные линии
- Синхронизированная вертикальная линия событий

#### 3.3 ViewModel для Dashboard
**Файл**: `FreeAPS/Sources/Modules/Dashboard/DashboardStateModel.swift`

```swift
@MainActor
class DashboardStateModel: ObservableObject {
    @Published var glucose: [GlucoseReading] = []
    @Published var predictedGlucose: [PredictedGlucose] = []
    @Published var iob: Decimal = 0
    @Published var cob: Decimal = 0
    @Published var delivery: [DeliveryEvent] = []
    
    @Injected() private var carbService: CarbAccountingService?
    @Injected() private var insulinService: InsulinDeliveryService?
    
    func updateDashboard() {
        // Объединить данные из всех сервисов
    }
}
```

**Критерии готовности**:
- ✅ Новый DashboardView создан
- ✅ График отображает все данные корректно
- ✅ Path API используется для производительности
- ✅ Интерактивность работает (hover, touch)

---

### **Этап 4: Переключение расчётов (отключение meal.js)**
*Время: 5-10 дней | Приоритет: ВЫСОКИЙ*

#### 4.1 Флаг конфигурации
**Файл**: `ConfigOverride.xcconfig`
```
# Переключение между системами углеводов
USE_LOOP_CARB_ABSORPTION = YES  # Использовать Loop систему
# USE_LOOP_CARB_ABSORPTION = NO  # Использовать meal.js (старая система)
```

#### 4.2 Модификация OpenAPS
**Файл**: `FreeAPS/Sources/APS/OpenAPS/OpenAPS.swift`

```swift
func mealCalculation() -> MealResult {
    guard let useLoopCarbs = Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_CARB_ABSORPTION") as? Bool,
          useLoopCarbs else {
        // Использовать старую систему meal.js
        return MealCalculator.compute(inputs: mealInputs)
    }
    
    // Использовать CarbAccountingService
    guard let carbService = carbService else {
        return MealResult()
    }
    
    return carbService.calculateMealEffect()
}
```

#### 4.3 Интеграция COB в Suggestion
```swift
extension Suggestion {
    var cob: Decimal? {
        guard let useLoopCarbs = Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_CARB_ABSORPTION") as? Bool,
              useLoopCarbs else {
            // Fallback к старой системе
            return mealCalculation().mealCOB
        }
        
        return carbService?.cob ?? 0
    }
}
```

#### 4.4 Обновление тестов
**Файл**: `FreeAPSTests/MealParityTests.swift`
- Добавить тесты для новой системы COB
- Обновить эталонные значения
- Создать A/B тесты между системами

**Критерии готовности**:
- ✅ Флаг конфигурации работает
- ✅ Переключение между системами работает
- ✅ COB рассчитывается корректно в обеих системах
- ✅ Тесты обновлены и проходят

---

### **Этап 5: SMB-адаптация**
*Время: 7-14 дней | Приоритет: СРЕДНИЙ*

#### 5.1 Интеграция с SMB логикой
```swift
// В SMB расчётах использовать данные из CarbAccountingService
let carbEffects = carbService?.carbEffects ?? []
let remainingCarbImpact = carbService?.remainingCarbImpact ?? 0

// Адаптировать SMB под Loop-данные
let adaptationFactor = carbService?.absorptionSpeedFactor ?? 1.0
let adjustedCarbEffect = carbEffect * adaptationFactor
```

#### 5.2 Динамическое обновление carbEffect
- Использовать `CarbMath.glucoseEffectFromCarbs()` из LoopKit
- Обновлять в реальном времени на основе скорости абсорбции
- Учитывать ретроспективную коррекцию

#### 5.3 Адаптивные коэффициенты для SMB
- Корректировать SMB на основе реальной скорости абсорбции углеводов
- Интегрировать с ретроспективной коррекцией
- Улучшить предсказание глюкозы

**Критерии готовности**:
- ✅ SMB использует данные из CarbAccountingService
- ✅ Адаптивные коэффициенты работают
- ✅ Ретроспективная коррекция интегрирована
- ✅ Предсказание глюкозы улучшено

---

## 📁 Файловая структура

```
FreeAPS/Sources/
├── Services/Carbs/
│   ├── CarbAccountingService.swift          # Основной сервис
│   ├── CarbStoreAdapter.swift              # Адаптер для LoopKit
│   ├── NightscoutCarbSync.swift            # Синхронизация с Nightscout
│   └── CarbMathExtensions.swift            # Расширения для расчётов
├── Modules/Dashboard/
│   ├── View/
│   │   ├── DashboardRootView.swift         # Новый главный экран
│   │   └── DashboardHeader.swift           # Header с метриками
│   ├── Charts/
│   │   ├── LoopStyleMainChart.swift        # Основной график
│   │   ├── GlucoseChart.swift              # График глюкозы
│   │   ├── IOBChart.swift                  # График IOB
│   │   ├── COBChart.swift                  # График COB
│   │   └── DeliveryChart.swift             # График подачи инсулина
│   └── DashboardStateModel.swift           # ViewModel
├── Modules/AddCarbsLoop/
│   ├── View/
│   │   ├── AddCarbsLoopView.swift          # Основной экран ввода
│   │   └── Components/
│   │       ├── CarbQuantityInput.swift     # Ввод количества
│   │       ├── MealTimeInput.swift         # Выбор времени
│   │       ├── AbsorptionSpeedPicker.swift # Выбор скорости
│   │       ├── FoodTypeRow.swift           # Тип пищи
│   │       └── COBPreview.swift            # Предварительный COB
│   └── AddCarbsLoopViewModel.swift         # ViewModel
└── APS/OpenAPS/
    ├── OpenAPS.swift                       # Модифицированный (флаги)
    ├── CarbIntegrationAdapter.swift        # Адаптер интеграции
    └── MealCalculator.swift                # Оставить для совместимости
```

---

## ⚙️ Технические детали

### **Dependency Injection**
```swift
// В ServiceAssembly.swift
container.register(CarbAccountingService.self) { resolver in
    let carbStore = CarbStore(healthStore: HKHealthStore(), observeHealthKitData: true)
    return CarbAccountingService(carbStore: carbStore)
}.inObjectScope(.container)

container.register(CarbStore.self) { resolver in
    CarbStore(healthStore: HKHealthStore(), observeHealthKitData: true)
}.inObjectScope(.container)
```

### **Nightscout интеграция**
```swift
extension CarbEntry {
    func toNightscoutTreatment() -> [String: Any] {
        return [
            "eventType": "Carbs",
            "created_at": created_at.iso8601String,
            "carbs": amount,
            "enteredBy": "OpenAPS",
            "absorptionTime": absorptionDuration
        ]
    }
}
```

### **Конфигурация**
```swift
// В ConfigOverride.xcconfig
USE_LOOP_CARB_ABSORPTION = YES
CARB_ABSORPTION_DEFAULT_SPEED = medium
CARB_ABSORPTION_FAST_MINUTES = 15
CARB_ABSORPTION_MEDIUM_MINUTES = 30
CARB_ABSORPTION_SLOW_MINUTES = 60
```

---

## 📊 Оценка времени и сложности

| Этап | Время | Сложность | Зависимости | Критичность |
|------|-------|-----------|-------------|-------------|
| 1. CarbStore сервис | 3-5 дней | Средняя | LoopKit | КРИТИЧЕСКАЯ |
| 2. UI ввода углеводов | 4-7 дней | Средняя | SwiftUI | ВЫСОКАЯ |
| 3. Главный экран | 2-4 дня | Низкая | Path API | СРЕДНЯЯ |
| 4. Отключение meal.js | 5-10 дней | Высокая | OpenAPS | ВЫСОКАЯ |
| 5. SMB адаптация | 7-14 дней | Высокая | Алгоритмы | СРЕДНЯЯ |

**Общее время**: 4-6 недель
**MVP (этапы 1-3)**: 2-3 недели

---

## 🎯 Критерии успеха

### **Этап 1 - CarbStore сервис**
- ✅ CarbAccountingService создан и работает
- ✅ COB рассчитывается корректно
- ✅ Nightscout синхронизация работает
- ✅ HealthKit интеграция (опционально)

### **Этап 2 - UI ввода углеводов**
- ✅ Красивый UI как в Loop
- ✅ Все поля ввода работают
- ✅ Предварительный расчёт COB
- ✅ Интеграция с CarbAccountingService

### **Этап 3 - Главный экран**
- ✅ Новый DashboardView создан
- ✅ График отображает все данные
- ✅ Path API для производительности
- ✅ Интерактивность работает

### **Этап 4 - Переключение расчётов**
- ✅ Флаг конфигурации работает
- ✅ Переключение между системами
- ✅ COB в обеих системах корректен
- ✅ Тесты обновлены

### **Этап 5 - SMB адаптация**
- ✅ SMB использует Loop данные
- ✅ Адаптивные коэффициенты
- ✅ Улучшенное предсказание

---

## 🚀 Преимущества после интеграции

### **Для пользователей**
- ✅ Точное указание времени углеводов
- ✅ Правильное списание с учётом типа пищи
- ✅ Красивый UI как в Loop
- ✅ Интеграция с HealthKit
- ✅ Более точное предсказание глюкозы

### **Для разработчиков**  
- ✅ Научно обоснованная модель абсорбции
- ✅ Единая система управления углеводами
- ✅ Лучшая производительность (Path API)
- ✅ Совместимость с Loop экосистемой
- ✅ Модульная архитектура

### **Для OpenAPS**
- ✅ Сохранение всех OpenAPS преимуществ
- ✅ Улучшение UX до уровня Loop
- ✅ Более точное предсказание глюкозы
- ✅ Готовность к интеграции с Loop алгоритмами
- ✅ Конкурентное преимущество

---

## ⚡ Первые шаги (СЕГОДНЯ)

1. **Создать CarbAccountingService** (день 1-2)
2. **Добавить UI для ввода углеводов** (день 3-5)  
3. **Обновить главный экран** (день 6-8)
4. **Протестировать на реальном устройстве**
5. **Постепенно переключить расчёты**

**Готов начать с первого этапа!** 🚀

---

## 📝 Лог прогресса

- [ ] **Этап 1**: CarbAccountingService создан
- [ ] **Этап 1**: CarbStore интеграция работает
- [ ] **Этап 1**: Nightscout синхронизация работает
- [ ] **Этап 2**: UI ввода углеводов создан
- [ ] **Этап 2**: Интеграция с CarbAccountingService
- [ ] **Этап 3**: DashboardView создан
- [ ] **Этап 3**: График в стиле Loop работает
- [ ] **Этап 4**: Флаг конфигурации добавлен
- [ ] **Этап 4**: Переключение систем работает
- [ ] **Этап 5**: SMB адаптация завершена

---

*Последнее обновление: 2025-01-27*
*Статус: Готов к началу реализации*
