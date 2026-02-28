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

// ─────────────────────────────────────────────────────────────────────────────
// FIXES:
//  1. Paginate Google Places via next_page_token  → 60 stations instead of 20
//  2. Store location hash in cache key            → stale cache per location fixed
//  3. Replaced deprecated withOpacity()           → Color.fromRGBO / explicit alpha
//  4. AnimationController lifecycle               → _animationsActive guard + dispose order fixed
//  5. Vehicle keyword search now also paginates
//  6. LAYOUT: full redesign — compact header, horizontal scroll chips, cleaner cards
// ─────────────────────────────────────────────────────────────────────────────

class StationsListScreen extends StatefulWidget {
  const StationsListScreen({super.key});

  @override
  State<StationsListScreen> createState() => _StationsListScreenState();
}

class _StationsListScreenState extends State<StationsListScreen>
    with TickerProviderStateMixin {
  late String apiKey;
  List<Map<String, dynamic>> allStations = [];
  List<Map<String, dynamic>> filteredStations = [];
  LatLng? currentLocation;
  String? currentAddressShort;
  bool isLoading = true;
  String selectedFilter = 'All Types';
  TextEditingController searchController = TextEditingController();

  late AnimationController _loadingPulseController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  bool _animationsActive = false;

  final VehicleService _vehicleService = VehicleService();
  List<Vehicle> userVehicles = [];
  Vehicle? selectedVehicle;

  // Cache key is now location-aware (rounded to ~1 km grid)
  static const String CACHE_TIMESTAMP_KEY = 'ev_stations_timestamp';
  static const int CACHE_DURATION_DAYS = 7;
  static const double SEARCH_RADIUS_KM = 30.0;

  // ── Theme ──────────────────────────────────────────────────────────────────
  static const Color _primaryBlue = Color(0xFF1565C0);
  static const Color _darkBlue    = Color(0xFF0D47A1);
  static const Color _accentGreen = Color(0xFF00C853);
  static const Color _softBg      = Color(0xFFF4F6FB);
  static const Color _cardBg      = Colors.white;
  static const Color _textDark    = Color(0xFF1A1A2E);

  // ── Helpers for opacity-safe colors ───────────────────────────────────────
  static Color _blue(double opacity) => Color.fromRGBO(21, 101, 192, opacity);
  static Color _green(double opacity) => Color.fromRGBO(0, 200, 83, opacity);
  static Color _black(double opacity) => Color.fromRGBO(0, 0, 0, opacity);
  static Color _white(double opacity) => Color.fromRGBO(255, 255, 255, opacity);

  String _cacheKey(LatLng loc) {
    const int cacheVersion = 2; // bump to bust old non-EV cache
    final latGrid = (loc.latitude * 10).round();
    final lngGrid = (loc.longitude * 10).round();
    return 'ev_stations_v${cacheVersion}_${latGrid}_${lngGrid}';
  }

  @override
  void initState() {
    super.initState();
    apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

    _loadingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _loadingPulseController, curve: Curves.easeInOut),
    );

    _initializeScreen();
  }

  void _startAnimations() {
    if (!_animationsActive && mounted) {
      _animationsActive = true;
      _loadingPulseController.repeat(reverse: true);
      _shimmerController.repeat();
    }
  }

  void _stopAnimations() {
    if (_animationsActive) {
      _animationsActive = false;
      _loadingPulseController.stop();
      _shimmerController.stop();
      _loadingPulseController.reset();
      _shimmerController.reset();
    }
  }

  Future<void> _initializeScreen() async {
    _startAnimations();
    _loadUserVehicles();
    await _getCurrentLocation();
    await _loadNearbyStations();
    _stopAnimations();
  }

  void _loadUserVehicles() {
    _vehicleService.getUserVehicles().listen((vehicles) async {
      if (!mounted) return;
      setState(() => userVehicles = vehicles);
      if (selectedVehicle == null && vehicles.isNotEmpty) {
        final defaultVehicle = await _vehicleService.getDefaultVehicle();
        if (!mounted) return;
        setState(() {
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
    });
  }

  @override
  void dispose() {
    _stopAnimations();
    _loadingPulseController.dispose();
    _shimmerController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ── Location ───────────────────────────────────────────────────────────────

  Future<void> _getCurrentLocation() async {
    try {
      var status = await Permission.location.status;
      if (status.isDenied) {
        status = await Permission.location.request();
        if (!status.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required to find stations')));
          }
          return;
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) _showPermissionDialog();
        return;
      }
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) _showLocationServicesDialog();
        return;
      }
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      if (mounted) setState(() => currentLocation = LatLng(position.latitude, position.longitude));
      await _updateCurrentLocationAddress();
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error getting your location')));
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Location Permission'),
        content: const Text('Location permission is permanently denied. Please enable it in app settings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () { openAppSettings(); Navigator.pop(ctx); }, child: const Text('Open Settings')),
        ],
      ),
    );
  }

  void _showLocationServicesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Location Services'),
        content: const Text('Please enable location services to find nearby stations.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () { Geolocator.openLocationSettings(); Navigator.pop(ctx); },
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
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=${currentLocation!.latitude},${currentLocation!.longitude}'
        '&key=$apiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if ((json['results'] as List).isNotEmpty) {
          final address = json['results'][0]['formatted_address'] as String;
          final parts = address.split(',');
          if (mounted) {
            setState(() {
              currentAddressShort = parts.length >= 2
                  ? '${parts[parts.length - 2].trim()}, ${parts.last.trim()}'
                  : address;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating address: $e');
    }
  }

  // ── Distance ───────────────────────────────────────────────────────────────

  double _calculateDistance(LatLng start, LatLng end) {
    const double r = 6371;
    final lat1 = start.latitude * 3.141592653589793 / 180;
    final lat2 = end.latitude * 3.141592653589793 / 180;
    final lon1 = start.longitude * 3.141592653589793 / 180;
    final lon2 = end.longitude * 3.141592653589793 / 180;
    final a = sin((lat2 - lat1) / 2) * sin((lat2 - lat1) / 2) +
        cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) * sin((lon2 - lon1) / 2);
    return r * 2 * asin(sqrt(a));
  }

  // ── Cache ──────────────────────────────────────────────────────────────────

  Future<bool> _isCacheValid() async {
    if (currentLocation == null) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _cacheKey(currentLocation!);
      final cached = prefs.getString(key);
      if (cached == null) return false;
      final timestamp = prefs.getInt(CACHE_TIMESTAMP_KEY);
      if (timestamp == null) return false;
      return (DateTime.now().millisecondsSinceEpoch - timestamp) <
          CACHE_DURATION_DAYS * 24 * 60 * 60 * 1000;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>?> _loadCachedStations() async {
    if (currentLocation == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _cacheKey(currentLocation!);
      final cached = prefs.getString(key);
      if (cached != null) {
        final list = (jsonDecode(cached) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        // Validate structure
        if (list.isNotEmpty && list.first.containsKey('lat') && list.first.containsKey('name')) {
          return list;
        }
      }
    } catch (e) {
      debugPrint('Error loading cache: $e');
      if (currentLocation != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_cacheKey(currentLocation!));
      }
    }
    return null;
  }

  Future<void> _saveStationsToCache(List<Map<String, dynamic>> stations) async {
    if (currentLocation == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _cacheKey(currentLocation!);
      await prefs.setString(key, jsonEncode(stations));
      await prefs.setInt(CACHE_TIMESTAMP_KEY, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('Error saving cache: $e');
    }
  }

  // ── Fetch stations — paginated (up to 3 pages = 60 results) ───────────────
  //
  // FIX: The original code only called the API once, getting ≤20 results.
  // Google Places nearbysearch returns a `next_page_token` when more pages exist.
  // We follow up to 2 additional pages (60 results max) with a 2-second delay
  // between requests (required by the API).

  Future<List<Map<String, dynamic>>> _fetchAllPages(String initialUrl) async {
    final stations = <Map<String, dynamic>>[];

    Future<void> fetchPage(String url) async {
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) return;

        final json = jsonDecode(response.body);
        for (final result in (json['results'] ?? []) as List) {
          try {
            final lat = result['geometry']['location']['lat'] as double;
            final lng = result['geometry']['location']['lng'] as double;
            final name = (result['name'] as String? ?? '').toLowerCase();
            final distance = _calculateDistance(currentLocation!, LatLng(lat, lng));

            // ── EV-only gate — skip anything that isn't a charger ───────────
            // Google's type filter is not always strict on paginated pages,
            // so we double-check with a name / type check.
            final types = (result['types'] as List? ?? []).cast<String>();
            final isEvType = types.contains('electric_vehicle_charging_station');
            final hasEvName = name.contains('ev') ||
                name.contains('electric') ||
                name.contains('charge') ||
                name.contains('charger') ||
                name.contains('charging') ||
                name.contains('supercharger') ||
                name.contains('tesla') ||
                name.contains('electrify') ||
                name.contains('evgo') ||
                name.contains('blink') ||
                name.contains('chargepoint') ||
                name.contains('volta');
            if (!isEvType && !hasEvName) continue;
            // ────────────────────────────────────────────────────────────────

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
          }
        }

        // Follow next_page_token if available (max 2 extra pages)
        final nextToken = json['next_page_token'] as String?;
        if (nextToken != null && nextToken.isNotEmpty && stations.length < 60) {
          // Google requires a short delay before the token becomes valid
          await Future.delayed(const Duration(seconds: 2));
          final nextUrl =
              'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
              '?pagetoken=${Uri.encodeComponent(nextToken)}'
              '&key=$apiKey';
          await fetchPage(nextUrl);
        }
      } catch (e) {
        debugPrint('Error fetching page: $e');
      }
    }

    await fetchPage(initialUrl);
    return stations;
  }

  Future<void> _loadNearbyStations({String? keyword}) async {
    if (currentLocation == null) {
      if (mounted) setState(() => isLoading = false);
      return;
    }
    try {
      // Use cache only for the default (no keyword) load
      if (keyword == null && await _isCacheValid()) {
        final cached = await _loadCachedStations();
        if (cached != null && cached.isNotEmpty) {
          if (mounted) setState(() { allStations = cached; filteredStations = cached; isLoading = false; });
          return;
        }
      }

      final int radiusMeters = (SEARCH_RADIUS_KM * 1000).toInt();
      String initialUrl =
          'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
          '?location=${currentLocation!.latitude},${currentLocation!.longitude}'
          '&radius=$radiusMeters'
          '&type=electric_vehicle_charging_station'
          '&keyword=${Uri.encodeComponent(keyword ?? "electric vehicle charging station") }'
          '&key=$apiKey';

      final stations = await _fetchAllPages(initialUrl);
      stations.sort((a, b) => (a['distance'] as double).compareTo(b['distance'] as double));

      if (keyword == null) await _saveStationsToCache(stations);

      if (mounted) {
        setState(() { allStations = stations; filteredStations = stations; isLoading = false; });
      }
    } catch (e) {
      debugPrint('Error loading stations: $e');
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading stations')));
      }
    }
  }

  // ── Filter & search ────────────────────────────────────────────────────────

  void _applyFilter(String filter) {
    setState(() => selectedFilter = filter);
    _applyFiltersAndSearch(searchController.text);
  }

  void _searchStations(String query) => _applyFiltersAndSearch(query);

  void _applyFiltersAndSearch(String query) {
    List<Map<String, dynamic>> results = List.from(allStations);
    switch (selectedFilter) {
      case 'Available Now':
        results = results.where((s) => s['isOpen'] == true).toList();
        break;
      case 'Recommended':
        results = results.where(_isRecommendedForVehicle).toList();
        break;
      case 'Top Rated':
        results = results.where((s) => (s['rating'] as double) >= 4.0).toList();
        results.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
        break;
    }
    if (query.trim().isNotEmpty) {
      final q = query.toLowerCase();
      results = results.where((s) =>
        s['name'].toString().toLowerCase().contains(q) ||
        s['vicinity'].toString().toLowerCase().contains(q)).toList();
    }
    setState(() => filteredStations = results);
  }

  bool _isRecommendedForVehicle(Map<String, dynamic> station) {
    if (selectedVehicle == null) return false;
    final brand = selectedVehicle!.brand.toLowerCase();
    final nameLower = (station['name'] as String).toLowerCase();
    final portLower = selectedVehicle!.chargingPortType.toLowerCase();
    if (brand == 'tesla') return nameLower.contains('tesla') || nameLower.contains('supercharger');
    if (portLower.contains('chademo')) return nameLower.contains('chademo') || nameLower.contains('dc fast');
    if (portLower.contains('ccs')) {
      return nameLower.contains('ccs') || nameLower.contains('electrify') ||
             nameLower.contains('evgo') || nameLower.contains('chargepoint');
    }
    return nameLower.contains(brand);
  }

  Future<void> _fetchStationsForVehicle(Vehicle vehicle) async {
    _startAnimations();
    setState(() { selectedVehicle = vehicle; isLoading = true; });
    final portLower = vehicle.chargingPortType.toLowerCase();
    String keyword;
    if (vehicle.brand.toLowerCase() == 'tesla') {
      keyword = 'Tesla Supercharger';
    } else if (portLower.contains('ccs') || portLower.contains('chademo')) {
      keyword = '${vehicle.brand} ${vehicle.chargingPortType} charging';
    } else {
      keyword = '${vehicle.brand} EV charging';
    }
    await _loadNearbyStations(keyword: keyword);
    _stopAnimations();
  }

  int get _recommendedCount => allStations.where(_isRecommendedForVehicle).length;
  int get _openCount => allStations.where((s) => s['isOpen'] == true).length;
  int get _topRatedCount => allStations.where((s) => (s['rating'] as double) >= 4.0).length;

  // ─────────────────────────────────────────────────────────────────────────
  // LOADING SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: _softBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeaderGradient(scanning: true),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (_, __) => Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          color: _blue(0.08),
                          shape: BoxShape.circle,
                          border: Border.all(color: _blue(0.2), width: 2),
                        ),
                        child: const Icon(Icons.ev_station_rounded, size: 30, color: _primaryBlue),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_accentGreen),
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Scanning ${SEARCH_RADIUS_KM.toInt()} km for stations...',
                      style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(children: List.generate(3, (i) => _buildShimmerCard(index: i))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerCard({required int index}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (_, __) {
        final t = ((_shimmerController.value + index * 0.28) % 1.0);
        final shimmer = (t < 0.5 ? t * 2 : (1.0 - t) * 2).clamp(0.0, 1.0);
        final base = Color.lerp(const Color(0xFFEEEEEE), const Color(0xFFE0E0E0), shimmer)!;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: _black(0.04), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: base)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(height: 12, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: base)),
              const SizedBox(height: 8),
              Container(height: 10, width: 120, decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
                  color: Color.lerp(const Color(0xFFF5F5F5), const Color(0xFFEEEEEE), shimmer))),
            ])),
          ]),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MAIN SCREEN
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (isLoading) return _buildLoadingScreen();
    return Scaffold(
      backgroundColor: _softBg,
      body: SafeArea(
        child: Column(children: [
          _buildHeaderGradient(scanning: false),
          _buildControlsRow(),
          _buildFilterChips(),
          _buildResultsBar(),
          Expanded(child: filteredStations.isEmpty ? _buildEmptyState() : _buildList()),
        ]),
      ),
    );
  }

  // ── Shared gradient header ─────────────────────────────────────────────────
  Widget _buildHeaderGradient({required bool scanning}) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_darkBlue, _primaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Location row
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(children: [
            const Icon(Icons.location_on_rounded, color: Color(0xFF90CAF9), size: 14),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                scanning ? 'Detecting location...' : (currentAddressShort ?? 'Current location'),
                style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!scanning)
              GestureDetector(
                onTap: () async {
                  _startAnimations();
                  setState(() => isLoading = true);
                  await _getCurrentLocation();
                  await _loadNearbyStations();
                  _stopAnimations();
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _white(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 14),
                ),
              ),
          ]),
        ),
        // Title + stat pills
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Nearby Stations',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
              const SizedBox(height: 3),
              Text(
                scanning ? 'Fetching up to 60 stations...' : '${allStations.length} stations within ${SEARCH_RADIUS_KM.toInt()} km',
                style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 12),
              ),
            ])),
            if (!scanning) ...[
              _pillStat('$_openCount', 'Open', _accentGreen),
              const SizedBox(width: 8),
              _pillStat('${allStations.length}', 'Total', Colors.white),
            ],
          ]),
        ),
        // Vehicle card
        if (!scanning) ...[
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: _buildVehicleCard(),
          ),
        ] else
          const SizedBox(height: 20),
      ]),
    );
  }

  Widget _pillStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _white(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(color: Color(0xFF90CAF9), fontSize: 10)),
      ]),
    );
  }

  // ── Vehicle card (in header) ───────────────────────────────────────────────
  Widget _buildVehicleCard() {
    if (userVehicles.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: _white(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _white(0.2)),
        ),
        child: const Row(children: [
          Icon(Icons.electric_car_rounded, color: Color(0xFF90CAF9), size: 16),
          SizedBox(width: 10),
          Expanded(child: Text('No vehicles saved — add one in Profile', style: TextStyle(color: Color(0xFF90CAF9), fontSize: 12))),
        ]),
      );
    }
    return GestureDetector(
      onTap: _showVehicleBottomSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: _black(0.12), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.electric_car_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              selectedVehicle != null
                  ? '${selectedVehicle!.brand} ${selectedVehicle!.model}'
                  : 'Select a vehicle',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _textDark),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            if (selectedVehicle != null)
              Text(selectedVehicle!.chargingPortType,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF78909C))),
          ])),
          if (selectedVehicle != null && _recommendedCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: _green(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('$_recommendedCount match${_recommendedCount == 1 ? '' : 'es'}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _accentGreen)),
            ),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF90A4AE), size: 18),
        ]),
      ),
    );
  }

  // ── Search bar row ─────────────────────────────────────────────────────────
  Widget _buildControlsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE0E6F0)),
          boxShadow: [BoxShadow(color: _black(0.05), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: TextField(
          controller: searchController,
          onChanged: _searchStations,
          style: const TextStyle(fontSize: 14, color: _textDark),
          decoration: InputDecoration(
            hintText: 'Search stations or areas...',
            hintStyle: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFB0BEC5), size: 19),
            suffixIcon: searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFFB0BEC5), size: 17),
                    onPressed: () { searchController.clear(); _searchStations(''); })
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    );
  }

  // ── Filter chips ──────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _chip('All', 'All Types', allStations.length, null, _primaryBlue, selectedFilter == 'All Types'),
            const SizedBox(width: 8),
            _chip('Open Now', 'Available Now', _openCount, Icons.circle, _accentGreen, selectedFilter == 'Available Now'),
            const SizedBox(width: 8),
            _chip('Top Rated ★4+', 'Top Rated', _topRatedCount, null, const Color(0xFFE65100), selectedFilter == 'Top Rated'),
            if (selectedVehicle != null) ...[
              const SizedBox(width: 8),
              _chip('For My EV', 'Recommended', _recommendedCount, Icons.verified_rounded, _primaryBlue, selectedFilter == 'Recommended'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String key, int count, IconData? icon, Color color, bool selected) {
    return GestureDetector(
      onTap: () => _applyFilter(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : const Color(0xFFDDE3EE), width: 1.2),
          boxShadow: selected ? [BoxShadow(color: Color.fromRGBO(color.red, color.green, color.blue, 0.25), blurRadius: 6, offset: const Offset(0, 2))] : [],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: selected ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(label, style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF546E7A),
            fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: selected ? _white(0.22) : const Color(0xFFF0F4FB),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.bold,
              color: selected ? Colors.white : const Color(0xFF78909C),
            )),
          ),
        ]),
      ),
    );
  }

  // ── Results bar ───────────────────────────────────────────────────────────
  Widget _buildResultsBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Row(children: [
        Text(
          '${filteredStations.length} station${filteredStations.length != 1 ? 's' : ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE), fontWeight: FontWeight.w500),
        ),
        if (selectedFilter != 'All Types' || searchController.text.isNotEmpty) ...[
          const Spacer(),
          GestureDetector(
            onTap: () { searchController.clear(); _applyFilter('All Types'); },
            child: Row(children: const [
              Icon(Icons.close_rounded, size: 13, color: Color(0xFF90A4AE)),
              SizedBox(width: 3),
              Text('Clear filters', style: TextStyle(fontSize: 12, color: Color(0xFF78909C), fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
      ]),
    );
  }

  // ── List ───────────────────────────────────────────────────────────────────
  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: filteredStations.length,
      itemBuilder: (_, i) => _buildStationCard(station: filteredStations[i], index: i),
    );
  }

  // ── Station card — redesigned ──────────────────────────────────────────────
  Widget _buildStationCard({required Map<String, dynamic> station, required int index}) {
    final name = station['name'] as String;
    final location = station['vicinity'] as String;
    final dist = (station['distance'] as double);
    final distStr = dist < 1 ? '${(dist * 1000).toInt()} m' : '${dist.toStringAsFixed(1)} km';
    final rating = station['rating'] as double;
    final totalRatings = station['userRatingsTotal'] as int? ?? 0;
    final isOpen = station['isOpen'] as bool? ?? false;
    final isRec = _isRecommendedForVehicle(station);

    return GestureDetector(
      onTap: () => _showStationDetailsModal(station),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRec ? _green(0.35) : const Color(0xFFE8EDF5),
            width: isRec ? 1.5 : 1,
          ),
          boxShadow: [BoxShadow(color: _black(0.06), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Top recommended banner
          if (isRec)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: _green(0.07),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.verified_rounded, color: _accentGreen, size: 12),
                const SizedBox(width: 5),
                Text(
                  selectedVehicle != null
                      ? 'Best match for ${selectedVehicle!.brand} ${selectedVehicle!.model}'
                      : 'Recommended for your EV',
                  style: const TextStyle(color: _accentGreen, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ]),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // Icon
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: isRec ? _green(0.1) : const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.ev_station_rounded,
                    color: isRec ? _accentGreen : Colors.white, size: 21),
              ),
              const SizedBox(width: 12),

              // Name + address
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_rounded, size: 12, color: Color(0xFFB0BEC5)),
                  const SizedBox(width: 3),
                  Expanded(child: Text(location,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE)),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
                const SizedBox(height: 10),
                // Bottom row: status + rating + distance
                Row(children: [
                  // Status pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isOpen ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          color: isOpen ? const Color(0xFF43A047) : const Color(0xFFE53935),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOpen ? 'Open' : 'Closed',
                        style: TextStyle(
                          color: isOpen ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          fontSize: 11, fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]),
                  ),
                  if (rating > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 13),
                    const SizedBox(width: 2),
                    Text(rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _textDark)),
                    if (totalRatings > 0)
                      Text(' ($totalRatings)', style: const TextStyle(fontSize: 11, color: Color(0xFFB0BEC5))),
                  ],
                ]),
              ])),

              // Distance + arrow
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: _blue(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(distStr,
                      style: const TextStyle(color: _primaryBlue, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(height: 22),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFCDD4E0), size: 18),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    String title = 'No stations found';
    String sub = 'Try adjusting your filters';
    IconData icon = Icons.ev_station_outlined;
    if (selectedFilter == 'Available Now') { title = 'No open stations'; sub = 'All nearby stations may be closed'; icon = Icons.access_time_rounded; }
    else if (selectedFilter == 'Recommended') { title = 'No matching stations'; sub = 'None matched for ${selectedVehicle?.brand ?? 'your EV'}'; icon = Icons.electric_car_rounded; }
    else if (selectedFilter == 'Top Rated') { title = 'No 4★+ stations'; sub = 'No highly rated stations nearby'; icon = Icons.star_outline_rounded; }
    else if (searchController.text.isNotEmpty) { title = 'No results'; sub = 'Try a different search term'; icon = Icons.search_off_rounded; }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(color: Color(0xFFF0F4FB), shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: const Color(0xFFCDD4E0)),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF546E7A), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(sub, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF90A4AE))),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () { searchController.clear(); _applyFilter('All Types'); },
            style: TextButton.styleFrom(
              foregroundColor: _primaryBlue,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: _blue(0.3))),
            ),
            child: const Text('Show all stations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  // ── Vehicle bottom sheet ───────────────────────────────────────────────────
  void _showVehicleBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: const Color(0xFFDDE3EE), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: _blue(0.08), borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.electric_car_rounded, color: _primaryBlue, size: 16),
              ),
              const SizedBox(width: 10),
              const Text('Select Vehicle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _textDark)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF0F4FB)),
          ...userVehicles.map((vehicle) {
            final isSel = selectedVehicle?.id == vehicle.id;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSel ? const Color(0xFF1A1A2E) : const Color(0xFFF0F4FB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.electric_car_rounded, color: isSel ? Colors.white : _primaryBlue, size: 16),
              ),
              title: Text('${vehicle.brand} ${vehicle.model}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _textDark)),
              subtitle: Text(vehicle.chargingPortType,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF90A4AE))),
              trailing: isSel
                  ? Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: _green(0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, color: _accentGreen, size: 14))
                  : null,
              onTap: () { Navigator.pop(ctx); _fetchStationsForVehicle(vehicle); },
            );
          }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Station details modal ──────────────────────────────────────────────────
  void _showStationDetailsModal(Map<String, dynamic> station) {
    final dist = (station['distance'] as double);
    final distStr = dist < 1 ? '${(dist * 1000).toInt()} m' : '${dist.toStringAsFixed(1)} km';
    final rating = station['rating']?.toDouble() ?? 0.0;
    final totalRatings = station['userRatingsTotal'] ?? 0;
    final isOpen = station['isOpen'] ?? false;
    final name = station['name'] ?? 'Unknown';
    final location = station['vicinity'] ?? 'Unknown';
    final lat = station['lat'] as double;
    final lng = station['lng'] as double;
    final isRec = _isRecommendedForVehicle(station);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: _black(0.14), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Gradient header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_darkBlue, _primaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (isRec)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _green(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _green(0.4)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified_rounded, color: _accentGreen, size: 12),
                    SizedBox(width: 4),
                    Text('Recommended for your vehicle', style: TextStyle(color: _accentGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                ),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _white(0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.ev_station_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.location_on_rounded, color: _white(0.6), size: 12),
                    const SizedBox(width: 3),
                    Text('$distStr away', style: TextStyle(color: _white(0.7), fontSize: 12)),
                  ]),
                ])),
              ]),
            ]),
          ),

          // Details
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                // Open/closed
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOpen ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isOpen ? const Color(0xFFA5D6A7) : const Color(0xFFEF9A9A)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6,
                        decoration: BoxDecoration(
                          color: isOpen ? const Color(0xFF43A047) : const Color(0xFFE53935),
                          shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text(isOpen ? 'Open Now' : 'Closed',
                        style: TextStyle(
                          color: isOpen ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                          fontSize: 12, fontWeight: FontWeight.w600,
                        )),
                  ]),
                ),
                if (rating > 0) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                  const SizedBox(width: 3),
                  Text(rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _textDark)),
                  Text(' ($totalRatings)', style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE))),
                ],
              ]),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.place_rounded, color: Color(0xFFB0BEC5), size: 14),
                const SizedBox(width: 7),
                Expanded(child: Text(location,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF546E7A), height: 1.4))),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => GoogleNavScreen(
                        destinationLat: lat, destinationLng: lng,
                        destinationName: name, destinationAddress: location,
                      ),
                    ));
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 16),
                  label: const Text('Start Navigation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}