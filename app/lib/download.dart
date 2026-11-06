/// Saves a file for the user: a browser download on the web, unavailable
/// elsewhere (the UI then offers copy instead).
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
