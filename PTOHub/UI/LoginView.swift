import SwiftUI

struct LoginView: View {
    @Bindable var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case email, password }
    private enum ScrollTarget: Hashable { case email, password, signIn }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        hero(compact: geometry.size.height < 600)
                            .frame(minHeight: heroHeight(in: geometry.size))
                        form
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, field in
                    guard field != nil else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(ScrollTarget.signIn, anchor: .bottom)
                    }
                }
            }
            .background(Color(hex: 0xF8F6F0))
            .tint(Color(hex: 0x273F38))
        }
    }

    private func hero(compact: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Color(hex: 0x273F38)
            Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 260).offset(x: 80, y: 90)
            Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 190).offset(x: 45, y: 65)
            if compact {
                HStack {
                    StaffHubMark(compact: true)
                    Spacer()
                    Text("Your workday, made clear.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .padding(24)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    StaffHubMark()
                    Spacer(minLength: 12)
                    Text("Your workday,\nmade clear.")
                        .font(.system(size: 43, weight: .medium, design: .serif))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.75)
                    Text("Schedules, time away, and the team—together in one place.")
                        .foregroundStyle(.white.opacity(0.72))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
        }
    }

    private func heroHeight(in size: CGSize) -> CGFloat {
        if size.height < 600 { return 132 }
        return size.height * (size.width > 700 ? 0.42 : 0.36)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome back")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
            Text("Sign in with your existing Staff Hub account.")
                .foregroundStyle(.secondary)
            TextField("Email address", text: $email)
                .id(ScrollTarget.email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Email address")
            SecureField("Password", text: $password)
                .id(ScrollTarget.password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { signIn() }
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Password")
            Button(action: signIn) {
                if session.phase == .loading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
            }
            .id(ScrollTarget.signIn)
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: 0x273F38))
            .controlSize(.large)
            .disabled(session.phase == .loading)
#if DEBUG && targetEnvironment(simulator)
            demoAccess
#endif
            Text("Invitations and password recovery continue securely on the Staff Hub website.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func signIn() {
        focusedField = nil
        Task { await session.signIn(email: email, password: password) }
    }

#if DEBUG && targetEnvironment(simulator)
    private var demoAccess: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                Text("SIMULATOR DEMO").font(.caption2.bold()).foregroundStyle(.secondary)
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            }
            Text("Explore with local sample data. Demo actions never reach Supabase.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                demoButton("Employee", icon: "person", role: .employee)
                demoButton("Manager", icon: "person.2", role: .officeManager)
                demoButton("Owner", icon: "building.2", role: .ownerAdmin)
            }
        }
        .padding(.vertical, 2)
    }

    private func demoButton(_ title: String, icon: String, role: AppRole) -> some View {
        Button {
            focusedField = nil
            Task { await session.signInDemo(role: role) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Demo \(title)")
        .disabled(session.phase == .loading)
    }
#endif
}
