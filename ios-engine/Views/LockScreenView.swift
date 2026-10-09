import SwiftUI

public struct LockScreenView: View {
    @ObservedObject var licenseService = LicenseService.shared
    @State private var inputKey: String = ""
    @State private var copiedHWID: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer().frame(height: 20)
                
                // Brand Header with New Quantum Reactor Logo
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 110, height: 110)
                            .overlay(
                                Image("Logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [ThemeColors.cyanGlow, ThemeColors.neonPurple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2.5
                                    )
                                    .allowsHitTesting(false)
                            )
                            .shadow(color: ThemeColors.cyanGlow.opacity(0.6), radius: 24, x: 0, y: 8)
                    }
                    
                    Text("iOS ENGINE")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, ThemeColors.cyanGlow],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("LIQUID GLASS GAMING ENVIRONMENT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeColors.glassTextMuted)
                        .tracking(1.8)
                }
                
                // Hardware ID Card
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "iphone.gen3")
                            .foregroundColor(ThemeColors.cyanGlow)
                        Text("DEVICE HARDWARE ID (HWID)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeColors.glassTextMuted)
                        Spacer()
                        
                        Button(action: {
                            UIPasteboard.general.string = licenseService.deviceHWID
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            copiedHWID = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedHWID = false
                            }
                        }) {
                            Text(copiedHWID ? "COPIED" : "COPY")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(copiedHWID ? ThemeColors.electricGreen : ThemeColors.cyanGlow)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(6)
                        }
                    }
                    
                    Text(licenseService.deviceHWID)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 16, glowColor: ThemeColors.cyanGlow.opacity(0.4), strokeWidth: 0.8)
                .padding(.horizontal, 24)
                
                // Key Verification Card
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ENTER LICENSE KEY")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeColors.glassTextMuted)
                        
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(ThemeColors.cyanGlow)
                            
                            TextField("XXXX-XXXX-XXXX-XXXX", text: $inputKey)
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                                .textInputAutocapitalization(.characters)
                                .disableAutocorrection(true)
                            
                            if !inputKey.isEmpty {
                                Button(action: { inputKey = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color.white.opacity(0.4))
                                }
                            }
                            
                            Button(action: {
                                if let pasted = UIPasteboard.general.string {
                                    inputKey = pasted
                                }
                            }) {
                                Image(systemName: "doc.on.clipboard")
                                    .foregroundColor(ThemeColors.cyanGlow)
                            }
                        }
                        .padding(14)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                .allowsHitTesting(false)
                        )
                    }
                    
                    if let error = licenseService.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(ThemeColors.dangerRed)
                            Text(error)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(ThemeColors.dangerRed)
                            Spacer()
                        }
                        .padding(12)
                        .background(ThemeColors.dangerRed.opacity(0.12))
                        .cornerRadius(10)
                    }
                    
                    if licenseService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: ThemeColors.cyanGlow))
                            .scaleEffect(1.2)
                            .frame(height: 50)
                    } else {
                        GlowingButton(title: "VERIFY & UNLOCK", icon: "lock.open.fill", primaryColor: ThemeColors.cyanGlow) {
                            Task {
                                await licenseService.activateKey(inputKey)
                            }
                        }
                    }
                }
                .padding(22)
                .liquidGlass(cornerRadius: 22, glowColor: ThemeColors.cyanGlow)
                .padding(.horizontal, 24)
                
                // Quick Test Presets
                VStack(spacing: 10) {
                    Text("QUICK TEST KEYS (TAP TO FILL):")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.4))
                    
                    HStack(spacing: 8) {
                        Button(action: { inputKey = "VIP-GAMER-2026" }) {
                            Text("VIP-GAMER-2026")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(ThemeColors.cyanGlow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                        }
                        
                        Button(action: { inputKey = "ENGINE-TRIAL-7D" }) {
                            Text("ENGINE-TRIAL-7D")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(ThemeColors.neonPurple)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.06))
                                .cornerRadius(8)
                        }
                    }
                }
                
                Spacer().frame(height: 30)
            }
        }
    }
}
