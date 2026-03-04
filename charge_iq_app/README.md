<div align="center">

# ⚡ ChargeIQ

### AI-Powered EV Charging Companion for India

*Find EV charging stations, plan smart trips, and navigate with confidence — all in one app.*

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-^3.9.0-0175C2?logo=dart&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-Enabled-FFCA28?logo=firebase&logoColor=black)
![Gemini AI](https://img.shields.io/badge/Gemini_AI-2.5_Flash-4285F4?logo=google&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Web-lightgrey)

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Tech Stack](#tech-stack)
- [APIs & Services](#apis--services)
- [Project Structure](#project-structure)
- [Data Models](#data-models)
- [Screens](#screens)
- [Getting Started](#getting-started)
- [Environment Variables](#environment-variables)

---

## Overview

**ChargeIQ** is a cross-platform Flutter mobile application designed for electric vehicle (EV) owners in India. It combines real-time Google Maps-based EV station discovery, AI-powered trip planning via Google Gemini, turn-by-turn navigation, vehicle profile management, and Firebase-backed user accounts into a single seamless experience.

The app targets Indian EV drivers and restricts place searches to India (`components=country:in`) to keep results relevant.

---

## Features

### 🗺️ Interactive EV Station Map
- Full-screen Google Maps view centered on the user's current GPS location
- Discovers nearby EV charging stations within a **30 km radius** using the Google Places Nearby Search API
- Custom-rendered **⚡ emoji markers** (canvas-drawn with radial gradient fill and drop shadow) for each charging station
- Custom **blue location pin** marker for the user's current position
- Station results are **locally cached for 7 days** using `SharedPreferences` to minimize API calls
- Tap any marker to open a detailed bottom sheet showing station name, address, rating, open/close status, and straight-line distance
- **Save / Unsave** stations to a personal favourites list stored in Firestore

### 🔍 Smart Station Search
- Live debounced search bar powered by the **Google Places Autocomplete API**
- Search EV stations by name inline on the map
- Matching results displayed in a live dropdown list

### ⚡ Quick Charge AI
- One-tap **"Quick Charge"** button (Lottie-animated) that instantly finds the **single best nearby EV station** for the current user
- When **AI mode is ON** (default): forwards the station list and full vehicle profile to **Google Gemini 2.5 Flash** which intelligently recommends the optimal station based on distance, charger compatibility, rating, and the user's vehicle charging preferences
- When **AI mode is OFF**: falls back to nearest-distance logic
- AI preference is persisted via `SharedPreferences`

### 🧭 AI Trip Planner
- Input a start location (or use current GPS) and a destination
- Select one or more registered vehicles; the planner uses the vehicle with the shortest range as the limiting constraint
- Optionally include restaurant stops along the route
- Calls **Google Gemini 2.5 Flash** (JSON response mode) with full vehicle context:
  - Battery capacity, max range (km), charging port type (CCS2 / CHAdeMO / Type 2)
  - Max AC & DC fast charging power
  - Driving style (Eco / Normal / Sport) — adjusts realistic range by ±10–15 %
  - AC usage flag — reduces range by ~12 %
  - Battery health % — scales range proportionally below 90 %
  - `stopChargingAtPercent` target (e.g. 80 %)
- Gemini responds with a structured JSON trip plan: route waypoints, recommended charging stops, estimated charge durations, and distance/time per leg
- Saved trips are persisted to **Cloud Firestore** under `users/{uid}/trips`

### 🗺️ Turn-by-Turn Navigation
- Integrated **Google Navigation Flutter** SDK for real-time turn-by-turn navigation sessions
- Directions polyline overlaid on the interactive map using the **Google Directions API**
- Dedicated navigation screen for in-progress journeys

### 🚗 Vehicle Management
- Add, edit, and delete multiple EV vehicles per account
- Rich vehicle profiles with three data sections:
  1. **Vehicle Info** — brand, model, variant, type (Car / Bike / Scooter), manufacturing year, registration number
  2. **Battery & Range** — battery capacity (kWh), max range (km), charging port type, max AC/DC charging power (kW)
  3. **Smart Settings** — driving style, AC usage habit, battery health %, preferred charging type, stop-charging target %, home charging availability
- Designate a **default vehicle** used automatically by the Trip Planner and Quick Charge AI
- All vehicle data stored in Firestore under `users/{uid}/vehicles`

### 📍 Saved Locations
- Bookmark any EV charging station from the map or station list with a single tap
- Saved station IDs stored in Firestore; accessible from a dedicated Saved Locations screen

### 📜 Trip History
- All AI-planned trips automatically saved and listed in reverse-chronological order
- View full trip details (start, destination, vehicle, AI-generated plan) and delete old trips

### 👤 User Profile & Statistics
- Displays user avatar, display name, email, and login method (Email / Google)
- Tracks local usage statistics: routes taken, stations found, minutes saved
- Toggle **Quick Charge AI** on / off from the profile screen
- System-wide **Dark / Light mode** toggle (persisted across sessions)
- Link to **Premium Plans** subscription screen

### 🔐 Authentication
- **Email & Password** sign-up and sign-in via Firebase Auth
- **Google Sign-In** (OAuth 2.0) — Web uses `signInWithPopup`; mobile uses the `google_sign_in` package
- User document automatically created in Firestore on first registration (uid, email, name, login type, timestamps)
- Auth state stream drives root navigation: splash → sign-in page or main app

### 🔔 Push Notifications
- Firebase Cloud Messaging (FCM) fully integrated
- Requests alert / badge / sound permissions on launch
- Foreground notification display configured via `FirebaseMessaging.onMessage`
- Background handler registered as a top-level VM entry point (`@pragma('vm:entry-point')`)
- FCM token refresh listener for always-current device registration

### 🌐 Web Support
- App runs on the web via Flutter Web
- Dynamically injects the Google Maps JavaScript SDK into the page `<head>` at startup
- Platform-conditional imports (`web_utils.dart` / `web_utils_stub.dart`) keep mobile builds clean

### 🎨 Theming
- Full **Light / Dark theme** support with `ThemeMode`
- Theme state managed by `AppTheme` (`ValueNotifier<ThemeMode>`) and persisted across restarts via `SharedPreferences`
- Custom branded `ThemeData` for both modes with distinct colour palettes and card styles

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Framework** | Flutter 3.x · Dart `^3.9.0` |
| **State Management** | `StatefulWidget` + `ValueNotifier` (theme) + Firestore streams |
| **Backend / Database** | Firebase Cloud Firestore |
| **Authentication** | Firebase Auth + Google Sign-In |
| **AI / LLM** | Google Gemini 2.5 Flash (`google_generative_ai ^0.4.0`) |
| **Maps** | Google Maps Flutter `^2.6.0` |
| **Navigation** | Google Navigation Flutter `^0.8.2` |
| **Location** | `geolocator ^10.1.0` · `geocoding ^3.0.0` · `location ^5.0.3` |
| **Permissions** | `permission_handler ^11.0.1` |
| **HTTP Client** | `http ^1.6.0` |
| **Local Storage** | `shared_preferences ^2.2.2` |
| **Animations** | `lottie ^3.1.3` |
| **Environment Config** | `flutter_dotenv ^6.0.0` |
| **Push Notifications** | `firebase_messaging ^16.1.1` |
| **Analytics** | `firebase_analytics ^12.1.2` |
| **URL Handling** | `url_launcher ^6.3.2` |
| **App Icons** | `flutter_launcher_icons ^0.14.4` |
| **Bottom Nav Bar** | `animated_bottom_navigation_bar ^1.4.0` |
| **Linting** | `flutter_lints ^6.0.0` |

---

## APIs & Services

### Google Cloud APIs

| API | Endpoint | Usage in App |
|---|---|---|
| **Places Nearby Search** | `maps.googleapis.com/maps/api/place/nearbysearch/json` | Discover EV charging stations within 30 km of the user; paginated results |
| **Places Autocomplete** | `maps.googleapis.com/maps/api/place/autocomplete/json` | Live location search suggestions (restricted to India) |
| **Place Details** | `maps.googleapis.com/maps/api/place/details/json` | Fetch full info for a selected place (name, address, lat/lng) |
| **Directions** | `maps.googleapis.com/maps/api/directions/json` | Route polylines and travel distance / estimated duration |
| **Geocoding** | `maps.googleapis.com/maps/api/geocode/json` | Reverse-geocode GPS coordinates to human-readable addresses |
| **Distance Matrix** | `maps.googleapis.com/maps/api/distancematrix/json` | Driving distances from user to multiple stations in one call |
| **Maps JavaScript SDK** | `maps.googleapis.com/maps/api/js` | Google Maps rendering on the Flutter Web platform |
| **Maps Android / iOS SDK** | Native SDKs via `google_maps_flutter` | Interactive map on Android and iOS |
| **Google Navigation SDK** | Native SDK via `google_navigation_flutter` | Real-time turn-by-turn navigation |

### Google AI (Gemini)

| API | Model | JSON Mode | Usage |
|---|---|---|---|
| **Gemini Generative AI** | `gemini-2.5-flash` | ✅ `application/json` | AI Trip Planner — structured JSON trip plan with optimal charging stops |
| **Gemini Generative AI** | `gemini-2.5-flash` | ✅ `application/json` | Quick Charge AI — selects best station from candidates based on vehicle profile |

### Firebase

| Service | SDK Package | Usage |
|---|---|---|
| **Firebase Core** | `firebase_core ^4.4.0` | App initialization |
| **Firebase Auth** | `firebase_auth ^6.1.4` | Email + Google sign-in / sign-up / session management |
| **Cloud Firestore** | `cloud_firestore ^6.1.2` | Users, vehicles, saved stations, trip history |
| **Firebase Analytics** | `firebase_analytics ^12.1.2` | App usage tracking |
| **Firebase Messaging** | `firebase_messaging ^16.1.1` | Push notifications (foreground + background) |

---

## Project Structure

```
lib/
├── main.dart                       # Entry point: Firebase init, theme, auth routing
├── firebase_options.dart           # Auto-generated multi-platform Firebase config
├── web_utils.dart                  # Web: injects Google Maps JS SDK into <head>
├── web_utils_stub.dart             # Mobile stub for conditional import
│
├── models/
│   ├── vehicle.dart                # Vehicle data model (3-section EV profile)
│   └── trip_plan.dart              # TripPlan model (stores Gemini JSON plan)
│
├── screens/
│   ├── splash_screen.dart          # Animated splash; Firebase init + min 1.5 s display
│   ├── sign_in_page.dart           # Email & Google sign-in form
│   ├── sign_up_page.dart           # Email registration form
│   ├── main_screen.dart            # Root scaffold with animated bottom nav (4 tabs)
│   ├── map_screen.dart             # Core map: stations, Quick Charge AI, search, directions
│   ├── stations_list_screen.dart   # List view of nearby EV stations with distance sort
│   ├── trip_planning_screen.dart   # AI trip planner input (location, vehicle, time, prefs)
│   ├── trip_result_screen.dart     # Renders Gemini JSON trip plan (legs, stops, times)
│   ├── all_trips_screen.dart       # Trip history — view & delete
│   ├── google_nav_screen.dart      # Google Navigation turn-by-turn screen
│   ├── navigation_screen.dart      # Navigation wrapper / controller
│   ├── profile_screen.dart         # User info, stats, AI & theme toggles, sign-out
│   ├── manage_vehicles_screen.dart # Add / edit / delete EV vehicle profiles
│   ├── saved_locations_screen.dart # Bookmarked charging stations
│   └── premium_plans_screen.dart   # Subscription tier selection UI
│
├── services/
│   ├── auth_service.dart           # Singleton: Firebase Auth (email + Google OAuth)
│   ├── gemini_service.dart         # Gemini AI: trip planning + Quick Charge station selection
│   ├── places_service.dart         # Google Places Autocomplete + Place Details REST calls
│   ├── directions_service.dart     # Google Directions API REST call
│   ├── trip_service.dart           # Firestore CRUD for trip history
│   ├── vehicle_service.dart        # Firestore CRUD for vehicle profiles + default vehicle
│   ├── saved_location_service.dart # Firestore CRUD for saved / bookmarked stations
│   └── fcm_service.dart            # Firebase Cloud Messaging setup & listeners
│
├── utils/
│   ├── theme_provider.dart         # AppTheme: ValueNotifier<ThemeMode> + light/dark ThemeData
│   ├── google_map_styles.dart      # JSON map style strings for light/dark map themes
│   └── app_snackbar.dart           # Reusable SnackBar helper widget
│
└── widgets/
    └── app_lottie_loader.dart      # Reusable Lottie animation loading widget

assets/
├── .env                            # API keys (not committed to VCS)
├── carr.json                       # Lottie JSON animation asset
└── lottie/
    └── quick_charge_button.json    # Lottie animation for the Quick Charge button
```

---

## Data Models

### `Vehicle`

```dart
Vehicle {
  String id, userId,

  // Section 1 — Vehicle Info
  String brand, model, variant, vehicleType,
  int    manufacturingYear,
  String registrationNumber,

  // Section 2 — Battery & Range
  double batteryCapacity,        // kWh
  double maxRange,               // km
  String chargingPortType,       // e.g. CCS2, CHAdeMO, Type 2
  double maxACChargingPower,     // kW
  double maxDCFastChargingPower, // kW

  // Section 3 — Smart Settings
  String drivingStyle,           // Eco | Normal | Sport
  bool   acUsageUsually,
  double? batteryHealthPercent,
  String preferredChargingType,  // Fast | Slow
  int    stopChargingAtPercent,  // e.g. 80
  bool   homeChargingAvailable,

  DateTime createdAt, updatedAt
}
```

### `TripPlan`

```dart
TripPlan {
  String id, userId,
  String startLocation, destination,
  String vehicleId,
  int    evRange,        // km
  String vehicleType,
  String planData,       // Raw Gemini JSON string
  DateTime timestamp,
  double? startLat, startLng, destLat, destLng
}
```

---

## Screens

| Screen | Description |
|---|---|
| **Splash** | Animated intro; Firebase initialised in parallel with a 1.5 s minimum display time |
| **Sign In** | Email/password login + Google Sign-In button |
| **Sign Up** | New account registration with name, email, and password |
| **Main** | Root screen with animated 4-tab bottom navigation bar |
| **Map** | Interactive EV station map, Quick Charge AI, station search, and directions |
| **Stations List** | Paginated list of nearby EV stations sorted by distance with open/closed badge |
| **Trip Planning** | AI trip planner form: pick start/end, select vehicles, set departure time, optional restaurants |
| **Trip Result** | Full Gemini-generated trip plan rendered with legs, stops, charge estimates |
| **All Trips** | Chronological trip history; tap to view plan, swipe/button to delete |
| **Google Nav** | Full-screen turn-by-turn navigation powered by Google Navigation Flutter |
| **Profile** | User info, usage stats, Quick Charge AI toggle, theme toggle, sign-out |
| **Manage Vehicles** | Add/edit/delete vehicles with full smart-settings fields; set default vehicle |
| **Saved Locations** | Bookmarked charging stations with name and address |
| **Premium Plans** | Subscription tier cards with feature comparison |

---

## Getting Started

### Prerequisites

- Flutter SDK `^3.9.0` — [install guide](https://docs.flutter.dev/get-started/install)
- A **Google Cloud** project with the following APIs enabled:
  - Maps SDK for Android
  - Maps SDK for iOS
  - Maps JavaScript API (Web)
  - Places API
  - Directions API
  - Geocoding API
  - Distance Matrix API
- A **Firebase** project with Android, iOS, and Web apps registered (`google-services.json` and `GoogleService-Info.plist` in place)
- A **Google AI Studio** API key for Gemini


## Environment Variables

Create the file `assets/.env` in the `charge_iq_app` directory with the following keys:

```env
GOOGLE_MAPS_API_KEY=your_google_maps_and_places_api_key
GEMINI_API=your_google_gemini_api_key
```

The `.env` file is declared as a Flutter asset in `pubspec.yaml` and loaded at runtime via `flutter_dotenv`. **Never commit real API keys to version control.**

---

