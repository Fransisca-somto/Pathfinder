# PathFinder Mobile App (Flutter) Comprehensive Handover Context

Welcome, New Agent! You are taking over the **PathFinder (Unizik Tracker)** mobile application on a new device. 

**CRITICAL CONTEXT:** The user has completely deleted their local backend API and is rebuilding it from scratch on this new device. Therefore, **do not attempt to fix or run the Node.js API**. Your sole domain and focus is this Flutter Mobile App. This document gives you an exhaustive snapshot of the exact codebase state so you can perfectly assist the user in integrating the app with their newly built API.

---

## 1. Directory Architecture & Philosophy
The app is located in the `PathFinder/` directory. It uses a **Feature-First Architecture** inside `lib/` and relies on **Riverpod 2.x** for state management.

### Exact File Map:
*   **Core Shared Logic (`lib/core/`):**
    *   `constants/app_colors.dart` & `app_theme.dart`: Centralized palette and Dark/Light mode configs.
    *   `enums/`: `user_role.dart` (OWNER vs DRIVER), `vehicle_status.dart`, `alert_type.dart`.
    *   `models/`: `user_model.dart`, `vehicle_model.dart`, `alert_model.dart`.
    *   `providers/app_providers.dart`: The global hub for all Riverpod state (Theme, Auth, Vehicles, Alerts).
    *   `services/`: `api_client.dart` (HTTP layer), `auth_service.dart`, `socket_service.dart` (WebSockets).
*   **Feature Modules (`lib/features/`):**
    *   `auth/`: `login_screen.dart`, `register_screen.dart`.
    *   `dashboard/`: `dashboard_screen.dart` (Main scaffold) and its specific tabs: `home_tab.dart`, `map_tab.dart`, `fleet_tab.dart`, `alerts_tab.dart`, `driver_dashboard_tab.dart`.
    *   `zones/`: `draw_zone_screen.dart` (Geofencing UI via `flutter_map`).
    *   `reports/`: `fleet_event_log_screen.dart`.

---

## 2. What Has Been Achieved So Far
The mobile app's UI is highly polished, completely free of "DummyData", and is structurally ready to consume live API data.

### 2.1 The "Live Data" Integration (Riverpod & HTTP)
We recently gutted the static mock data and replaced it with live API fetching logic:
1.  **`ApiClient` (`lib/core/services/api_client.dart`):** 
    *   A custom HTTP client that reads `API_URL` from the `.env` file (e.g., `http://localhost:3000`).
    *   It automatically injects JWT tokens (stored via `flutter_secure_storage`) into the `Authorization: Bearer <token>` header for every GET/POST/PUT request.
2.  **Auth State:** 
    *   `login_screen.dart` uses `AuthService` to hit `POST /auth/login`. 
    *   On a 200 OK, it securely stores the token, updates `currentUserProvider` (`UserModel`), and triggers `ref.invalidate(vehiclesProvider);` to fetch fresh data for that user.
3.  **AsyncNotifiers (`app_providers.dart`):**
    *   `vehiclesProvider`, `alertsProvider`, and `zonesProvider` are implemented as `AsyncNotifierProvider`s.
    *   They automatically call `ApiClient.get('/vehicles')` or `get('/alerts')` on initialization and parse the JSON lists into Dart models using their respective `.fromJson()` factories.
4.  **Graceful UI Loading (`AsyncValue`):**
    *   Every tab (e.g., `home_tab.dart` or `fleet_tab.dart`) uses Riverpod's `.when(data: ..., loading: ..., error: ...)` on the providers.
    *   They beautifully render `CircularProgressIndicator` while data is fetching from the API.

### 2.2 Advanced UI Features
*   **Map & Geofencing:** `flutter_map` is fully integrated. In `draw_zone_screen.dart`, the user can tap the map to physically draw geometric boundaries (polygons/circles).
*   **Role-Based Dashboards:** If `user.role == UserRole.DRIVER`, the app intelligently swaps out the owner's `HomeTab` for the specialized `DriverDashboardTab`.

---

## 3. What is Left To Do (Your Immediate Next Steps)

Since the user is rebuilding their API on this new device, the Flutter app's internal logic is technically complete, **but it has never been end-to-end tested with the live API**. 

When the user finishes building their new API, they will ask you to help connect the mobile app. Follow these exact steps:

### Task 1: Environment Configuration
Make sure the user has created a `.env` file in the root of the `PathFinder/` folder:
```env
API_URL=http://localhost:3000
WS_URL=http://localhost:3000
```
*(If testing on a physical Android device, `localhost` must be changed to the PC's local IPv4 address, e.g., `http://192.168.1.5:3000`)*.

### Task 2: Fix JSON Parsing Mismatches (The Most Likely Bug)
When the user connects the app to their new API for the first time, it might crash or show "Error" on the screen. 
*   **Why?** Because the JSON payload sent by their new API might not perfectly match the fields expected in `VehicleModel.fromJson` or `UserModel.fromJson`.
*   **Your Job:** Ask the user to provide the exact JSON response their API is sending, and then update `lib/core/models/vehicle_model.dart` or `user_model.dart` to map perfectly to their new backend schema. (For example, check if the backend sends `id` vs `vehicleId`, or `currentLatitude` vs `lat`).

### Task 3: Finalize Real-Time WebSockets
The app currently fetches data via HTTP GET requests. For true real-time GPS tracking on the `map_tab.dart`, you need to finalize WebSockets.
1.  Open `lib/core/services/socket_service.dart`.
2.  Ensure it connects to the `WS_URL` and authenticates using the JWT.
3.  Listen for a `location_update` event from the API.
4.  When received, you must trigger a function in `app_providers.dart` (like `vehiclesProvider.notifier.updateVehicle()`) so the marker on the map moves instantly without the user needing to refresh the screen.

---

## 4. Instructions for the New AI
1. Acknowledge this context when the user pastes it to you, or when you read it upon startup.
2. Tell the user: *"I understand you are rebuilding the API on this machine. Whenever your API is ready, let's boot up the Flutter app, configure the `.env` file with your PC's IP address, and test the connection! I am standing by to debug any JSON parsing issues or WebSocket setups."*
3. **Remember the user's rule:** *Never run major terminal code autonomously. Always provide the terminal code (like `flutter pub get` or `flutter run`) for the user to execute themselves.*
