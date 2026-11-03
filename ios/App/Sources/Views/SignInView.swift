import AuthenticationServices
import SwiftUI

/// The first screen. Signing in with Apple opens the person's bench on the server, or makes it the
/// first time.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var signingIn = false
    @State private var failed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "hanger")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(L10n.signInTitle)
                .font(.largeTitle.bold())
            Text(L10n.signInMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if failed {
                Text(L10n.signInFailed)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("signIn.failed")
            }
            SignInWithAppleButton(.signIn) { request in
                // No name and no email: the server only needs Apple's id for the person.
                request.requestedScopes = []
            } onCompletion: { result in
                finish(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .disabled(signingIn)
            .accessibilityIdentifier("signIn.apple")
        }
        .padding()
    }

    private func finish(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.authorizationCode,
                  let code = String(data: data, encoding: .utf8)
            else {
                failed = true
                return
            }
            signingIn = true
            Task {
                let signedIn = await model.signIn(code: code)
                failed = !signedIn
                signingIn = false
            }
        case .failure(let error):
            // Closing Apple's sheet isn't a failure.
            failed = (error as? ASAuthorizationError)?.code != .canceled
        }
    }
}
