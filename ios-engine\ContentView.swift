import SwiftUI

public struct ContentView: View {
    @ObservedObject var licenseService = LicenseService.shared
    
    public init() {}
    
    public var body: some View {
        ZStack {
            // High-tech Liquid Glass Animated Loop Background
            BackgroundMeshView()
            
            if licenseService.isAuthenticated {
                DashboardView()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
            } else {
                LockScreenView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: licenseService.isAuthenticated)
        .alert(isPresented: $licenseService.isRevokedAlertPresented) {
            Alert(
                title: Text("ACCESS TERMINATED"),
                message: Text(licenseService.revocationReason.isEmpty ? "Your license was revoked by the administrator in real time." : licenseService.revocationReason),
                dismissButton: .default(Text("UNDERSTOOD")) {
                    licenseService.isRevokedAlertPresented = false
                }
            )
        }
    }
}
