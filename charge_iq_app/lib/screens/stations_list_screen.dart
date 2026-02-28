import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'dart:math' show cos, sqrt, asin, sin;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:charge_iq_app/screens/google_nav_screen.dart';
import '../models/vehicle.dart';
import '../services/vehicle_service.dart';

class StationsListScreen extends StatefulWidget {
  const StationsListScreen({super.key});

  @override
  State<StationsListScreen> createState() => _StationsListScreenState();
}

class _StationsListScreenState extends State<StationsListScreen> {
  late String apiKey;
  List<Map<String, dynamic>> allStations = [];
  List<Map<String, dynamic>> filteredStations = [];
  LatLng? currentLocation;
  String? currentAddressShort;
  bool isLoading = true;
  String selectedFilter = 'All Types';
  bool isSearching = false;
  TextEditingController searchController = TextEditingController();

  final VehicleService _vehicleService = VehicleService();
  List<Vehicle> userVehicles = [];
  Vehicle? selectedVehicle;

  // Cache settings
  static const String CACHE_KEY = 'ev_stations_cache';
  static const String CACHE_TIMESTAMP_KEY = 'ev_stations_timestamp';
  static const int CACHE_DURATION_DAYS = 7;
  static const double SEARCH_RADIUS_KM = 30.0;

  @override
  void initState() {
    super.initState();
    apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    _loadUserVehicles();
    await _clearBadCache();
    await _getCurrentLocation();
    await _loadNearbyStations();
  }

  Future<void> _clearBadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(CACHE_KEY);
      if (cached != null) {
        final decoded = jsonDecode(cached) as List;
        if (decoded.isNotEmpty) {
          final first = Map<String, dynamic>.from(decoded[0] as Map);
          if (!first.containsKey('lat') || !first.containsKey('lng') || !first.containsKey('name')) {
            await prefs.remove(CACHE_KEY);
            await prefs.remove(CACHE_TIMESTAMP_KEY);
          }
        }
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(CACHE_KEY);
      await prefs.remove(CACHE_TIMESTAMP_KEY);
    }
  }

  void _loadUserVehicles() {
    _vehicleService.getUserVehicles().listen((vehicles) async {
      if (mounted) {
        setState(() {
          userVehicles = vehicles;
        });
        
        if (selectedVehicle == null && vehicles.isNotEmpty) {
          final defaultVehicle = await _vehicleService.getDefaultVehicle();
          if (mounted) {
            setState(() {
              // Try to find the default vehicle in the loaded list, or just use the first one
              if (defaultVehicle != null) {
                try {
                  selectedVehicle = vehicles.firstWhere((v) => v.id == defaultVehicle.id);
                } catch (_) {
                  selectedVehicle = vehicles.first;
                }
              } else {
                selectedVehicle = vehicles.first;
              }
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    try {
      final status = await Permission.location.status;

      if (status.isDenied) {
        final result = await Permission.location.request();
        if (!result.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Location permission is required to find stations')),
            );
          }
          return;
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _showPermissionDialog();
        }
        return;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showLocationServicesDialog();
        }
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
      });

      await _updateCurrentLocationAddress();
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error getting your location')),
        );
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Location Permission'),
        content: const Text(
            'Location permission is permanently denied. Please enable it in app settings.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showLocationServicesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Location Services'),
        content: const Text('Please enable location services to find nearby stations.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Geolocator.openLocationSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateCurrentLocationAddress() async {
    if (currentLocation == null) return;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${currentLocation!.latitude},${currentLocation!.longitude}&key=$apiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['results'].isNotEmpty) {
          final address = json['results'][0]['formatted_address'] as String;
          final parts = address.split(',');
          setState(() {
            currentAddressShort = parts.length >= 2
                ? '${parts[parts.length - 2].trim()}, ${parts.last.trim()}'
                : address;
          });
        }
      }
    } catch (e) {
      debugPrint('Error updating address: $e');
    }
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

    double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }

  Future<bool> _isCacheValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(CACHE_TIMESTAMP_KEY);
      if (timestamp == null) return false;

      final now = DateTime.now().millisecondsSinceEpoch;
      final cacheDurationMs = CACHE_DURATION_DAYS * 24 * 60 * 60 * 1000;

      return (now - timestamp) < cacheDurationMs;
    } catch (e) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> _loadCachedStations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(CACHE_KEY);
      if (cached != null) {
        final List<dynamic> decoded = jsonDecode(cached);
        return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('Error loading cache: $e');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(CACHE_KEY);
      await prefs.remove(CACHE_TIMESTAMP_KEY);
    }
    return null;
  }

  Future<void> _saveStationsToCache(List<Map<String, dynamic>> stations) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(CACHE_KEY, jsonEncode(stations));
      await prefs.setInt(CACHE_TIMESTAMP_KEY, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving cache: $e');
    }
  }

  // Load nearby stations from Google Places API
  Future<void> _loadNearbyStations({String? keyword}) async {
    if (currentLocation == null) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
      return;
    }

    try {
      // Check cache first ONLY if no keyword is provided (we don't cache keyword searches right now to keep it simple)
      if (keyword == null && await _isCacheValid()) {
        final cached = await _loadCachedStations();
        if (cached != null && cached.isNotEmpty) {
          if (mounted) {
            setState(() {
              allStations = cached;
              filteredStations = cached;
              isLoading = false;
            });
          }
          return;
        }
      }

      // Fetch from Google Places API
      const String placeType = 'electric_vehicle_charging_station';
      final int radiusMeters = (SEARCH_RADIUS_KM * 1000).toInt();

      String urlStr =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${currentLocation!.latitude},${currentLocation!.longitude}'
          '&radius=$radiusMeters'
          '&type=$placeType'
          '&key=$apiKey';

      if (keyword != null && keyword.isNotEmpty) {
        urlStr += '&keyword=${Uri.encodeComponent(keyword)}';
      }

      final url = Uri.parse(urlStr);

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> results = json['results'] ?? [];

        final List<Map<String, dynamic>> stations = [];

        for (final result in results) {
          try {
            final lat = result['geometry']['location']['lat'] as double;
            final lng = result['geometry']['location']['lng'] as double;
            final stationLocation = LatLng(lat, lng);
            final distance = _calculateDistance(currentLocation!, stationLocation);

            // Only include stations within 30km
            if (distance <= SEARCH_RADIUS_KM) {
              stations.add({
                'placeId': result['place_id'] as String,
                'name': result['name'] as String,
                'vicinity': result['vicinity'] as String,
                'lat': lat,
                'lng': lng,
                'distance': distance,
                'rating': (result['rating'] as num?)?.toDouble() ?? 0.0,
                'userRatingsTotal': result['user_ratings_total'] as int? ?? 0,
                'isOpen': result['opening_hours']?['open_now'] as bool? ?? true,
              });
            }
          } catch (e) {
            debugPrint('Error parsing station: $e');
            continue;
          }
        }

        // Sort by distance
        stations.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

        // Save to cache
        await _saveStationsToCache(stations);

        if (mounted) {
          setState(() {
            allStations = stations;
            filteredStations = stations;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to load stations')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading stations: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading stations')),
        );
      }
    }
  }

  void _applyFilter(String filter) {
    setState(() {
      selectedFilter = filter;
    });

    _searchStations(searchController.text);
  }

  void _searchStations(String query) {
    List<Map<String, dynamic>> results = List.from(allStations);

    // Apply Filter
    if (selectedFilter == 'Available Now') {
      results = results.where((s) => s['isOpen'] == true).toList();
    }

    // Apply search
    if (query.isNotEmpty) {
      results = results
          .where((s) =>
              s['name'].toString().toLowerCase().contains(query.toLowerCase()) ||
              s['vicinity'].toString().toLowerCase().contains(query.toLowerCase()))
          .toList();
    }

    setState(() {
      filteredStations = results;
    });
  }

  Future<void> _fetchStationsForVehicle(Vehicle vehicle) async {
    setState(() {
      selectedVehicle = vehicle;
      isLoading = true;
    });

    String keyword = vehicle.brand;
    final portLower = vehicle.chargingPortType.toLowerCase();
    
    if (vehicle.brand.toLowerCase() == 'tesla') {
      keyword = 'Tesla Supercharger';
    } else if (portLower.contains('ccs') || portLower.contains('chademo')) {
      keyword = '${vehicle.brand} ${vehicle.chargingPortType} charging';
    } else {
      keyword = '${vehicle.brand} EV charging';
    }

    await _loadNearbyStations(keyword: keyword);
  }

  void _showStationDetailsModal(Map<String, dynamic> station) {
    final distance = station['distance']?.toStringAsFixed(1) ?? 'N/A';
    final rating = station['rating']?.toDouble() ?? 0.0;
    final totalRatings = station['userRatingsTotal'] ?? 0;
    final isOpen = station['isOpen'] ?? false; 
    final name = station['name'] ?? 'Unknown';
    final location = station['vicinity'] ?? 'Unknown';
    final lat = station['lat'] as double;
    final lng = station['lng'] as double;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF4285F4),
                      Color(0xFF3367D6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.ev_station,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
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
                                color: Colors.white.withOpacity(0.9),
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$distance km away',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
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
                          color:
                              isOpen ? Colors.green[50] : Colors.red[50],
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
                                color: isOpen
                                    ? Colors.green[900]
                                    : Colors.red[900],
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Rating
                    if (rating > 0)
                      Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 20),
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
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[600]),
                          ),
                        ],
                      ),

                    const SizedBox(height: 16),

                    // Address
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.place,
                            color: Colors.grey[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            location,
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

                    // Action Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (ctx) => GoogleNavScreen(
                                destinationLat: lat,
                                destinationLng: lng,
                                destinationName: name,
                                destinationAddress: location,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text(
                          'Start Navigation',
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFF00D26A),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Loading nearby stations...',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : Stack(
              children: [
                // Blue Background Header
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1565C0),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(30),
                      bottomRight: Radius.circular(30),
                    ),
                  ),
                ),

                SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Content
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nearby Stations',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 100), // Adjusted space for floating box

                      // Summary Cards
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSummaryCard(
                              allStations.length.toString(),
                              'Stations',
                            ),
                            _buildSummaryCard(
                              filteredStations.length.toString(),
                              selectedFilter,
                              textColor: const Color(0xFF00D26A),
                            ),
                            _buildSummaryCard(
                              allStations.isNotEmpty
                                  ? '${(allStations.first['distance'] as double).toStringAsFixed(1)} km'
                                  : 'N/A',
                              'Nearest',
                              textColor: const Color(0xFF2962FF),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Stations List
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: filteredStations.isEmpty
                              ? [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 40),
                                    child: Center(
                                      child: Text(
                                        'No stations found',
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 16),
                                      ),
                                    ),
                                  ),
                                ]
                              : filteredStations
                                  .map(
                                    (station) => _buildStationCard(
                                      station: station,
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                    ],
                  ),
                ),

                // Floating Search Box
                Positioned(
                  top: 90,
                  left: 20,
                  right: 20,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Vehicle Selector Dropdown
                        Padding(
                          padding: const EdgeInsets.only(left: 4, right: 4, top: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: userVehicles.isEmpty 
                                    ? null 
                                    : (userVehicles.any((v) => v.id == selectedVehicle?.id) 
                                        ? selectedVehicle?.id 
                                        : userVehicles.first.id),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF1565C0)),
                                isExpanded: true,
                                hint: userVehicles.isEmpty 
                                    ? Row(
                                        children: [
                                          const Icon(Icons.electric_car_rounded, color: Colors.grey, size: 18),
                                          const SizedBox(width: 10),
                                          const Text('No vehicles saved. Add in Profile.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                                        ],
                                      )
                                    : null,
                                style: const TextStyle(
                                  color: Color(0xFF1E293B),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                onChanged: userVehicles.isEmpty ? null : (String? newId) {
                                  if (newId != null && newId != selectedVehicle?.id) {
                                    final newValue = userVehicles.firstWhere((v) => v.id == newId);
                                    _fetchStationsForVehicle(newValue);
                                  }
                                },
                                items: userVehicles.isEmpty ? [] : userVehicles.map<DropdownMenuItem<String?>>((Vehicle vehicle) {
                                  return DropdownMenuItem<String?>(
                                    value: vehicle.id,
                                    child: Row(
                                      children: [
                                        const Icon(Icons.electric_car_rounded, color: Color(0xFF1565C0), size: 18),
                                        const SizedBox(width: 10),
                                        Text('${vehicle.brand} ${vehicle.model}'),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),

                        // Search Bar - Improved padding
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(
                            children: [
                              Icon(Icons.search,
                                  color: Colors.grey[400], size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: searchController,
                                  onChanged: _searchStations,
                                  decoration: InputDecoration(
                                    hintText: 'Search stations...',
                                    hintStyle: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Visual Divider
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Divider(
                            height: 1,
                            color: Colors.grey[200],
                          ),
                        ),

                        // Filter Chips - Improved spacing
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                          child: Row(
                            children: [
                              _buildFilterChip('All Types',
                                  isSelected: selectedFilter == 'All Types'),
                              const SizedBox(width: 12),
                              _buildFilterChip('Available Now',
                                  isSelected:
                                      selectedFilter == 'Available Now'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, {bool isSelected = false}) {
    return GestureDetector(
      onTap: () => _applyFilter(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF4285F4) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(color: Colors.transparent)
              : Border.all(color: Colors.grey.shade300),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String value,
    String label, {
    Color textColor = Colors.black,
  }) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildStationCard({
    required Map<String, dynamic> station,
  }) {
    final name = station['name'] as String;
    final location = station['vicinity'] as String;
    final distance = (station['distance'] as double).toStringAsFixed(1);
    final rating = station['rating'] as double;
    final totalRatings = station['userRatingsTotal'] ?? 0;
    final isOpen = station['isOpen'] ?? false;

    // Add visual cues if it matches the selected vehicle implicitly (e.g. Tesla for Supercharger)
    bool isRecommended = false;
    if (selectedVehicle != null) {
      final brand = selectedVehicle!.brand.toLowerCase();
      final nameLower = name.toLowerCase();
      if ((brand.contains('tesla') && nameLower.contains('supercharger')) ||
          nameLower.contains(brand)) {
        isRecommended = true;
      }
    }

    return GestureDetector(
      onTap: () => _showStationDetailsModal(station),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isRecommended ? Border.all(color: const Color(0xFF4285F4), width: 1.5) : Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isRecommended)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.stars_rounded, color: Color(0xFF4285F4), size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Recommended for your EV',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00D26A), Color(0xFF00BFA5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D26A).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.ev_station_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                  color: Color(0xFF1E293B),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded, size: 14, color: Colors.grey[500]),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      location,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Distance Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4285F4).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.near_me_rounded, color: Color(0xFF4285F4), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '${distance}km',
                                style: const TextStyle(
                                  color: Color(0xFF4285F4),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    const SizedBox(height: 16),

                    // Status and Details Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isOpen ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: isOpen ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOpen ? 'Open Now' : 'Closed',
                                style: TextStyle(
                                  color: isOpen ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Rating
                        if (rating > 0)
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFB45309), // Dark amber
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (totalRatings > 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '($totalRatings)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
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
}
