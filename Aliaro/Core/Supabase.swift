import Foundation
import Supabase

/// Single official Supabase SDK client for the whole app (PostgREST,
/// Realtime and Edge Functions).
let supabase = SupabaseClient(
    supabaseURL: SupabaseConfig.url,
    supabaseKey: SupabaseConfig.anonKey
)

/// Error carrying the friendly message an Aliaro edge function returned in
/// its JSON body (e.g. "este código ha caducado", "demasiados intentos...")
/// so the UI can show that instead of a generic HTTP status code.
struct EdgeFunctionError: LocalizedError {
    let message: String
    // Edge functions return lowercase Spanish messages ("código no válido");
    // capitalized here, once, so every screen that shows
    // `error.localizedDescription` gets a properly-cased sentence without
    // having to fix each message at its source.
    var errorDescription: String? {
        if let localized = Self.localizedMessage(for: message) { return localized }
        return message.prefix(1).uppercased() + message.dropFirst()
    }

    /// Known user-facing messages from the edge functions (always Spanish on
    /// the server), matched accent/case-insensitively and shown in the
    /// app's language instead.
    private static func localizedMessage(for message: String) -> String? {
        let key = message.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        if key.contains("codigo no valido") { return String(localized: "Invalid code.") }
        if key.contains("ya se ha usado") { return String(localized: "This code has already been used.") }
        if key.contains("ha caducado") { return String(localized: "This code has expired.") }
        if key.contains("demasiados intentos") { return String(localized: "Too many attempts. Try again in a few minutes.") }
        if key.contains("maximo de miembros") {
            return String(localized: "This group has reached the free plan's member limit. Its creator can subscribe to Aliaro Premium to add more.")
        }
        if key.contains("ya perteneces a otro grupo") {
            return String(localized: "You already belong to another family group. Leave it before joining this one.")
        }
        if key.contains("ya perteneces a un grupo") {
            return String(localized: "You already belong to a family group. Leave it before creating another one.")
        }
        return nil
    }
}

/// Drop-in replacement for `supabase.functions.invoke`: every Aliaro edge
/// function returns `{ "error": "..." }` on failure, but the SDK's own error
/// just says "Edge Function returned a non-2xx status code: N" and drops
/// that message. This unwraps it so callers (and the UI, via
/// `error.localizedDescription`) see the actual reason.
private struct EdgeFunctionErrorBody: Decodable {
    let error: String
}

func invokeEdgeFunction<T: Decodable>(
    _ functionName: String,
    options: FunctionInvokeOptions = FunctionInvokeOptions()
) async throws -> T {
    do {
        return try await supabase.functions.invoke(functionName, options: options)
    } catch FunctionsError.httpError(_, let data) {
        if let body = try? JSONDecoder().decode(EdgeFunctionErrorBody.self, from: data), !body.error.isEmpty {
            throw EdgeFunctionError(message: body.error)
        }
        throw EdgeFunctionError(message: String(localized: "Something went wrong, please try again."))
    }
}
