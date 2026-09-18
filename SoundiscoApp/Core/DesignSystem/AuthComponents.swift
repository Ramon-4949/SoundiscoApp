import SwiftUI

enum Brand {
    static let red = Color(red: 0.76, green: 0, blue: 0.09)
}

struct BrandMark: View {
    var size: CGFloat = 76
    var body: some View {
        Image("BrandLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("SounDisco")
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
    @FocusState private var focused: Bool

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
                .focused($focused)
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
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        focused ? Brand.red : Color(uiColor: .separator).opacity(0.55),
                        lineWidth: focused ? 1.5 : 1
                    )
            }
            .animation(.easeOut(duration: 0.16), value: focused)
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
                .background(Brand.red, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
