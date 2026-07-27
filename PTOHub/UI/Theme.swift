import SwiftUI

struct BusinessTheme {
    let primary: Color
    let secondary: Color
    let accent: Color
    let accentSoft: Color
    let wash: Color

    static func theme(for key: String?) -> BusinessTheme {
        switch key {
        case "senoia-eye-care":
            .init(primary: Color(hex: 0x4A4142), secondary: Color(hex: 0x64595A), accent: Color(hex: 0x8C6C12), accentSoft: Color(hex: 0xEBDFB5), wash: Color(hex: 0xF0ECE3))
        case "maxara":
            .init(primary: Color(hex: 0x080D0D), secondary: Color(hex: 0x202827), accent: Color(hex: 0x9A731F), accentSoft: Color(hex: 0xEAD9AA), wash: Color(hex: 0xEDE9DF))
        default:
            .init(primary: Color(hex: 0x453B3D), secondary: Color(hex: 0x5D5052), accent: Color(hex: 0xA7694E), accentSoft: Color(hex: 0xEAD7CE), wash: Color(hex: 0xEEE9E6))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255
        )
    }
}

struct BrandLogo: View {
    let business: Business?

    var body: some View {
        Image(business?.themeKey ?? "griffin-eye-care")
            .resizable()
            .scaledToFit()
            .accessibilityLabel(business?.name ?? "Staff Hub")
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .contentTransition(.numericText())
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct OfflineBanner: View {
    let savedAt: Date?

    var body: some View {
        Label {
            if let savedAt {
                Text("Offline · saved \(savedAt.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Offline · changes are unavailable")
            }
        } icon: {
            Image(systemName: "wifi.slash")
        }
        .font(.caption.weight(.semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .foregroundStyle(Color(hex: 0x7A4B19))
        .background(Color(hex: 0xFFF2D6))
    }
}

struct ProfileAvatar: View {
    let profile: StaffProfile

    var body: some View {
        Text(profile.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined())
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Color(hexString: profile.avatarColor), in: Circle())
            .accessibilityHidden(true)
    }
}

private extension Color {
    init(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt32(cleaned, radix: 16) ?? 0x6F7773
        self.init(hex: value)
    }
}
