# EV Charging Station Map - Tamil Nadu

A comprehensive Flutter application to locate EV charging stations across Tamil Nadu with real-time location tracking and search functionality.

## Features ✨

### 🗺️ Comprehensive Coverage
- **26+ Major Locations** covered across Tamil Nadu including:
  - Metro cities: Chennai, Coimbatore, Madurai, Trichy, Salem
  - Tier 2 cities: Vellore, Erode, Tiruppur, Thanjavur, Dindigul
  - Highway towns and tourist destinations
- **50km radius** search around each location for maximum coverage
- **Duplicate removal** ensures clean, non-overlapping markers

### 📍 Location Features
- **Current Location** button to instantly find your position
- **Blue marker** for your current location
- **Green markers** for EV charging stations
- **Orange markers** for search results
- Real-time location tracking with permission handling

### 🔍 Search Functionality
- Search bar at the top to find any place in Tamil Nadu
- Auto-search for nearby EV stations when you search a location
- Clear button to reset search
- Smooth camera animation to searched locations

### 📊 User Interface
- **Station count badge** showing total charging stations found
- **Legend** explaining different marker types
- **Loading indicator** during data fetch
- **Info windows** with station names and addresses on marker tap
- Clean, Material Design interface

### ⚡ Performance
- Efficient API calls with rate limiting
- Asynchronous loading to prevent UI freezing
- Smart duplicate detection
- Optimized marker rendering

## Setup Instructions 🛠️

### 1. Prerequisites
- Flutter SDK (3.0.0 or higher)
- Android Studio / Xcode
- Google Maps API Key with the following APIs enabled:
  - Maps SDK for Android
  - Maps SDK for iOS
  - Places API
  - Geocoding API

### 2. Get Google Maps API Key

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable the required APIs (listed above)
4. Go to "Credentials" → "Create Credentials" → "API Key"
5. Copy your API key

### 3. Project Setup

```bash
# Clone or create the project
flutter create ev_charging_map
cd ev_charging_map

# Replace the files with the provided ones
# - lib/map_screen.dart
# - pubspec.yaml
# - android/app/src/main/AndroidManifest.xml
# - ios/Runner/Info.plist
```

### 4. Configure API Key

#### Option A: Using .env file (Recommended)
1. Create a `.env` file in the root directory:
```
GOOGLE_MAPS_API_KEY=your_actual_api_key_here
```

2. Add `.env` to your `.gitignore`:
```
.env
```

#### Option B: Direct configuration
Replace `YOUR_GOOGLE_MAPS_API_KEY_HERE` in:
- `android/app/src/main/AndroidManifest.xml` (line with `com.google.android.geo.API_KEY`)
- `ios/Runner/Info.plist` (line with `GMSApiKey`)

### 5. Install Dependencies

```bash
flutter pub get
```

### 6. Android Configuration

In `android/app/src/main/AndroidManifest.xml`, replace:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_GOOGLE_MAPS_API_KEY_HERE"/>
```

With your actual API key.

### 7. iOS Configuration

In `ios/Runner/Info.plist`, replace:
```xml
<key>GMSApiKey</key>
<string>YOUR_GOOGLE_MAPS_API_KEY_HERE</string>
```

With your actual API key.

Also, ensure you have CocoaPods installed:
```bash
cd ios
pod install
cd ..
```

### 8. Run the App

```bash
# For Android
flutter run

# For iOS
flutter run -d ios

# For specific device
flutter devices
flutter run -d <device_id>
```

## Usage Guide 📱

### Finding Your Location
1. Tap the **blue circular button** (my location) on the right side
2. Grant location permissions when prompted
3. The map will center on your current location with a blue marker

### Searching for Places
1. Use the **search bar** at the top
2. Type any place name in Tamil Nadu (e.g., "Coimbatore", "Marina Beach")
3. Press Enter or search button
4. The map will show:
   - Orange marker for the searched location
   - Green markers for nearby EV stations

### Viewing Station Details
1. Tap any **green marker** to see:
   - Station name
   - Address/vicinity
2. The info window appears above the marker

### Understanding Markers
- 🔵 **Blue**: Your current location
- 🟢 **Green**: EV charging stations
- 🟠 **Orange**: Search results

## File Structure 📁

```
ev_charging_map/
├── lib/
│   └── map_screen.dart          # Main map screen widget
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml  # Android permissions & API key
├── ios/
│   └── Runner/
│       └── Info.plist           # iOS permissions & API key
├── pubspec.yaml                 # Dependencies
├── .env                         # API key (create this)
└── README.md                    # This file
```

## Dependencies 📦

- `google_maps_flutter: ^2.5.0` - Google Maps integration
- `http: ^1.1.0` - API calls
- `flutter_dotenv: ^5.1.0` - Environment variables
- `geolocator: ^10.1.0` - Location services
- `permission_handler: ^11.0.1` - Permission management

## Permissions ⚙️

### Android
- `ACCESS_FINE_LOCATION` - Precise location
- `ACCESS_COARSE_LOCATION` - Approximate location
- `INTERNET` - Network access

### iOS
- `NSLocationWhenInUseUsageDescription` - Location while using app
- `NSLocationAlwaysUsageDescription` - Background location
- `NSLocationAlwaysAndWhenInUseUsageDescription` - Combined permission

## API Usage 📊

The app makes calls to:
- **Places API - Nearby Search**: Find EV stations around coordinates
- **Places API - Find Place**: Search for user-entered locations
- Each location searched uses 2-3 API calls
- Initial load makes ~26 API calls (one per major location)

**Note**: Monitor your API usage in Google Cloud Console to avoid unexpected charges.

## Troubleshooting 🔧

### Map shows blank/gray tiles
- Verify your API key is correct
- Ensure Maps SDK for Android/iOS is enabled
- Check billing is enabled in Google Cloud Console

### Location not working
- Grant location permissions in device settings
- Enable location services (GPS)
- Check permission_handler configuration

### No charging stations appearing
- Verify Places API is enabled
- Check API key has no restrictions preventing access
- Look at console logs for API response errors

### Build errors
- Run `flutter clean` then `flutter pub get`
- For iOS: `cd ios && pod install && cd ..`
- Update Flutter: `flutter upgrade`

## Future Enhancements 🚀

Potential features to add:
- Filter by charging speed (Fast DC / Slow AC)
- Show charging station availability in real-time
- Route planning with charging stops
- User reviews and ratings
- Favorite stations
- Offline mode with cached data
- Navigation integration

## Contributing 🤝

Feel free to submit issues and enhancement requests!

## License 📄

This project is open source and available under the MIT License.

## Support 💬

For issues or questions:
1. Check the troubleshooting section
2. Review Google Maps Platform documentation
3. Check Flutter documentation for platform-specific issues

---

**Made with ❤️ for EV drivers in Tamil Nadu**