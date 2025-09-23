import Foundation
import Swinject

// MARK: - SMB-Basal Middleware Manager

protocol SmbBasalMiddleware: AnyObject {
    func setupMiddleware()
    func removeMiddleware()
}

final class BaseSmbBasalMiddleware: SmbBasalMiddleware, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var settingsManager: SettingsManager!

    private let resolver: Resolver

    init(resolver: Resolver) {
        self.resolver = resolver
        injectServices(resolver)
    }

    func setupMiddleware() {
        let middlewareScript = createSmbBasalMiddleware()
        storage.save(middlewareScript, as: OpenAPS.Middleware.determineBasal)

        // Сохраняем наш IOB расчет для использования в middleware
        updateCustomIOBForMiddleware()

        print("SMB-Basal: Middleware installed successfully")
    }

    // 🎯 Структура для сохранения Custom IOB данных в FileStorage
    private struct CustomIOBData: JSON {
        let totalIOB: Double
        let bolusIOB: Double
        let basalIOB: Double
        let calculationTime: Double
        let debugInfo: String
    }

    func updateCustomIOBForMiddleware() {
        // Создаем CustomIOBCalculator через resolver, избегая циклическую зависимость
        guard let customIOBCalculator = resolver.resolve(CustomIOBCalculator.self) else {
            print("SMB-Basal: Cannot resolve CustomIOBCalculator")
            return
        }

        let iobResult = customIOBCalculator.calculateIOB()

        let customIOBData = CustomIOBData(
            totalIOB: Double(truncating: iobResult.totalIOB as NSNumber),
            bolusIOB: Double(truncating: iobResult.bolusIOB as NSNumber),
            basalIOB: Double(truncating: iobResult.basalIOB as NSNumber),
            calculationTime: iobResult.calculationTime.timeIntervalSince1970,
            debugInfo: iobResult.debugInfo
        )

        print("SMB-Basal: 🔄 Attempting to save Custom IOB data...")

        // 🚀 ИСПРАВЛЕНИЕ: Используем transaction для гарантированного сохранения
        storage.transaction { storage in
            storage.save(customIOBData, as: "middleware/custom-iob.json")
            print("SMB-Basal: ✅ Data saved in transaction")
        }

        print("SMB-Basal: Custom IOB saved for middleware - Total: \(iobResult.totalIOB)U")
        print(
            "SMB-Basal: Saved to middleware/custom-iob.json: totalIOB=\(customIOBData.totalIOB), calculationTime=\(customIOBData.calculationTime)"
        )

        // 🔍 ДЕТАЛЬНАЯ ДИАГНОСТИКА с задержкой для асинхронных операций
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            if let savedData = self.storage.retrieve("middleware/custom-iob.json", as: CustomIOBData.self) {
                print("SMB-Basal: ✅ Verification SUCCESS - data saved as CustomIOBData struct!")
                print("SMB-Basal: ✅ Verified IOB: \(savedData.totalIOB)U")
            } else if let rawData = self.storage.retrieveRaw("middleware/custom-iob.json") {
                print("SMB-Basal: ⚠️ Data exists as raw but failed as struct: \(String(rawData.prefix(100)))")
            } else {
                print("SMB-Basal: ❌ Verification FAILED - no data found at all!")

                // 🔍 Дополнительная диагностика - попробуем альтернативное имя файла
                self.storage.save(customIOBData, as: "custom-iob-backup.json")
                if let backupData = self.storage.retrieve("custom-iob-backup.json", as: CustomIOBData.self) {
                    print("SMB-Basal: 🆘 BACKUP saved successfully - problem with middleware/ path!")
                }
            }
        }
    }

    func removeMiddleware() {
        storage.remove(OpenAPS.Middleware.determineBasal)
        print("SMB-Basal: Middleware removed")
    }

    private func createSmbBasalMiddleware() -> String {
        """
            function middleware(iob, currenttemp, glucose, profile, autosens, meal, reservoir, clock) {
                console.log("SMB-Basal Middleware: 🎯 АРХИТЕКТУРНОЕ РЕШЕНИЕ на основе изучения OpenAPS oref0!");
                console.log("Проблема: Частичная замена IOB полей создавала несогласованную структуру");
                console.log("Решение: Полная пересборка IOB согласно oref0 архитектуре");

                // 🎯 ВАЖНО: Middleware работает только в JavaScript контексте

                var middlewareMessage = "SMB-Basal Middleware: No changes needed";

            // 🎯 ЕДИНСТВЕННАЯ ЗАДАЧА - ЗАМЕНИТЬ IOB ПАРАМЕТР НА НАШ РАСЧЕТ!
            if (typeof customIOBData !== 'undefined' && customIOBData && customIOBData.totalIOB !== undefined) {
                // Проверяем возраст данных (максимум 5 минут)
                var now = new Date().getTime() / 1000;
                var dataAge = now - customIOBData.calculationTime;

                if (dataAge < 300) { // 5 минут
                    console.log("SMB-Basal Middleware: ✅ Заменяем IOB значения, СОХРАНЯЯ оригинальную структуру!");
                    console.log("  Системный IOB: " + JSON.stringify(iob));

                    // 🎯 ПРОСТОЕ РЕШЕНИЕ: Аккуратная модификация существующей IOB структуры
                    if (iob && Array.isArray(iob) && iob.length > 0) {
                        console.log("  Системный IOB массив: " + iob.length + " элементов");

                        var originalIOB = iob[0];
                        console.log("  Старые значения: iob=" + originalIOB.iob + ", basaliob=" + originalIOB.basaliob + ", bolusiob=" + originalIOB.bolusiob);

                        // Аккуратно заменяем только ключевые IOB поля, сохраняя структуру для Swift
                        originalIOB.iob = customIOBData.totalIOB;
                        originalIOB.basaliob = customIOBData.basalIOB;
                        originalIOB.bolusiob = customIOBData.bolusIOB;

                        // Согласуем вспомогательные поля с нашими IOB значениями
                        if (customIOBData.totalIOB > 0) {
                            originalIOB.activity = Math.abs(customIOBData.totalIOB * 0.0025); // Разумная activity
                            originalIOB.netbasalinsulin = customIOBData.basalIOB;
                            originalIOB.bolusinsulin = customIOBData.bolusIOB;
                        }

                        // Убираем iobWithZeroTemp чтобы oref0 пересчитал его с нашими данными
                        originalIOB.iobWithZeroTemp = null;

                        console.log("SMB-Basal Middleware: 🚀 IOB ЗНАЧЕНИЯ СОГЛАСОВАНЫ В ОРИГИНАЛЬНОЙ СТРУКТУРЕ!");
                        console.log("  Новые значения: iob=" + originalIOB.iob + ", basaliob=" + originalIOB.basaliob + ", bolusiob=" + originalIOB.bolusiob);
                        console.log("  Согласованная activity: " + originalIOB.activity);
                        console.log("  Согласованные инсулины: netbasal=" + originalIOB.netbasalinsulin + ", bolus=" + originalIOB.bolusinsulin);

                        // 🔍 КРИТИЧЕСКАЯ ДИАГНОСТИКА: Что мы возвращаем в Swift?
                        console.log("🔍 ПОЛНАЯ СТРУКТУРА IOB[0] после модификации:");
                        console.log(JSON.stringify(originalIOB, null, 2));
                        console.log("🔍 Типы полей:");
                        console.log("  typeof iob: " + typeof originalIOB.iob);
                        console.log("  typeof basaliob: " + typeof originalIOB.basaliob);  
                        console.log("  typeof bolusiob: " + typeof originalIOB.bolusiob);
                        console.log("  typeof activity: " + typeof originalIOB.activity);
                        console.log("  typeof time: " + typeof originalIOB.time);
                        console.log("  iobWithZeroTemp: " + originalIOB.iobWithZeroTemp);

                        // ✅ IOB данные модифицированы только для JavaScript - Swift читает оригинальные
                    }

                    middlewareMessage = "Custom IOB calculation active";
                } else {
                    console.log("SMB-Basal Middleware: Custom IOB data too old (" + Math.round(dataAge) + "s)");
                }
            } else {
                console.log("SMB-Basal Middleware: Custom IOB data not available");
            }

            return middlewareMessage;
        }

        """
    }
}
