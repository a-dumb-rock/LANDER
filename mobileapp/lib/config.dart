/// App-wide configuration.
///
/// [kServerBaseUrl] is the base URL of the LANDR analysis server (the FastAPI
/// app in `server.py`). Point it at the machine running the server on your
/// network (default port 8000). Override at build/run time without editing
/// source, e.g.:
///
///   flutter run --dart-define=LANDR_SERVER=http://192.168.1.50:8000
const String kServerBaseUrl = String.fromEnvironment(
  'LANDR_SERVER',
  defaultValue: 'http://192.168.0.162:8000',
);
