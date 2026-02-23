import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' show cos, sqrt, asin;
import 'package:charge_iq_app/screens/google_nav_screen.dart';
import 'package:charge_iq_app/services/gemini_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  late String apiKey;
  Set<Marker> markers = {};
  Set<Polyline> polylines = {};
  GoogleMapController? mapController;
  final TextEditingController searchController = TextEditingController();
  bool isLoadingStations = false;
  bool isLoadingDirections = false;
  bool isAISelectingStation = false;
  LatLng? currentLocation;
  String? currentAddressShort;
  BitmapDescriptor? customEVIcon;
  BitmapDescriptor? customLocationIcon;
  Map<String, dynamic>? selectedStation;
  final GeminiService _geminiService = GeminiService();

  // Trip route state
  bool _showingTripRoute = false;
  String _tripDistance = '';
  String _tripDuration = '';
  String _tripDestination = '';
  LatLng? _tripDestLatLng;
  List<Map<String, dynamic>> _tripStops = [];

  // Search state
  List<Map<String, dynamic>> _allLoadedStations = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _showSearchResults = false;

  // Quick Charge AI setting
  bool useAIForQuickCharge = true;

  // Cache settings
  static const String CACHE_KEY = 'ev_stations_cache';
  static const String CACHE_TIMESTAMP_KEY = 'ev_stations_timestamp';
  static const int CACHE_DURATION_DAYS = 7;
  static const double SEARCH_RADIUS_KM = 30.0;

  @override
  void initState() {
    super.initState();
    apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
    searchController.addListener(_onSearchChanged);
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _loadCustomMarkers();
    await _loadAIPref();
    await getCurrentLocation();
  }

  Future<void> _loadAIPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        useAIForQuickCharge = prefs.getBool('quick_charge_use_ai') ?? true;
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadCustomMarkers() async {
    customEVIcon = await _createCustomMarkerBitmap(
      '⚡',
      const Color(0xFF10B981),
      Colors.white,
    );
    customLocationIcon = await _createCustomMarkerBitmap(
      '📍',
      const Color(0xFF3B82F6),
      Colors.white,
    );
  }

  Future<BitmapDescriptor> _createCustomMarkerBitmap(
    String emoji,
    Color bgColor,
    Color borderColor,
  ) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double size = 120.0;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(
      Offset(size / 2 + 2, size / 2 + 2),
      size / 2,
      shadowPaint,
    );

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(size / 2, size / 2),
        size / 2,
        [bgColor, bgColor.withOpacity(0.8)],
        [0.0, 1.0],
      );
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 3, borderPaint);

    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: emoji,
      style: const TextStyle(fontSize: 60.0),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
    );

    final img = await pictureRecorder.endRecording().toImage(
      size.toInt(),
      size.toInt(),
    );
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // Calculate distance between two points in km
  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371; // km
    double lat1 = start.latitude * 3.141592653589793 / 180;
    double lat2 = end.latitude * 3.141592653589793 / 180;
    double lon1 = start.longitude * 3.141592653589793 / 180;
    double lon2 = end.longitude * 3.141592653589793 / 180;

    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;

    double a =
        (1 - cos(dLat)) / 2 + cos(lat1) * cos(lat2) * (1 - cos(dLon)) / 2;
    double c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }

  Future<bool> _isCacheValid() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(CACHE_TIMESTAMP_KEY);
    if (timestamp == null) return false;

    final cacheDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final difference = DateTime.now().difference(cacheDate).inDays;
    return difference < CACHE_DURATION_DAYS;
  }

  Future<List<Map<String, dynamic>>?> _loadCachedStations() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheString = prefs.getString(CACHE_KEY);
    if (cacheString == null) return null;

    final List<dynamic> decoded = jsonDecode(cacheString);
    return decoded.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<void> _saveStationsToCache(List<Map<String, dynamic>> stations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CACHE_KEY, jsonEncode(stations));
    await prefs.setInt(
      CACHE_TIMESTAMP_KEY,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> getCurrentLocation() async {
    try {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
      }

      if (status.isPermanentlyDenied) {
        await _showPermissionDialog();
        return;
      }

      if (!status.isGranted) {
        await _showPermissionDialog();
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _showLocationServicesDialog();
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
        markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
            position: currentLocation!,
            icon:
                customLocationIcon ??
                BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: 'Your Location',
              snippet: currentAddressShort,
            ),
          ),
        );
      });

      mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(currentLocation!, 13),
      );

      await _updateCurrentLocationAddress();

      // Auto-load nearby stations within 30km
      await loadNearbyStations();
    } catch (e) {
      debugPrint('Error getting location: $e');
      _showSnackBar('Unable to get your location', isError: true);
    }
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Permission Required'),
        content: const Text(
          'Enable location permission in Settings to find nearby chargers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLocationServicesDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Services Off'),
        content: const Text(
          'Turn on location services to get your current position.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateCurrentLocationAddress() async {
    if (currentLocation == null) return;

    try {
      final url =
          "https://maps.googleapis.com/maps/api/geocode/json"
          "?latlng=${currentLocation!.latitude},${currentLocation!.longitude}"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['results'] as List<dynamic>;

        if (results.isNotEmpty) {
          final shortAddress = _buildShortAddress(results[0]);

          if (!mounted) return;
          setState(() {
            currentAddressShort = shortAddress;
            markers.removeWhere((m) => m.markerId.value == 'current_location');
            markers.add(
              Marker(
                markerId: const MarkerId('current_location'),
                position: currentLocation!,
                icon:
                    customLocationIcon ??
                    BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueBlue,
                    ),
                infoWindow: InfoWindow(
                  title: 'Your Location',
                  snippet: currentAddressShort,
                ),
              ),
            );
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching short address: $e');
    }
  }

  String _buildShortAddress(Map<String, dynamic> result) {
    final components = result['address_components'] as List<dynamic>?;
    if (components == null || components.isEmpty) {
      return (result['formatted_address'] ?? '').toString();
    }

    String? locality;
    String? adminArea2;
    String? adminArea1;

    for (final component in components) {
      final types = (component['types'] as List<dynamic>).cast<String>();
      if (types.contains('locality')) {
        locality = component['long_name']?.toString();
      } else if (types.contains('administrative_area_level_2')) {
        adminArea2 = component['long_name']?.toString();
      } else if (types.contains('administrative_area_level_1')) {
        adminArea1 = component['short_name']?.toString();
      }
    }

    final parts = <String>[];
    if (locality != null && locality!.isNotEmpty) parts.add(locality!);
    if (adminArea2 != null && adminArea2!.isNotEmpty) parts.add(adminArea2!);
    if (adminArea1 != null && adminArea1!.isNotEmpty) parts.add(adminArea1!);

    if (parts.isEmpty) {
      return (result['formatted_address'] ?? '').toString();
    }

    return parts.join(', ');
  }

  // Load stations within 30km of user location
  Future<void> loadNearbyStations() async {
    if (currentLocation == null) {
      _showSnackBar('Getting your location first...', isError: true);
      return;
    }

    if (isLoadingStations) return;

    setState(() {
      isLoadingStations = true;
    });

    try {
      // Check cache first
      if (await _isCacheValid()) {
        final cached = await _loadCachedStations();
        if (cached != null && cached.isNotEmpty) {
          // Filter cached stations by distance
          final nearby = cached.where((station) {
            final stationPos = LatLng(station['lat'], station['lng']);
            final distance = _calculateDistance(currentLocation!, stationPos);
            return distance <= SEARCH_RADIUS_KM;
          }).toList();

          if (nearby.isNotEmpty) {
            debugPrint('Loaded ${nearby.length} nearby stations from cache');
            _displayStations(nearby);
            setState(() {
              _allLoadedStations = nearby;
              isLoadingStations = false;
            });
            return;
          }
        }
      }

      // Load from API
      debugPrint('Searching for stations within ${SEARCH_RADIUS_KM}km...');

      final radiusMeters = (SEARCH_RADIUS_KM * 1000).toInt();
      final url =
          "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
          "?location=${currentLocation!.latitude},${currentLocation!.longitude}"
          "&radius=$radiusMeters"
          "&keyword=ev charging station electric vehicle"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final results = json['results'] as List;

        List<Map<String, dynamic>> stationData = [];

        for (var place in results) {
          final lat = place['geometry']['location']['lat'];
          final lng = place['geometry']['location']['lng'];
          final name = place['name'];
          final id = place['place_id'];
          final vicinity = place['vicinity'] ?? '';
          final rating = place['rating']?.toDouble() ?? 0.0;
          final userRatingsTotal = place['user_ratings_total'] ?? 0;
          final isOpen = place['opening_hours']?['open_now'];

          final stationPos = LatLng(lat, lng);
          final distance = _calculateDistance(currentLocation!, stationPos);

          final stationInfo = {
            'id': id,
            'name': name,
            'lat': lat,
            'lng': lng,
            'vicinity': vicinity,
            'rating': rating,
            'userRatingsTotal': userRatingsTotal,
            'isOpen': isOpen,
            'distance': distance,
          };

          stationData.add(stationInfo);
        }

        // Sort by distance (closest first)
        stationData.sort(
          (a, b) =>
              (a['distance'] as double).compareTo(b['distance'] as double),
        );

        // Save to cache
        await _saveStationsToCache(stationData);

        _displayStations(stationData);

        setState(() {
          _allLoadedStations = stationData;
        });

        debugPrint(
          '✅ Found ${stationData.length} stations within ${SEARCH_RADIUS_KM}km',
        );
        _showSnackBar('Found ${stationData.length} charging stations nearby');
      }
    } catch (e) {
      debugPrint('Error loading stations: $e');
      _showSnackBar('Unable to load stations', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isLoadingStations = false;
        });
      }
    }
  }

  /// Quick Charge Action - Find and route to the BEST EV charging station
  /// "Best" is determined by a weighted score of: Availability, Price, Rating, and Distance.
  Future<void> quickCharge() async {
    // Step 1: Ensure we have current location
    if (currentLocation == null) {
      _showSnackBar('Getting your location...', isError: false);
      await getCurrentLocation();
      if (currentLocation == null) {
        _showSnackBar('Unable to get your location', isError: true);
        return;
      }
    }

    // Step 2: Load nearby stations
    setState(() {
      isLoadingStations = true;
    });

    try {
      debugPrint('Quick Charge: Finding BEST station within 30km...');

      List<Map<String, dynamic>> nearbyStations = [];

      // Check cache first
      if (await _isCacheValid()) {
        final cached = await _loadCachedStations();
        if (cached != null && cached.isNotEmpty) {
          nearbyStations = cached.where((station) {
            final stationPos = LatLng(station['lat'], station['lng']);
            final distance = _calculateDistance(currentLocation!, stationPos);
            // Update distance in case location changed slightly
            station['distance'] = distance;
            return distance <= SEARCH_RADIUS_KM;
          }).toList();
        }
      }

      // If no cached stations, fetch from API
      if (nearbyStations.isEmpty) {
        final radiusMeters = (SEARCH_RADIUS_KM * 1000).toInt();
        final url =
            "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
            "?location=${currentLocation!.latitude},${currentLocation!.longitude}"
            "&radius=$radiusMeters"
            "&keyword=ev charging station electric vehicle"
            "&key=$apiKey";

        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final results = json['results'] as List;

          for (var place in results) {
            final lat = place['geometry']['location']['lat'];
            final lng = place['geometry']['location']['lng'];
            final name = place['name'];
            final id = place['place_id'];
            final vicinity = place['vicinity'] ?? '';
            final rating = place['rating']?.toDouble() ?? 0.0;
            final userRatingsTotal = place['user_ratings_total'] ?? 0;
            final isOpen = place['opening_hours']?['open_now'];

            final stationPos = LatLng(lat, lng);
            final distance = _calculateDistance(currentLocation!, stationPos);

            if (distance <= SEARCH_RADIUS_KM) {
              nearbyStations.add({
                'id': id,
                'name': name,
                'lat': lat,
                'lng': lng,
                'vicinity': vicinity,
                'rating': rating,
                'userRatingsTotal': userRatingsTotal,
                'isOpen': isOpen,
                'distance': distance,
              });
            }
          }

          // Cache the raw results
          if (nearbyStations.isNotEmpty) {
            await _saveStationsToCache(nearbyStations);
          }
        }
      }

      // Step 3: Handle results - Logic for "Best" Station
      if (nearbyStations.isEmpty) {
        _showSnackBar('No charging stations found within 30km', isError: true);
        setState(() {
          isLoadingStations = false;
        });
        return;
      }

      // Calculate Score based on available data
      // If specific real-time data is missing (e.g. ports, price), we degrade gracefully
      // by relying on standard metrics: Open Status, Rating, Review Count, and Distance.

      for (var station in nearbyStations) {
        // NOTE: Real-time 'available_ports' and 'price' are not reliably available
        // from standard free APIs. We proceed with what we have.
        // If your backend or a premium API provides this, populate it here.

        final int? available = station['available_ports'];
        final double? price = station['price'];
        final double rating = station['rating'] ?? 0.0;
        final int ratingCount = station['userRatingsTotal'] ?? 0;
        final double distance = station['distance'];
        final bool? isOpen = station['isOpen'];

        // Scoring Algorithm (Graceful Fallback Mode):
        // 1. Open Status: Critical.
        // 2. Rating: Very Important when other data is missing.
        // 3. Distance: Always distinct.
        // 4. Popularity: (ratingCount) - adds confidence.

        double score = 0.0;

        // -- Status --
        if (isOpen == true)
          score += 100.0; // Huge bonus for being definitely open
        if (isOpen == false) score -= 200.0; // Huge penalty for being closed

        // -- Quality --
        // Weight rating heavily (0-5 stars -> 0-50 pts)
        score += (rating * 10.0);

        // Boost for popularity (logarithmic to avoid outlier skew)
        if (ratingCount > 0) {
          score += (sqrt(ratingCount) * 0.5); // e.g. 100 reviews -> +5 pts
        }

        // -- Distance --
        // Penalize distance (e.g. 10km away -> -20 pts)
        score -= (distance * 2.0);

        // -- Real-time Data (If available) --
        if (available != null) {
          score += (available * 5.0); // Reward known availability
        }

        if (price != null) {
          score -= (price * 100.0); // Penalize price if known
        } else {
          // If price unknown, we don't penalize, or assumes average.
          // Leaving at 0 (neutral) is safer than guessing.
        }

        station['score'] = score;
      }

      // Sort by Score Descending (Best First)
      nearbyStations.sort((a, b) {
        final scoreA = a['score'] as double;
        final scoreB = b['score'] as double;
        return scoreB.compareTo(scoreA);
      });

      // Display all nearby stations on map
      _displayStations(nearbyStations);

      // Step 4: Optionally use AI to refine selection
      Map<String, dynamic>? bestStation;

      if (useAIForQuickCharge) {
        setState(() {
          isAISelectingStation = true;
        });

        debugPrint('Quick Charge: Asking AI to select optimal station...');

        final aiSelectedStation = await _geminiService.selectOptimalStation(
          nearbyStations: nearbyStations,
          currentLatitude: currentLocation!.latitude,
          currentLongitude: currentLocation!.longitude,
        );

        if (!mounted) return;

        setState(() {
          isAISelectingStation = false;
        });

        bestStation = aiSelectedStation ?? nearbyStations.first;
      } else {
        // Scoring-only: top of already-sorted list
        bestStation = nearbyStations.first;
        debugPrint('Quick Charge: Using scoring algorithm (AI disabled).');
      }

      // Step 5: debug info
      final debugPrice = bestStation['price'] != null
          ? '\$${(bestStation['price']).toStringAsFixed(2)}'
          : 'N/A';
      final debugPorts = bestStation['available_ports']?.toString() ?? 'N/A';
      final selMethod = bestStation['selected_via_ai'] == true
          ? '[AI Selected - ${(bestStation['ai_confidence'] * 100).toStringAsFixed(0)}% confidence]'
          : '[Score-based]';

      debugPrint(
        'Best station: ${bestStation['name']} '
        '(Dist: ${bestStation['distance'].toStringAsFixed(1)}km, '
        'Ports: $debugPorts, '
        'Price: $debugPrice) $selMethod',
      );

      // Step 6: Show the best station details card
      _showStationDetails(bestStation);

      // Center map on best station
      final bestPos = LatLng(bestStation['lat'], bestStation['lng']);
      mapController?.animateCamera(CameraUpdate.newLatLngZoom(bestPos, 15));
    } catch (e) {
      debugPrint('Quick Charge error: $e');
      _showSnackBar('Unable to find charging stations', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isLoadingStations = false;
        });
      }
    }
  }

  void _displayStations(List<Map<String, dynamic>> stations) {
    if (!mounted) return;

    setState(() {
      // Remove old station markers
      markers.removeWhere((m) => m.markerId.value.startsWith('ChIJ'));

      for (var station in stations) {
        markers.add(
          Marker(
            markerId: MarkerId(station['id']),
            position: LatLng(station['lat'], station['lng']),
            icon:
                customEVIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
            onTap: () => _showStationDetails(station),
          ),
        );
      }
    });
  }

  // Show professional station details card
  void _showStationDetails(Map<String, dynamic> station) {
    setState(() {
      selectedStation = station;
      polylines.clear(); // Clear any existing route
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildStationDetailsCard(station),
    );
  }

  Widget _buildStationDetailsCard(Map<String, dynamic> station) {
    final distance = station['distance']?.toStringAsFixed(1) ?? 'N/A';
    final rating = station['rating']?.toDouble() ?? 0.0;
    final totalRatings = station['userRatingsTotal'] ?? 0;
    final isOpen = station['isOpen'];

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.ev_station,
                    color: Color(0xFF4285F4),
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        station['name'],
                        style: const TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Colors.grey[500],
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$distance km away',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status Badge
                if (isOpen != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isOpen ? Colors.green[50] : Colors.red[50],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isOpen ? Colors.green : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isOpen ? Colors.green : Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOpen ? 'Open Now' : 'Closed',
                          style: TextStyle(
                            color: isOpen ? Colors.green[900] : Colors.red[900],
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // AI Selection Badge
                if (station['selected_via_ai'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF4285F4).withOpacity(0.5),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              color: Color(0xFF4285F4),
                              size: 14,
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'AI Recommended',
                              style: TextStyle(
                                color: Color(0xFF4285F4),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${((station['ai_confidence'] ?? 0.0) * 100).toStringAsFixed(0)}% confident',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          station['ai_reason'] ??
                              'Optimal choice based on analysis',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // Price and Availability (Best Match Details)
                if (station['available_ports'] != null ||
                    station['price'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        if (station['available_ports'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.charging_station,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${station['available_ports']} Ports',
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (station['available_ports'] != null &&
                            station['price'] != null)
                          const SizedBox(width: 8),
                        if (station['price'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.attach_money,
                                  size: 16,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 0),
                                Text(
                                  '${(station['price'] as double).toStringAsFixed(2)}/kWh',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                // Rating
                if (rating > 0)
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber[700], size: 20),
                      const SizedBox(width: 6),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '($totalRatings reviews)',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                    ],
                  ),

                const SizedBox(height: 16),

                // Address
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.place, color: Colors.grey[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        station['vicinity'],
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GoogleNavScreen(
                            destinationLat: station['lat'] as double,
                            destinationLng: station['lng'] as double,
                            destinationName:
                                station['name']?.toString() ?? 'EV Charger',
                            destinationAddress: station['vicinity']?.toString(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.navigation_rounded),
                    label: const Text(
                      'Navigate',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4285F4),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Center map on selected station
  void _centerOnStation(Map<String, dynamic> station) {
    final position = LatLng(station['lat'], station['lng']);
    mapController?.animateCamera(CameraUpdate.newLatLngZoom(position, 16));
  }

  // Get turn-by-turn directions
  Future<void> _getDirections(Map<String, dynamic> station) async {
    if (currentLocation == null) {
      _showSnackBar('Current location not available', isError: true);
      return;
    }

    setState(() {
      isLoadingDirections = true;
    });

    try {
      final destination = LatLng(station['lat'], station['lng']);

      final url =
          "https://maps.googleapis.com/maps/api/directions/json"
          "?origin=${currentLocation!.latitude},${currentLocation!.longitude}"
          "&destination=${destination.latitude},${destination.longitude}"
          "&mode=driving"
          "&key=$apiKey";

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['routes'] != null && json['routes'].isNotEmpty) {
          final route = json['routes'][0];
          final polylinePoints = route['overview_polyline']['points'];
          final legs = route['legs'][0];

          // Decode polyline
          final points = _decodePolyline(polylinePoints);

          setState(() {
            polylines.clear();
            polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: const Color(0xFF3B82F6),
                width: 5,
                patterns: [PatternItem.dot, PatternItem.gap(10)],
              ),
            );
          });

          // Zoom to show entire route
          _fitRouteBounds(currentLocation!, destination);

          // Show route info
          final duration = legs['duration']['text'];
          final distance = legs['distance']['text'];

          _showSnackBar('$distance • $duration');
        }
      }
    } catch (e) {
      debugPrint('Error getting directions: $e');
      _showSnackBar('Unable to get directions', isError: true);
    } finally {
      setState(() {
        isLoadingDirections = false;
      });
    }
  }

  // Decode Google polyline
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return points;
  }

  // Fit map to show entire route
  void _fitRouteBounds(LatLng start, LatLng end) {
    final bounds = LatLngBounds(
      southwest: LatLng(
        start.latitude < end.latitude ? start.latitude : end.latitude,
        start.longitude < end.longitude ? start.longitude : end.longitude,
      ),
      northeast: LatLng(
        start.latitude > end.latitude ? start.latitude : end.latitude,
        start.longitude > end.longitude ? start.longitude : end.longitude,
      ),
    );

    mapController?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.red[700] : Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // === Trip Route Integration ===

  Future<LatLng?> _geocodeAddress(String address) async {
    // If already lat,lng
    if (address.contains(',')) {
      final parts = address.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
    }
    // Current location
    if (address.toLowerCase().contains('current location')) {
      if (currentLocation != null) return currentLocation;
      try {
        Position pos = await Geolocator.getCurrentPosition();
        return LatLng(pos.latitude, pos.longitude);
      } catch (_) {
        return null;
      }
    }
    // Geocode via API
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(address)}'
        '&key=$apiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final loc = data['results'][0]['geometry']['location'];
          return LatLng(loc['lat'], loc['lng']);
        }
      }
    } catch (e) {
      debugPrint('Geocode error: $e');
    }
    return null;
  }

  /// Public method: called from outside to show a trip route on this map
  Future<void> showTripRoute({
    required String startLocation,
    required String destination,
    required List<dynamic> routeSegments,
  }) async {
    setState(() {
      isLoadingDirections = true;
      _showingTripRoute = true;
      _tripDestination = destination;
    });

    try {
      final startLatLng = await _geocodeAddress(startLocation);
      final destLatLng = await _geocodeAddress(destination);

      if (startLatLng == null || destLatLng == null) {
        _showSnackBar('Could not locate start or destination', isError: true);
        setState(() {
          isLoadingDirections = false;
          _showingTripRoute = false;
        });
        return;
      }

      // Save dest lat/lng for Google Navigation SDK
      _tripDestLatLng = destLatLng;

      // Collect waypoints and stop info from charge_meal segments
      List<LatLng> waypoints = [];
      List<Map<String, dynamic>> stops = [];

      for (var seg in routeSegments) {
        if (seg['segment_type'] == 'charge_meal') {
          final addr = seg['address']?.toString() ?? '';
          if (addr.isNotEmpty) {
            final wp = await _geocodeAddress(addr);
            if (wp != null) {
              waypoints.add(wp);
              stops.add({
                'position': wp,
                'name': seg['location_name'] ?? 'Charging Stop',
                'charging_time': seg['charging_time'] ?? '',
                'restaurant_name': seg['restaurant_name'] ?? '',
                'meal_type': seg['meal_type'] ?? '',
              });
            }
          }
        }
      }

      // Build directions URL with waypoints
      String waypointsParam = '';
      if (waypoints.isNotEmpty) {
        final wpStr = waypoints
            .map((w) => '${w.latitude},${w.longitude}')
            .join('|');
        waypointsParam = '&waypoints=$wpStr';
      }

      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json'
        '?origin=${startLatLng.latitude},${startLatLng.longitude}'
        '&destination=${destLatLng.latitude},${destLatLng.longitude}'
        '$waypointsParam'
        '&mode=driving'
        '&units=metric'
        '&key=$apiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylineEncoded = route['overview_polyline']['points'];
          final legs = route['legs'] as List;

          int totalDistM = 0;
          int totalDurS = 0;
          for (var leg in legs) {
            totalDistM += (leg['distance']['value'] as int);
            totalDurS += (leg['duration']['value'] as int);
          }

          final points = _decodePolyline(polylineEncoded);

          // Clear existing station markers & polylines
          setState(() {
            markers.removeWhere((m) => m.markerId.value != 'current_location');
            polylines.clear();

            // Add route polyline
            polylines.add(
              Polyline(
                polylineId: const PolylineId('trip_route'),
                points: points,
                color: const Color(0xFF4285F4),
                width: 5,
                startCap: Cap.roundCap,
                endCap: Cap.roundCap,
                jointType: JointType.round,
              ),
            );

            // Start marker
            markers.add(
              Marker(
                markerId: const MarkerId('trip_start'),
                position: startLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen,
                ),
                infoWindow: InfoWindow(title: 'Start', snippet: startLocation),
              ),
            );

            // Destination marker
            markers.add(
              Marker(
                markerId: const MarkerId('trip_dest'),
                position: destLatLng,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
                infoWindow: InfoWindow(
                  title: 'Destination',
                  snippet: destination,
                ),
              ),
            );

            // Charging station & restaurant markers
            for (int i = 0; i < stops.length; i++) {
              final stop = stops[i];
              final pos = stop['position'] as LatLng;

              // Charging station marker (orange)
              markers.add(
                Marker(
                  markerId: MarkerId('trip_charge_$i'),
                  position: pos,
                  icon:
                      customEVIcon ??
                      BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueOrange,
                      ),
                  infoWindow: InfoWindow(
                    title: '⚡ ${stop['name']}',
                    snippet: 'Charging: ${stop['charging_time']}',
                  ),
                ),
              );
            }

            _tripStops = stops;
            _tripDistance = totalDistM >= 1000
                ? '${(totalDistM / 1000).toStringAsFixed(1)} km'
                : '$totalDistM m';
            final hours = totalDurS ~/ 3600;
            final mins = (totalDurS % 3600) ~/ 60;
            _tripDuration = hours > 0 ? '${hours}h ${mins}m' : '${mins} min';

            isLoadingDirections = false;
          });

          // Fit map to show entire route
          if (points.length > 2) {
            double minLat = points.first.latitude;
            double maxLat = points.first.latitude;
            double minLng = points.first.longitude;
            double maxLng = points.first.longitude;
            for (var p in points) {
              if (p.latitude < minLat) minLat = p.latitude;
              if (p.latitude > maxLat) maxLat = p.latitude;
              if (p.longitude < minLng) minLng = p.longitude;
              if (p.longitude > maxLng) maxLng = p.longitude;
            }
            mapController?.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(minLat, minLng),
                  northeast: LatLng(maxLat, maxLng),
                ),
                80,
              ),
            );
          }
        } else {
          _showSnackBar('No route found', isError: true);
          setState(() {
            isLoadingDirections = false;
            _showingTripRoute = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Trip route error: $e');
      _showSnackBar('Failed to load route', isError: true);
      setState(() {
        isLoadingDirections = false;
        _showingTripRoute = false;
      });
    }
  }

  void _clearTripRoute() {
    setState(() {
      _showingTripRoute = false;
      _tripDistance = '';
      _tripDuration = '';
      _tripDestination = '';
      _tripDestLatLng = null;
      _tripStops = [];
      polylines.clear();
      markers.removeWhere((m) => m.markerId.value.startsWith('trip_'));
    });
    // Reload nearby stations
    loadNearbyStations();
  }

  /// Top bar when trip route is showing: white card with back button, destination name, address.
  Widget _buildTripRouteTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black26,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _clearTripRoute,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tripDestination.isNotEmpty
                          ? _tripDestination
                          : 'Destination',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_tripDestination.contains(',') ||
                        _tripDestination.contains('+'))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _tripDestination.length > 40
                              ? '${_tripDestination.substring(0, 40)}...'
                              : _tripDestination,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom panel: drag handle, distance/duration chips, Start Navigation button.
  Widget _buildTripRoutePanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Distance and duration chips
                Row(
                  children: [
                    Expanded(
                      child: _buildTripRouteInfoChip(
                        Icons.route_rounded,
                        _tripDistance.isNotEmpty ? _tripDistance : '—',
                        const Color(0xFF4285F4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTripRouteInfoChip(
                        Icons.access_time_filled_rounded,
                        _tripDuration.isNotEmpty ? _tripDuration : '—',
                        const Color(0xFFEA4335),
                      ),
                    ),
                  ],
                ),
                // Stops chips (when present)
                if (_tripStops.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 32,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tripStops.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, index) {
                        return _buildTripStopChip(_tripStops[index], index);
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Start Navigation — opens Google Navigation
                if (_tripDestLatLng != null)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GoogleNavScreen(
                              destinationLat: _tripDestLatLng!.latitude,
                              destinationLng: _tripDestLatLng!.longitude,
                              destinationName: _tripDestination.isNotEmpty
                                  ? _tripDestination
                                  : 'Destination',
                              destinationAddress: _tripDestination.length > 50
                                  ? _tripDestination
                                  : null,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: const Color(0xFF4285F4).withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.navigation_rounded, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Start Navigation',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTripRouteInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTripStopChip(Map<String, dynamic> stop, int index) {
    final hasRestaurant =
        (stop['restaurant_name'] ?? '').toString().isNotEmpty &&
        stop['restaurant_name'].toString().toLowerCase() != 'null';

    return GestureDetector(
      onTap: () {
        final pos = stop['position'] as LatLng;
        mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ev_station, size: 14, color: Color(0xFF10B981)),
            const SizedBox(width: 4),
            Text(
              stop['name'].toString().length > 15
                  ? '${stop['name'].toString().substring(0, 15)}...'
                  : stop['name'],
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF10B981),
              ),
            ),
            if (hasRestaurant) ...[
              const SizedBox(width: 4),
              const Icon(Icons.restaurant, size: 12, color: Color(0xFF9C27B0)),
            ],
          ],
        ),
      ),
    );
  }

  // Search functionality
  void _onSearchChanged() {
    final query = searchController.text.toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _showSearchResults = false;
        _searchResults = [];
      });
      return;
    }

    final results = _filterStations(query);
    setState(() {
      _searchResults = results;
      _showSearchResults = results.isNotEmpty;
    });
  }

  List<Map<String, dynamic>> _filterStations(String query) {
    return _allLoadedStations.where((station) {
      final name = station['name'].toString().toLowerCase();
      final vicinity = station['vicinity'].toString().toLowerCase();
      return name.contains(query) || vicinity.contains(query);
    }).toList();
  }

  Future<void> _selectStationFromSearch(Map<String, dynamic> station) async {
    // Close search results
    setState(() {
      _showSearchResults = false;
      searchController.clear();
    });

    // Show station details
    _showStationDetails(station);

    // Get directions to the station
    await _getDirections(station);
  }

  @override
  Widget build(BuildContext context) {
    final evStationCount = markers
        .where((m) => m.markerId.value != 'current_location')
        .length;

    return Scaffold(
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: LatLng(11.1271, 78.6569),
              zoom: 7,
            ),
            markers: markers,
            polylines: polylines,
            zoomControlsEnabled: false,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
            onMapCreated: (controller) {
              mapController = controller;
            },
            onTap: (_) {
              // Clear selected station when tapping map
              if (!_showingTripRoute) {
                setState(() {
                  selectedStation = null;
                  polylines.clear();
                });
              }
            },
          ),

          // Search Bar - Fixed at top
          if (!_showSearchResults)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search charging stations...',
                    hintStyle: TextStyle(color: Colors.grey[500]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close, color: Colors.grey[600]),
                            onPressed: () {
                              searchController.clear();
                              setState(() {
                                _showSearchResults = false;
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
            ),

          // Full Screen Search Results Overlay
          if (_showSearchResults)
            Positioned.fill(
              child: Container(
                color: Colors.white,
                child: Column(
                  children: [
                    // Search Input in Full Screen
                    Container(
                      padding: EdgeInsets.only(
                        top: MediaQuery.of(context).padding.top + 16,
                        left: 16,
                        right: 16,
                        bottom: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: TextField(
                                controller: searchController,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Search charging stations...',
                                  hintStyle: TextStyle(color: Colors.grey[500]),
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: Colors.grey[600],
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () {
                              searchController.clear();
                              setState(() {
                                _showSearchResults = false;
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Search Results List
                    Expanded(
                      child: _searchResults.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search,
                                    size: 80,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No stations found',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try searching with a different name or location',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _searchResults.length,
                              itemBuilder: (context, index) {
                                final station = _searchResults[index];
                                final distance =
                                    station['distance']?.toStringAsFixed(1) ??
                                    'N/A';
                                final rating =
                                    station['rating']?.toStringAsFixed(1) ??
                                    'N/A';

                                return InkWell(
                                  onTap: () =>
                                      _selectStationFromSearch(station),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.grey[200]!,
                                          width: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.ev_station,
                                            color: Color(0xFF10B981),
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                station['name'] ?? 'Station',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 16,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                station['vicinity'] ?? '',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (station['rating'] != 0)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.star,
                                                    size: 16,
                                                    color: Colors.amber[700],
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    rating,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${distance}km',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF4285F4),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),

          // Trip route loading overlay
          if (isLoadingDirections && _showingTripRoute)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF4285F4),
                  strokeWidth: 3,
                ),
              ),
            ),

          // Current Location Button (above trip panel when route is showing)
          Positioned(
            bottom: _showingTripRoute ? 220 : 40,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reload stations button
                if (evStationCount > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: loadNearbyStations,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.refresh,
                            color: Color(0xFF10B981),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),

                // My location button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: getCurrentLocation,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.my_location,
                          color: Color(0xFF3B82F6),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Trip route top bar (destination card) and bottom panel
          if (_showingTripRoute) ...[
            _buildTripRouteTopBar(),
            _buildTripRoutePanel(),
          ],

        ],
      ),
    );
  }
}
