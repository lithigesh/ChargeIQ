# ChargeIQ

A Flutter application that helps electric vehicle (EV) owners find nearby charging stations, plan long-distance trips with smart charging stops, and navigate to their destination — all powered by Google Maps and Gemini AI.

---

## Features

- **Interactive EV Map** — Find charging stations near you on a live Google Map with custom markers and one-tap directions.
- **AI Quick Charge** — A single button uses Gemini AI to intelligently pick the best nearby station based on your vehicle and location.
- **Station Browser** — A searchable, filterable list of up to 60 nearby EV stations with drive-time estimates and vehicle-specific suggestions.
- **AI Trip Planner** — Plan a road trip by entering a destination; Gemini calculates optimal charging stops along the route.
- **Turn-by-Turn Navigation** — Full Google Navigation SDK integration with route preview and live guidance.
- **Vehicle Management** — Save multiple EVs with their range details and set a default vehicle.
- **Saved Stations** — Bookmark favourite charging stations synced via Firestore.
- **Trip History** — View and reload all previously planned trips.
- **User Profile & Stats** — Track routes taken, stations found, and time saved.
- **Dark Mode** — Full light/dark theme support throughout the app.
- **Premium Plans** — Subscription tier screen for unlocking advanced features.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Auth | Firebase Authentication (Email + Google Sign-In) |
| Database | Cloud Firestore |
| Analytics & Push | Firebase Analytics, Firebase Cloud Messaging |
| Maps | Google Maps Flutter |
| Navigation | Google Navigation Flutter SDK |
| AI | Google Generative AI (Gemini) |
| Places & Directions | Google Places API, Google Directions API |
| Location | Geolocator, Geocoding |
| Local Storage | SharedPreferences |
| Animations | Lottie |

---

## Screens

### Authentication
| Screen | Description |
|---|---|
| **Splash Screen** | Animated logo intro with scale and fade transitions. |
| **Sign In** | Email/password login and Google Sign-In. |
| **Sign Up** | New account creation with email and password. |

### Main App (Bottom Navigation)
| Tab | Description |
|---|---|
| **Map** | Interactive Google Map centred on the user's location. Shows custom EV station markers, a search bar with live autocomplete, station detail bottom-sheets, route polylines, and the AI Quick Charge FAB. |
| **Stations** | Paginated list of nearby EV stations (up to 60 via Google Places). Supports text search, charger-type filters, vehicle-specific filtering, and drive-duration estimates. |
| **Trip Planner** | Form to set start/destination, select one or more vehicles, choose departure time, and optionally include restaurant stops. Submits to Gemini AI to generate a charging-stop itinerary. |
| **Profile** | Displays user info, usage stats, default vehicle, AI preference toggle, dark mode switch, and links to sub-screens. |

### Detail & Sub-Screens
| Screen | Description |
|---|---|
| **Trip Result** | Shows the AI-generated trip plan with each charging stop, segment distances, and a "Start Navigation" button. |
| **Navigation** | In-app turn-by-turn directions rendered on Google Maps with a collapsible step-by-step panel. |
| **Google Nav** | Full Google Navigation SDK experience — route preview phase followed by active voice-guided navigation. Supports multi-waypoint charging stops from the trip planner. |
| **Manage Vehicles** | Add, edit, and delete EVs. Set a default vehicle used across the app. |
| **Saved Locations** | Firestore-synced list of bookmarked charging stations. One-tap to navigate. |
| **All Trips** | History of every saved trip plan. Tap any entry to reload the full trip result. |
| **Premium Plans** | Subscription tier cards with feature comparison. |

---

## Project Structure

```
lib/
├── main.dart
├── firebase_options.dart
├── models/
│   ├── vehicle.dart
│   └── trip_plan.dart
├── screens/           # All UI screens (see table above)
├── services/
│   ├── auth_service.dart
│   ├── vehicle_service.dart
│   ├── trip_service.dart
│   ├── places_service.dart
│   ├── directions_service.dart
│   ├── saved_location_service.dart
│   ├── gemini_service.dart
│   └── fcm_service.dart
├── utils/
└── widgets/
    └── app_lottie_loader.dart
```

---

## Getting Started

### Prerequisites

- Flutter SDK `^3.9.0`
- A Firebase project with **Authentication**, **Firestore**, and **Cloud Messaging** enabled
- Google Cloud project with the following APIs enabled:
  - Maps SDK for Android / iOS
  - Places API
  - Directions API
  - Navigation SDK for Android / iOS
  - Generative Language API (Gemini)

### Setup

1. **Clone the repo**
   ```bash
   git clone https://github.com/lithigesh/ChargeIQ.git
   cd ChargeIQ/charge_iq_app
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure environment variables**

   Create a `.env` file in `charge_iq_app/`:
   ```env
   GOOGLE_MAPS_API_KEY=your_google_maps_api_key
   GEMINI_API_KEY=your_gemini_api_key
   ```

4. **Add Firebase config files**
   - `android/app/google-services.json`
   - `ios/Runner/GoogleService-Info.plist`

5. **Run the app**
   ```bash
   flutter run
   ```

---

## License

This project is private and not published to pub.dev.