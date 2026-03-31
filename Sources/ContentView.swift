import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BypassViewModel()
    @State private var pulse = false
    @State private var introVisible = false
    @State private var splashVisible = true
    @State private var splashRingExpanded = false
    @State private var splashSweep = false
    @State private var splashGlow = false
    @State private var showingAdvanced = false
    @State private var showingFastFlags = false
    @State private var showingStats = false
    @State private var copyConfirmation = false

    var body: some View {
        ZStack {
            background

            HStack(alignment: .top, spacing: 20) {
                leftColumn
                rightColumn
            }
            .padding(20)
            .scaleEffect(introVisible ? 1 : 0.975)
            .opacity(introVisible ? 1 : 0)
            .blur(radius: splashVisible ? 12 : 0)

            if splashVisible {
                splashOverlay
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .background(
            WindowAccessor { window in
                configureWindow(window)
            }
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false)) {
                splashSweep = true
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                splashGlow = true
            }
            withAnimation(.spring(response: 1.3, dampingFraction: 0.78).delay(0.12)) {
                splashRingExpanded = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.spring(response: 0.95, dampingFraction: 0.86)) {
                    splashVisible = false
                    introVisible = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.forceCleanupForTermination()
        }
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                settingsCard
                fastFlagsCard
                
                if viewModel.proManager.isPro {
                    if showingAdvanced {
                        advancedCard
                    }
                    
                    if showingFastFlags {
                        fastFlagsDetailCard
                    }
                    
                    if showingStats {
                        statsCard
                    }
                } else {
                    upgradeCard
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(width: 340)
        .opacity(introVisible ? 1 : 0)
        .offset(x: introVisible ? 0 : -20)
        .animation(.spring(response: 0.9, dampingFraction: 0.88).delay(0.1), value: introVisible)
    }

    @State private var showingLicenseInfo: Bool = false
    
    private var headerCard: some View {
        glassCard {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    logoTile(size: 56)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("SpoofTrap")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            if viewModel.proManager.isPro {
                                Text("PRO")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .clipShape(Capsule())
                            }
                        }

                        Text("Roblox bypass launcher")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Spacer()
                    
                    if viewModel.proManager.isPro {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingLicenseInfo.toggle()
                            }
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if showingLicenseInfo, let license = viewModel.proManager.licenseManager.currentLicense {
                    Divider().background(.white.opacity(0.15))
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("License:")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(license.licenseKey)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        
                        HStack {
                            Text("Plan:")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(license.plan.capitalized)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.cyan)
                            
                            Spacer()
                            
                            Button {
                                deactivateLicense()
                            } label: {
                                Text("Deactivate")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
    
    private func deactivateLicense() {
        Task {
            await viewModel.proManager.deactivate()
            await MainActor.run {
                showingLicenseInfo = false
            }
        }
    }

    private var settingsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    sectionTitle("Settings")
                    Spacer()
                    if viewModel.proManager.isPro {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingStats.toggle()
                            }
                        } label: {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(showingStats ? .purple : .white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingAdvanced.toggle()
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(showingAdvanced ? .cyan : .white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    settingRow(label: "Roblox App") {
                        HStack(spacing: 8) {
                            statusDot(active: viewModel.robloxInstalled)
                            Button("Choose") { viewModel.chooseRobloxApp() }
                                .buttonStyle(SmallButtonStyle())
                                .disabled(viewModel.isRunning)
                            if viewModel.robloxInstalled {
                                Button {
                                    viewModel.revealRobloxInFinder()
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(SmallButtonStyle())
                            }
                        }
                    }
                    
                    Text(viewModel.robloxDisplayPath)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                settingRow(label: "Preset") {
                    presetPicker
                }

                VStack(alignment: .leading, spacing: 6) {
                    settingRow(label: "Proxy Mode") {
                        scopePicker
                    }
                    
                    Text(viewModel.proxyScope.description)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(viewModel.proxyScope == .system ? .green.opacity(0.7) : .orange.opacity(0.7))
                }
            }
        }
    }

    private var advancedCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Advanced")

                VStack(alignment: .leading, spacing: 6) {
                    settingRow(label: "spoofdpi") {
                        HStack(spacing: 8) {
                            statusDot(active: viewModel.binaryAvailable)
                            Button("Choose") { viewModel.chooseSpoofdpiBinary() }
                                .buttonStyle(SmallButtonStyle())
                                .disabled(viewModel.isRunning)
                            Button("Auto") { viewModel.resetBinaryPathOverride() }
                                .buttonStyle(SmallButtonStyle())
                                .disabled(viewModel.isRunning)
                            if viewModel.binaryAvailable {
                                Button {
                                    viewModel.revealBinaryInFinder()
                                } label: {
                                    Image(systemName: "folder")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .buttonStyle(SmallButtonStyle())
                            }
                        }
                    }
                    
                    Text(viewModel.binaryDisplayPath)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                settingRow(label: "Hybrid Relaunch") {
                    Toggle("", isOn: hybridBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(viewModel.isRunning)
                }

                settingRow(label: "Launch Delay") {
                    HStack(spacing: 6) {
                        Text("\(viewModel.appLaunchDelay)s")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        Stepper("", value: delayBinding, in: 0...10)
                            .labelsHidden()
                            .disabled(viewModel.isRunning)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var fastFlagsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    sectionTitle("FastFlags")
                    Spacer()
                    if viewModel.proManager.isPro {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showingFastFlags.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 10))
                                Text(showingFastFlags ? "Hide" : "Edit")
                            }
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.cyan.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Pro")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.yellow.opacity(0.7))
                    }
                }

                settingRow(label: "Enable FastFlags") {
                    Toggle("", isOn: $viewModel.fastFlagsManager.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(viewModel.isRunning)
                }

                settingRow(label: "Preset") {
                    fastFlagPresetPicker
                }

                HStack(spacing: 12) {
                    flagStat(label: "Enabled", value: "\(viewModel.fastFlagsManager.enabledCount)")
                    flagStat(label: "Modified", value: "\(viewModel.fastFlagsManager.modifiedCount)")
                }
            }
        }
    }

    private var fastFlagsDetailCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Flag Editor")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button {
                        viewModel.fastFlagsManager.resetAll()
                    } label: {
                        Text("Reset All")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRunning)
                }

                ForEach(FastFlag.Category.allCases, id: \.rawValue) { category in
                    let categoryFlags = viewModel.fastFlagsManager.flags.filter { $0.category == category }
                    if !categoryFlags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.rawValue)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                                .textCase(.uppercase)

                            ForEach(categoryFlags) { flag in
                                flagRow(flag: flag)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func flagRow(flag: FastFlag) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { flag.isEnabled },
                set: { _ in viewModel.fastFlagsManager.toggleFlag(flag) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(viewModel.isRunning)

            VStack(alignment: .leading, spacing: 2) {
                Text(flag.name)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(flag.isEnabled ? .white : .white.opacity(0.6))

                Text(flag.description)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            if flag.isEnabled && flag.valueType != .bool {
                TextField("", text: Binding(
                    get: { flag.value },
                    set: { viewModel.fastFlagsManager.setFlagValue(flag, value: $0) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 50)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .disabled(viewModel.isRunning)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(flag.isEnabled ? Color.white.opacity(0.06) : Color.clear)
        )
    }

    private var fastFlagPresetPicker: some View {
        Menu {
            ForEach(FastFlagPreset.allCases) { preset in
                Button(preset.rawValue) {
                    viewModel.fastFlagsManager.applyPreset(preset)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.fastFlagsManager.selectedPreset.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
        }
        .disabled(viewModel.isRunning)
    }

    private func flagStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(viewModel.fastFlagsManager.isEnabled ? .white : .white.opacity(0.5))
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Pro Features
    
    @State private var licenseKeyInput: String = ""
    @State private var isActivating: Bool = false
    @State private var activationError: String?
    
    private var upgradeCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                    Text("Upgrade to Pro")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    upgradeFeatureRow(icon: "slider.horizontal.3", text: "Fast & Custom presets")
                    upgradeFeatureRow(icon: "flag.fill", text: "Full FastFlags editor")
                    upgradeFeatureRow(icon: "gearshape.2.fill", text: "Advanced settings")
                    upgradeFeatureRow(icon: "chart.bar.fill", text: "Detailed session stats")
                }
                
                Divider().background(.white.opacity(0.2))
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Enter License Key")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                    
                    TextField("STXXX-XXXXX-XXXXX-XXXXX-XXXXX", text: $licenseKeyInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        )
                        .disabled(isActivating)
                    
                    if let error = activationError ?? viewModel.proManager.licenseManager.validationError {
                        Text(error)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    
                    Button {
                        activateLicense()
                    } label: {
                        HStack {
                            if isActivating {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.black)
                            } else {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 12))
                            }
                            Text(isActivating ? "Activating..." : "Activate License")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(licenseKeyInput.isEmpty || isActivating ? 0.6 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(licenseKeyInput.isEmpty || isActivating)
                }
            }
        }
    }
    
    private func activateLicense() {
        guard !licenseKeyInput.isEmpty else { return }
        
        isActivating = true
        activationError = nil
        
        Task {
            let success = await viewModel.proManager.activate(key: licenseKeyInput)
            
            await MainActor.run {
                isActivating = false
                if !success {
                    activationError = viewModel.proManager.licenseManager.validationError
                } else {
                    licenseKeyInput = ""
                }
            }
        }
    }
    
    private func upgradeFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.cyan)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
    
    private var statsCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.purple)
                        Text("Session Stats")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    if viewModel.sessionStats.isActive {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("Live")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                    }
                }
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    statTile(
                        icon: "clock.fill",
                        label: "Current",
                        value: viewModel.sessionStats.currentDuration,
                        color: .cyan
                    )
                    statTile(
                        icon: "play.fill",
                        label: "Launches",
                        value: "\(viewModel.sessionStats.currentLaunches)",
                        color: .green
                    )
                    statTile(
                        icon: "calendar",
                        label: "Today",
                        value: viewModel.sessionStats.todayPlayTimeFormatted,
                        color: .orange
                    )
                    statTile(
                        icon: "checkmark.circle",
                        label: "Success",
                        value: viewModel.sessionStats.successRateFormatted,
                        color: .mint
                    )
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Sessions")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Text("\(viewModel.sessionStats.totalSessions)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Play Time")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(viewModel.sessionStats.totalPlayTimeFormatted)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avg Session")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(viewModel.sessionStats.averageSessionFormatted)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private func statTile(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }

    // MARK: - Right Column

    private var rightColumn: some View {
        VStack(spacing: 16) {
            sessionCard
            logCard
        }
        .frame(maxWidth: .infinity)
        .opacity(introVisible ? 1 : 0)
        .offset(x: introVisible ? 0 : 20)
        .animation(.spring(response: 0.9, dampingFraction: 0.88).delay(0.15), value: introVisible)
    }

    private var sessionCard: some View {
        glassCard(accent: true) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Launch Session")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(viewModel.statusSummary)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(2)
                    }

                    Spacer()

                    statusPill
                }

                Button(action: viewModel.toggleBypass) {
                    VStack(spacing: 4) {
                        Text(viewModel.isRunning ? "Stop Session" : "Start Session")
                            .font(.system(size: 20, weight: .bold, design: .rounded))

                        Text(viewModel.isRunning ? "Terminate proxy" : "Launch Roblox")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(Color.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.98), actionTint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .shadow(color: actionTint.opacity(pulse ? 0.4 : 0.2), radius: pulse ? 20 : 10)
                    )
                }
                .buttonStyle(.plain)
                .disabled((!viewModel.binaryAvailable || !viewModel.robloxInstalled) && !viewModel.isRunning)

                HStack(spacing: 12) {
                    quickStat(label: "Preset", value: viewModel.preset.title)
                    quickStat(label: "Mode", value: viewModel.proxyScope.title)
                    quickStat(label: "Binary", value: viewModel.binaryAvailable ? "Ready" : "Missing")
                }
            }
        }
    }

    private var logCard: some View {
        glassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    sectionTitle("Session Log")

                    Spacer()

                    Text("\(viewModel.logs.count) lines")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    Button {
                        viewModel.copyLogs()
                        copyConfirmation = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copyConfirmation = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copyConfirmation ? "checkmark" : "doc.on.doc")
                            Text(copyConfirmation ? "Copied" : "Copy")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(copyConfirmation ? .green : .white.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.logs.isEmpty)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(displayLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(logColor(for: line, index: index))
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            )
                    )
                    .onChange(of: viewModel.logs.count) { _ in
                        if let last = viewModel.logs.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Splash

    private var splashOverlay: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.05, blue: 0.10),
                        Color(red: 0.05, green: 0.09, blue: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color(red: 0.4, green: 0.85, blue: 1.0).opacity(splashGlow ? 0.25 : 0.12))
                    .frame(width: 500, height: 500)
                    .blur(radius: 80)
                    .offset(x: geo.size.width * 0.15, y: -geo.size.height * 0.1)

                VStack(spacing: 28) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            .frame(width: splashRingExpanded ? 200 : 100, height: splashRingExpanded ? 200 : 100)

                        Circle()
                            .trim(from: 0.1, to: 0.85)
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color.white.opacity(0.1),
                                        Color(red: 0.45, green: 0.88, blue: 1.0),
                                        Color(red: 0.9, green: 0.35, blue: 0.5),
                                        Color.white.opacity(0.1)
                                    ],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round)
                            )
                            .frame(width: splashRingExpanded ? 160 : 70, height: splashRingExpanded ? 160 : 70)
                            .rotationEffect(.degrees(splashSweep ? 360 : 0))

                        logoTile(size: 72)
                            .shadow(color: Color(red: 0.45, green: 0.86, blue: 1.0).opacity(splashGlow ? 0.5 : 0.2), radius: 20)
                    }

                    VStack(spacing: 8) {
                        Text("SpoofTrap")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Initializing")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    HStack(spacing: 8) {
                        Capsule().fill(Color.white.opacity(0.15)).frame(width: 40, height: 5)
                        Capsule()
                            .fill(Color(red: 0.45, green: 0.88, blue: 1.0).opacity(0.85))
                            .frame(width: splashGlow ? 100 : 60, height: 5)
                        Capsule().fill(Color.white.opacity(0.15)).frame(width: 40, height: 5)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Components

    private func glassCard<Content: View>(accent: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: accent
                            ? [Color.white.opacity(0.10), Color.white.opacity(0.06)]
                            : [Color.white.opacity(0.08), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(accent ? 0.12 : 0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.2), radius: 20, y: 10)
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func settingRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            content()
        }
    }

    private func statusDot(active: Bool) -> some View {
        Circle()
            .fill(active ? Color.green : Color.red)
            .frame(width: 8, height: 8)
            .shadow(color: (active ? Color.green : Color.red).opacity(0.5), radius: 4)
    }

    private func quickStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(pulse ? 0.6 : 0.3), radius: pulse ? 8 : 4)

            Text(viewModel.state.title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(Capsule().stroke(statusColor.opacity(0.4), lineWidth: 1))
        )
    }

    private var presetPicker: some View {
        HStack(spacing: 3) {
            ForEach(BypassViewModel.ProxyPreset.allCases) { preset in
                let isProOnly = preset == .fast || preset == .custom
                let isLocked = isProOnly && !viewModel.proManager.isPro
                
                Button {
                    if !isLocked {
                        viewModel.applyPreset(preset)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(preset.title)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        if isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 7))
                        }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        isLocked ? .white.opacity(0.35) :
                        viewModel.preset == preset ? .black.opacity(0.8) : .white.opacity(0.6)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(viewModel.preset == preset && !isLocked ? Color.white : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRunning || isLocked)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
    }

    private var scopePicker: some View {
        HStack(spacing: 4) {
            ForEach(BypassViewModel.ProxyScope.allCases) { scope in
                Button {
                    viewModel.setProxyScope(scope)
                } label: {
                    Text(scope.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(viewModel.proxyScope == scope ? .black.opacity(0.8) : .white.opacity(0.6))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(viewModel.proxyScope == scope ? Color.white : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRunning)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.2))
        )
    }

    private func logoTile(size: CGFloat) -> some View {
        Image(nsImage: BrandAssets.logo)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.09, blue: 0.16),
                    Color(red: 0.08, green: 0.11, blue: 0.18),
                    Color(red: 0.10, green: 0.13, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.42, green: 0.85, blue: 1.0).opacity(0.15))
                .frame(width: 400, height: 400)
                .blur(radius: 60)
                .offset(x: 300, y: -200)

            Circle()
                .fill(Color(red: 1.0, green: 0.8, blue: 0.55).opacity(0.10))
                .frame(width: 280, height: 280)
                .blur(radius: 50)
                .offset(x: -280, y: 220)
        }
    }

    // MARK: - Helpers

    private var displayLines: [String] {
        viewModel.logs.isEmpty
            ? ["Waiting for session..."]
            : viewModel.logs
    }

    private func logColor(for line: String, index: Int) -> Color {
        if viewModel.logs.isEmpty { return .white.opacity(0.4) }
        if line.localizedCaseInsensitiveContains("failed") || line.localizedCaseInsensitiveContains("missing") || line.localizedCaseInsensitiveContains("error") {
            return Color(red: 1.0, green: 0.55, blue: 0.55)
        }
        if line.localizedCaseInsensitiveContains("active") || line.localizedCaseInsensitiveContains("ready") || line.localizedCaseInsensitiveContains("launched") {
            return Color(red: 0.55, green: 0.92, blue: 0.65)
        }
        return .white.opacity(0.8)
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .running: return Color(red: 0.45, green: 0.92, blue: 0.65)
        case .starting: return Color(red: 1.0, green: 0.78, blue: 0.35)
        case .stopping, .stopped: return Color(red: 1.0, green: 0.45, blue: 0.45)
        }
    }

    private var actionTint: Color {
        switch viewModel.state {
        case .running: return Color(red: 0.6, green: 0.92, blue: 0.75)
        case .starting: return Color(red: 0.95, green: 0.85, blue: 0.55)
        case .stopping, .stopped: return Color(red: 0.75, green: 0.88, blue: 1.0)
        }
    }

    private var hybridBinding: Binding<Bool> {
        Binding(get: { viewModel.hybridLaunch }, set: { viewModel.setHybridLaunch($0) })
    }

    private var delayBinding: Binding<Int> {
        Binding(get: { viewModel.appLaunchDelay }, set: { viewModel.setLaunchDelay($0) })
    }

    private func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.styleMask.insert(.fullSizeContentView)
    }
}

// MARK: - Small Button Style

struct SmallButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.08))
            )
    }
}

// MARK: - Assets

private enum BrandAssets {
    static let logo: NSImage = {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("spooftrap-icon.png"),
            BypassViewModel.locateResourceBundle()?.resourceURL?.appendingPathComponent("spooftrap-icon.png")
        ]
        for url in candidates.compactMap({ $0 }) {
            if let image = NSImage(contentsOf: url) { return image }
        }
        return NSApplication.shared.applicationIconImage
    }()
}
