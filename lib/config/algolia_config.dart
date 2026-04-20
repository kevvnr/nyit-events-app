class AlgoliaConfig {
  static const appId = 'ELWALJMF68';

  /// Read-only — safe to ship in the app binary.
  static const searchKey = 'd8c82049ac1c9a118ed85c7076296b00';

  /// Write key — only used for admin-triggered operations (create/edit/delete).
  /// Move to a Cloud Function when upgrading to Firebase Blaze plan.
  static const writeKey = '2defdca44b2b3d803e6a40ba37826776';

  static const indexName = 'events';
}
