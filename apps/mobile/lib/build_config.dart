abstract final class BuildConfig {
  // Companion APKs are updated from this project, not from PiliPlus releases.
  static const bool upstreamUpdatesEnabled = bool.fromEnvironment(
    'pili.upstreamUpdates',
    defaultValue: false,
  );

  static const int versionCode = int.fromEnvironment(
    'pili.code',
    defaultValue: 1,
  );
  static const String versionName = String.fromEnvironment(
    'pili.name',
    defaultValue: 'SNAPSHOT',
  );

  static const int buildTime = int.fromEnvironment('pili.time');
  static const String commitHash = String.fromEnvironment(
    'pili.hash',
    defaultValue: 'N/A',
  );
}
