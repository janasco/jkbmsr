# Future Flutter Project Structure

Proposed structure when the Flutter app is created:

```text
lib/
├── main.dart
├── app/
│   ├── app.dart
│   └── router.dart
├── features/
│   ├── auth/
│   ├── devices/
│   ├── battery/
│   ├── alerts/
│   ├── settings/
│   └── ota/
├── services/
│   ├── api_client.dart
│   ├── auth_store.dart
│   └── notification_service.dart
├── models/
│   ├── device.dart
│   ├── telemetry.dart
│   └── alert.dart
└── widgets/
    └── shared/
```

The app should keep REST API access in service classes and avoid calling APIs directly from widgets.
