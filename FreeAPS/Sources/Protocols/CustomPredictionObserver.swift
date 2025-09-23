import Foundation

// 🎯 Протокол для получения результатов Custom Prediction Service
protocol CustomPredictionObserver {
    func customPredictionDidUpdate(_ prediction: CustomPredictionResult)
}
