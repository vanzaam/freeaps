import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var autoOpenOnce = false

        var body: some View {
            Form {
                Section(header: Text("Model")) {
                    if let pumpState = state.pumpState {
                        Button {
                            state.setupPump = true
                        } label: {
                            HStack {
                                Image(uiImage: pumpState.image ?? UIImage()).padding()
                                Text(pumpState.name)
                            }
                        }
                        Button(role: .destructive) {
                            // Remove current pump to allow choosing another
                            state.provider.apsManager.pumpManager = nil
                        } label: {
                            Text("Remove pump")
                        }
                    } else {
                        Button("Add Omnipod DASH") { state.addPump(.omnipodDash) }
                        Button("Add Medtrum") { state.addPump(.medtrum) }
                        Button("Add Medtronic") { state.addPump(.minimed) }
                        Button("Add Omnipod") { state.addPump(.omnipod) }
                        Button("Add Simulator") { state.addPump(.simulator) }
                    }
                }
            }
            .onAppear(perform: configureView)
            .navigationTitle("Pump config")
            .navigationBarTitleDisplayMode(.automatic)
            .sheet(isPresented: $state.setupPump, onDismiss: {
                // nothing
            }) {
                if let pumpManager = state.provider.apsManager.pumpManager {
                    PumpSettingsView(pumpManager: pumpManager, completionDelegate: state)
                } else {
                    PumpSetupView(
                        pumpType: state.setupPumpType,
                        pumpInitialSettings: state.initialSettings,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            .onChange(of: state.pumpState) { newValue in
                // Open full settings automatically once, when entering from Settings and pump exists
                if !autoOpenOnce, newValue != nil, state.provider.apsManager.pumpManager != nil {
                    autoOpenOnce = true
                    state.setupPump = true
                }
            }
        }
    }
}
