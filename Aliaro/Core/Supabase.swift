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
    var errorDescription: String? { message.prefix(1).uppercased() + message.dropFirst() }
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
        throw EdgeFunctionError(message: "Something went wrong, please try again.")
    }
}
