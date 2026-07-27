import SwiftUI

struct LoginView: View {
    @Bindable var session: AppSession
    @State private var email = ""
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .frame(minHeight: geometry.size.height * (geometry.size.width > 700 ? 0.42 : 0.36))
                    form
                }
                .frame(minHeight: geometry.size.height)
            }
            .background(Color(hex: 0xF8F6F0))
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(hex: 0x453B3D)
            Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 260).offset(x: 80, y: 90)
            Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: 190).offset(x: 45, y: 65)
            VStack(alignment: .leading, spacing: 18) {
                BrandLogo(business: nil).frame(width: 150, height: 84)
                Spacer(minLength: 12)
                Text("Time away,\nmade clear.")
                    .font(.system(size: 43, weight: .medium, design: .serif))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                Text("Your schedule and PTO, wherever work takes you.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome back")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
            Text("Sign in with your existing Staff Hub account.")
                .foregroundStyle(.secondary)
            TextField("Email address", text: $email)
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
            .buttonStyle(.borderedProminent)
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
