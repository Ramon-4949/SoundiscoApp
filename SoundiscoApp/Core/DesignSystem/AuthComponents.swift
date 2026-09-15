import SwiftUI

enum Brand {
    static let red = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.3, blue: 0.35, alpha: 1)
            : UIColor(red: 0.76, green: 0, blue: 0.09, alpha: 1)
    })
}

struct BrandMark: View {
    var size: CGFloat = 76
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.23).fill(.black)
            RoundedRectangle(cornerRadius: 4).fill(.red)
                .frame(width: size * 0.19, height: size * 0.49)
                .offset(x: size * 0.29, y: size * 0.24)
            RoundedRectangle(cornerRadius: 4).fill(.red)
                .frame(width: size * 0.43, height: size * 0.18)
                .offset(x: size * 0.29, y: size * 0.24)
            Circle().fill(.red).frame(width: size * 0.21, height: size * 0.21)
                .offset(x: size * 0.55, y: size * 0.53)
        }
        .frame(width: size, height: size).accessibilityLabel("SounDisco")
    }
}

struct AuthField: View {
    let title: String
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .never
    @State private var visible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Brand.red)
                    .frame(width: 20).accessibilityHidden(true)
                Group {
                    if secure && !visible { SecureField(placeholder, text: $text) }
                    else { TextField(placeholder, text: $text) }
                }
                .textContentType(contentType).keyboardType(keyboard)
                .textInputAutocapitalization(capitalization).autocorrectionDisabled()
                .accessibilityLabel(title)
                if secure {
                    Button { visible.toggle() } label: {
                        Image(systemName: visible ? "eye.slash" : "eye").frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(visible ? "Ocultar contraseña" : "Mostrar contraseña")
                }
            }
            .padding(.leading, 14).padding(.trailing, secure ? 2 : 14)
            .frame(minHeight: 52)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct PrimaryAction: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title); Image(systemName: "arrow.right") }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(.white)
                .background(Color(red: 0.76, green: 0, blue: 0.09), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
