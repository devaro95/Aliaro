import Foundation

/// Configuración del backend Supabase de Aliaro. Debug (Xcode/simulador/dispositivo
/// en desarrollo) apunta al proyecto Aliaro-Dev; Release (Archive/TestFlight/App Store)
/// apunta a producción. Se decide en tiempo de compilación con #if DEBUG, sin pasar
/// por Info.plist, para evitar depender de que Xcode regenere/sincronice ese fichero.
enum SupabaseConfig {
#if DEBUG
    static let url = URL(string: "https://wjqlwsypkhjcnyrzofre.supabase.co")!
    // "Publishable/anon" key del proyecto Aliaro-Dev.
    static let anonKey = "sb_publishable_jeWxe9Y4m4mTJC28WyO1eg_1nWoDcw3"
#else
    static let url = URL(string: "https://ngedcnaxsnrfzmhiittd.supabase.co")!
    // "Publishable/anon" key del proyecto Aliaro (producción).
    static let anonKey = "sb_publishable_AUBZHrAE43TzOFxgBQq5rA_SniBVY2u"
#endif
}
