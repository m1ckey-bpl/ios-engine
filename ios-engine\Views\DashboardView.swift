import SwiftUI

public struct DashboardView: View {
    @ObservedObject var licenseService = LicenseService.shared
    @ObservedObject var engineManager = BackgroundEngineManager.shared
    @State private var showFilePicker: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 22) {
                Spacer().frame(height: 10)
                
                // Top Navigation Bar
                HStack {
                    HStack(spacing: 10) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iOS ENGINE")
                                .font(.system(size: 16, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("VERSION 1.0.0")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeColors.glassTextMuted)
                        }
                    }
                    
                    Spacer()
                    
                    // VIP Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ThemeColors.electricGreen)
                            .frame(width: 7, height: 7)
                        Text("PRO VIP")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ThemeColors.electricGreen.opacity(0.15))
                    .cornerRadius(20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(ThemeColors.electricGreen.opacity(0.4), lineWidth: 1)
                    )
                    
                    Button(action: {
                        licenseService.logout()
                    }) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                
                // User & Countdown Glass Card
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CUSTOMER ACCOUNT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeColors.glassTextMuted)
                            
                            Text(licenseService.currentLicense?.customerName ?? "VIP Member")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 26))
                            .foregroundColor(ThemeColors.cyanGlow)
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    // Live Countdown Digital Display
                    VStack(spacing: 6) {
                        Text("LICENSE TIME REMAINING")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeColors.glassTextMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text(licenseService.countdownDisplay)
                            .font(.system(size: 24, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [ThemeColors.cyanGlow, .white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(ThemeColors.cyanGlow.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(20)
                .liquidGlass(cornerRadius: 22, glowColor: ThemeColors.cyanGlow)
                .padding(.horizontal, 24)
                
                // File Import & Analyzer Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("ENVIRONMENT FILE PAYLOAD")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeColors.glassTextMuted)
                    
                    if let fileName = engineManager.selectedFileName {
                        // File Loaded State
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(ThemeColors.neonPurple.opacity(0.2))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "doc.zipper")
                                        .font(.system(size: 22))
                                        .foregroundColor(ThemeColors.neonPurple)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fileName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 8) {
                                        Text(engineManager.selectedFileSize ?? "0 KB")
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(ThemeColors.glassTextMuted)
                                        
                                        Text("•")
                                            .foregroundColor(Color.white.opacity(0.3))
                                        
                                        Text(engineManager.selectedFileType ?? "BINARY")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(ThemeColors.cyanGlow)
                                    }
                                }
                                
                                Spacer()
                                
                                Button(action: { showFilePicker = true }) {
                                    Text("CHANGE")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(ThemeColors.cyanGlow)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.08))
                                        .cornerRadius(8)
                                }
                            }
                            
                            if let hash = engineManager.selectedFileSHA256 {
                                HStack(spacing: 6) {
                                    Text("SHA256:")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(ThemeColors.glassTextMuted)
                                    Text(hash)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(8)
                            }
                        }
                        .padding(14)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(14)
                    } else {
                        // Empty / Import Button State
                        Button(action: { showFilePicker = true }) {
                            VStack(spacing: 10) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 32))
                                    .foregroundColor(ThemeColors.cyanGlow)
                                
                                Text("SELECT FILE FROM FILE MANAGER")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                
                                Text("Supports binary, packages, configs, and environment profiles")
                                    .font(.system(size: 10))
                                    .foregroundColor(ThemeColors.glassTextMuted)
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                            .background(Color.black.opacity(0.25))
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                                    )
                                    .foregroundColor(ThemeColors.cyanGlow.opacity(0.5))
                            )
                        }
                    }
                }
                .padding(20)
                .liquidGlass(cornerRadius: 22, glowColor: ThemeColors.neonPurple)
                .padding(.horizontal, 24)
                
                // Big Glowing Activate Button
                VStack(spacing: 12) {
                    GlowingButton(
                        title: engineManager.isEngineActive ? "DEACTIVATE ENVIRONMENT" : "ACTIVATE ENGINE",
                        icon: engineManager.isEngineActive ? "power" : "bolt.shield.fill",
                        primaryColor: engineManager.isEngineActive ? ThemeColors.electricGreen : ThemeColors.cyanGlow,
                        isPulsing: engineManager.isEngineActive
                    ) {
                        engineManager.toggleEngine()
                    }
                    
                    if engineManager.isEngineActive {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(ThemeColors.electricGreen)
                                .frame(width: 8, height: 8)
                            Text("RUNNING PERSISTENTLY IN BACKGROUND")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(ThemeColors.electricGreen)
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                // Live Activity Logs Terminal
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .foregroundColor(ThemeColors.cyanGlow)
                        Text("DIAGNOSTIC TELEMETRY STREAM")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeColors.glassTextMuted)
                        Spacer()
                    }
                    
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(engineManager.engineLogs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                                        .foregroundColor(log.contains("[ERROR]") ? ThemeColors.dangerRed : (log.contains("[SUCCESS]") ? ThemeColors.electricGreen : .white.opacity(0.75)))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(12)
                        }
                        .frame(height: 120)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(20)
                .liquidGlass(cornerRadius: 22, glowColor: ThemeColors.cyanGlow.opacity(0.3))
                .padding(.horizontal, 24)
                
                Spacer().frame(height: 30)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    engineManager.importFile(from: url)
                }
            case .failure(let error):
                engineManager.appendLog("[ERROR] File picker error: \(error.localizedDescription)")
            }
        }
    }
}
