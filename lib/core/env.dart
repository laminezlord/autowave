/// Build-time settings. Override any of them with --dart-define, e.g.
///   flutter run --dart-define=DEMO=true
///
/// The Supabase URL and anon key are public by design (they ship inside every
/// app). Row-level security in the database is what protects the data.
/// Never put secret keys here: Paystack, Gemini and Google server keys live in
/// Supabase Edge Function secrets.
class Env {
  /// Runs the whole app on built-in sample data, with no backend at all.
  /// Useful for demos, design reviews and app-store screenshots.
  static const demo = bool.fromEnvironment('DEMO');

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yvhcakjqsjtvueltwpxv.supabase.co',
  );

  /// Publishable key (sb_publishable_...). The legacy anon JWT also works here.
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_VDJj3iI-tK5gfEODWfpcKg_GbGXZphL',
  );

  /// Where Google/Paystack send people back to the app after signing in or paying.
  static const authRedirect = String.fromEnvironment(
    'AUTH_REDIRECT',
    defaultValue: 'io.autowave.app://login-callback',
  );

  /// Map tiles. OpenStreetMap's public server is fine for development only.
  /// Before launch, switch to a provider with a key (MapTiler, Stadia, Mapbox):
  ///   --dart-define=MAP_TILE_URL=https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=YOUR_KEY
  static const mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const defaultCountry = String.fromEnvironment('DEFAULT_COUNTRY', defaultValue: 'NG');
}
