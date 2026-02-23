import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:charge_iq_app/screens/google_nav_screen.dart';

class NavigationScreen extends StatefulWidget {
  final String startLocation;
  final String destination;
  final List<dynamic> routeSegments;
  final String? destinationName;

  const NavigationScreen({
    super.key,
    required this.startLocation,
    required this.destination,
    required this.routeSegments,
    this.destinationName,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with TickerProviderStateMixin {
  final String _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<Map<String, dynamic>> _steps = [];
  String _totalDistance = '';
  String _totalDuration = '';
  bool _isLoading = true;
  bool _isNavigating = false;
  bool _isSheetExpanded = false;
  bool _hasError = false;
  int _currentStepIndex = 0;

  LatLng? _startLatLng;
  LatLng? _destinationLatLng;
  List<LatLng> _waypoints = [];
  List<String> _waypointNames = [];

  String get _displayDestinationName {
    final customName = widget.destinationName;
    if (customName != null && customName.trim().isNotEmpty) {
      return customName.trim();
    }
    return widget.destination;
  }

  // Animation controllers
  late AnimationController _bottomSheetController;
  late Animation<double> _bottomSheetAnimation;
  late AnimationController _fabController;
  late Animation<double> _fabSlide;

  StreamSubscription<Position>? _locationSubscription;

  @override
  void initState() {
    super.initState();

    _bottomSheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _bottomSheetAnimation = CurvedAnimation(
      parent: _bottomSheetController,
      curve: Curves.easeOutCubic,
    );

    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fabSlide = Tween<double>(begin: 80.0, end: 0.0).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeOutBack),
    );

    _initRoute();
  }

  @override
  void dispose() {
    _bottomSheetController.dispose();
    _fabController.dispose();
    _locationSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _initRoute() async {
    try {
      // Geocode start location
      _startLatLng = await _geocode(widget.startLocation);

      // Geocode destination
      _destinationLatLng = await _geocode(widget.destination);

      // Collect waypoints from charging stops
      for (var seg in widget.routeSegments) {
        if (seg['segment_type'] == 'charge_meal' &&
            seg['address'] != null &&
            seg['address'].toString().isNotEmpty) {
          final wp = await _geocode(seg['address']);
          if (wp != null) {
            _waypoints.add(wp);
            _waypointNames.add(
              (seg['location_name'] as String?)?.trim().isNotEmpty == true
                  ? seg['location_name'] as String
                  : 'Stop ${_waypoints.length}',
            );
          }
        }
      }

      if (_startLatLng == null || _destinationLatLng == null) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
        return;
      }

      // Get directions with waypoints
      await _fetchDirections();
    } catch (e) {
      debugPrint('Navigation init error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<LatLng?> _geocode(String address) async {
    // Check if it's already lat,lng
    if (address.contains(',')) {
      final parts = address.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    }

    // Check if it's "Current Location"
    if (address.toLowerCase().contains('current location')) {
      try {
        Position pos = await Geolocator.getCurrentPosition();
        return LatLng(pos.latitude, pos.longitude);
      } catch (_) {
        return null;
      }
    }

    // Geocode using Google API
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeComponent(address)}'
        '&key=$_apiKey',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
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

  Future<void> _fetchDirections() async {
    String waypointsStr = '';
    if (_waypoints.isNotEmpty) {
      final wpParts = _waypoints
          .map((wp) => '${wp.latitude},${wp.longitude}')
          .join('|');
      waypointsStr = '&waypoints=$wpParts';
    }

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${_startLatLng!.latitude},${_startLatLng!.longitude}'
      '&destination=${_destinationLatLng!.latitude},${_destinationLatLng!.longitude}'
      '$waypointsStr'
      '&mode=driving'
      '&units=metric'
      '&key=$_apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final polylinePoints = route['overview_polyline']['points'];
          final legs = route['legs'] as List;

          // Calculate totals
          int totalDistMeters = 0;
          int totalDurSeconds = 0;
          List<Map<String, dynamic>> allSteps = [];

          for (var leg in legs) {
            totalDistMeters += (leg['distance']['value'] as int);
            totalDurSeconds += (leg['duration']['value'] as int);
            for (var step in leg['steps']) {
              allSteps.add({
                'instruction': _stripHtmlTags(
                  step['html_instructions']?.toString() ?? '',
                ),
                'distance': step['distance']['text'],
                'duration': step['duration']['text'],
                'maneuver': step['maneuver'] ?? '',
                'start_location': LatLng(
                  step['start_location']['lat'],
                  step['start_location']['lng'],
                ),
                'end_location': LatLng(
                  step['end_location']['lat'],
                  step['end_location']['lng'],
                ),
              });
            }
          }

          final points = _decodePolyline(polylinePoints);

          if (mounted) {
            setState(() {
              _steps = allSteps;
              _totalDistance = _formatDistance(totalDistMeters);
              _totalDuration = _formatDuration(totalDurSeconds);

              // Build polyline
              _polylines = {
                Polyline(
                  polylineId: const PolylineId('nav_route'),
                  points: points,
                  color: const Color(0xFF4285F4),
                  width: 6,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                ),
              };

              // Build markers
              _markers = {};

              // Start marker
              _markers.add(
                Marker(
                  markerId: const MarkerId('start'),
                  position: _startLatLng!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Start',
                    snippet: widget.startLocation,
                  ),
                ),
              );

              // Destination marker
              _markers.add(
                Marker(
                  markerId: const MarkerId('destination'),
                  position: _destinationLatLng!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Destination',
                    snippet: widget.destination,
                  ),
                ),
              );

              // Waypoint markers (charging stops)
              final chargeMealSegs = widget.routeSegments
                  .where((s) => s['segment_type'] == 'charge_meal')
                  .toList();
              for (int i = 0; i < _waypoints.length; i++) {
                final seg = i < chargeMealSegs.length ? chargeMealSegs[i] : {};
                _markers.add(
                  Marker(
                    markerId: MarkerId('waypoint_$i'),
                    position: _waypoints[i],
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange,
                    ),
                    infoWindow: InfoWindow(
                      title: (seg['location_name'] as String?)?.trim().isNotEmpty == true
                          ? seg['location_name'] as String
                          : 'Charging Stop ${i + 1}',
                      snippet: seg['charging_time'] ?? '',
                    ),
                  ),
                );
              }

              _isLoading = false;
            });

            // Animate to fit route
            _fitBounds(points);

            // Trigger entrance animations with delays
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _bottomSheetController.forward();
            });
            Future.delayed(const Duration(milliseconds: 400), () {
              if (mounted) _fabController.forward();
            });
          }
        } else {
          setState(() {
            _hasError = true;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Directions error: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _fitBounds(List<LatLng> points) {
    if (points.isEmpty || _mapController == null) return;

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

    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  String _formatDistance(int meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
    return '$meters m';
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes} min';
  }

  String _stripHtmlTags(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

  IconData _getManeuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-slight-left':
        return Icons.turn_slight_left;
      case 'turn-slight-right':
        return Icons.turn_slight_right;
      case 'turn-sharp-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
        return Icons.u_turn_left;
      case 'uturn-right':
        return Icons.u_turn_right;
      case 'roundabout-left':
      case 'roundabout-right':
        return Icons.roundabout_left;
      case 'merge':
        return Icons.merge;
      case 'fork-left':
        return Icons.fork_left;
      case 'fork-right':
        return Icons.fork_right;
      case 'ramp-left':
        return Icons.ramp_left;
      case 'ramp-right':
        return Icons.ramp_right;
      case 'straight':
        return Icons.straight;
      default:
        return Icons.arrow_upward;
    }
  }

  void _stopNavigation() {
    setState(() {
      _isNavigating = false;
    });
    _locationSubscription?.cancel();
    _locationSubscription = null;

    // Reset camera
    if (_polylines.isNotEmpty) {
      _fitBounds(_polylines.first.points);
    }
  }

  void _goToNextStep() {
    if (_currentStepIndex < _steps.length - 1) {
      setState(() {
        _currentStepIndex++;
      });
      final step = _steps[_currentStepIndex];
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: step['start_location'], zoom: 17, tilt: 45),
        ),
      );
    }
  }

  void _goToPreviousStep() {
    if (_currentStepIndex > 0) {
      setState(() {
        _currentStepIndex--;
      });
      final step = _steps[_currentStepIndex];
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: step['start_location'], zoom: 17, tilt: 45),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
          // Full-screen Google Map
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _startLatLng ?? const LatLng(20.5937, 78.9629),
              zoom: 5,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              // Set dark-ish style for premium feel
              controller.setMapStyle(_mapStyle);
            },
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
          ),

          // Loading overlay
          if (_isLoading) _buildLoadingOverlay(),

          // Error overlay
          if (_hasError && !_isLoading) _buildErrorOverlay(),

          // Top bar (back + info)
          if (!_isLoading && !_hasError) _buildTopBar(),

          // Navigation step card (when navigating)
          if (_isNavigating && _steps.isNotEmpty) _buildNavigationStepCard(),

          // Bottom panel with route info + start button
          if (!_isLoading && !_hasError && !_isNavigating) _buildBottomPanel(),

          // Navigation controls (when navigating)
          if (_isNavigating) _buildNavigationControls(),

          // Recenter FAB
          if (!_isLoading && !_hasError)
            Builder(
              builder: (ctx) {
                final screenH = MediaQuery.of(ctx).size.height;
                final safeBottom = MediaQuery.of(ctx).padding.bottom;
                // Collapsed panel ≈ handle(26) + stops label(36) + stops scroll(135) + hint(46) + button(86) + safeArea
                final collapsedPanelH = 26.0 + 36.0 + 135.0 + 46.0 + 86.0 + safeBottom;
                final fabBottom = _isNavigating
                    ? 180.0
                    : (_isSheetExpanded
                        ? screenH * 0.65 + 12
                        : collapsedPanelH + 8);
                return AnimatedBuilder(
                  animation: _fabSlide,
                  builder: (context, child) {
                    return Positioned(
                      right: 16,
                      bottom: fabBottom,
                      child: Transform.translate(
                        offset: Offset(_fabSlide.value, 0),
                        child: child,
                      ),
                    );
                  },
                  child: FloatingActionButton.small(
                    heroTag: 'recenter',
                    onPressed: () {
                      if (_polylines.isNotEmpty) {
                        _fitBounds(_polylines.first.points);
                      }
                    },
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.my_location, color: Color(0xFF4285F4)),
                  ),
                );
              },
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(
                    width: 50,
                    height: 50,
                    child: CircularProgressIndicator(
                      color: Color(0xFF4285F4),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Loading Route...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wrong_location_outlined,
                size: 60,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Route Not Found',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Unable to find directions.\nPlease check the locations and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: Row(
        children: [
          // Back button
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (_isNavigating) {
                  _stopNavigation();
                } else {
                  Navigator.pop(context);
                }
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isNavigating ? Icons.close : Icons.arrow_back,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Route info card
          Expanded(
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _displayDestinationName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    if (_totalDistance.isNotEmpty || _totalDuration.isNotEmpty)
                      Row(
                        children: [
                          if (_totalDistance.isNotEmpty) ...[
                            const Icon(
                              Icons.route_rounded,
                              size: 16,
                              color: Color(0xFF4285F4),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _totalDistance,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          if (_totalDistance.isNotEmpty &&
                              _totalDuration.isNotEmpty)
                            Text(
                              '  •  ',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                            ),
                          if (_totalDuration.isNotEmpty) ...[
                            const Icon(
                              Icons.access_time_filled_rounded,
                              size: 16,
                              color: Color(0xFFEA4335),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _totalDuration,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4285F4),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationStepCard() {
    if (_currentStepIndex >= _steps.length) return const SizedBox();
    final step = _steps[_currentStepIndex];

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 12,
      right: 12,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.5),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: Material(
          key: ValueKey(_currentStepIndex),
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4285F4), Color(0xFF3367D6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getManeuverIcon(step['maneuver'] ?? ''),
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step['instruction'] ?? 'Continue',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${step['distance']}  •  ${step['duration']}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 20,
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

  Widget _buildNavigationControls() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Previous step
              IconButton(
                onPressed: _currentStepIndex > 0 ? _goToPreviousStep : null,
                icon: Icon(
                  Icons.arrow_back_ios_rounded,
                  color: _currentStepIndex > 0
                      ? const Color(0xFF4285F4)
                      : Colors.grey[300],
                ),
              ),
              // Step counter
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Step ${_currentStepIndex + 1} of ${_steps.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 120,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentStepIndex + 1) / _steps.length,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF4285F4),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),
                ],
              ),
              // Stop button
              Container(
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: _stopNavigation,
                  icon: const Icon(
                    Icons.stop_rounded,
                    color: Colors.red,
                    size: 28,
                  ),
                ),
              ),
              // Next step
              IconButton(
                onPressed: _currentStepIndex < _steps.length - 1
                    ? _goToNextStep
                    : null,
                icon: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: _currentStepIndex < _steps.length - 1
                      ? const Color(0xFF4285F4)
                      : Colors.grey[300],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    final double expandedHeight = MediaQuery.of(context).size.height * 0.68;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(_bottomSheetAnimation),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          height: _isSheetExpanded ? expandedHeight : null,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 30,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize:
                  _isSheetExpanded ? MainAxisSize.max : MainAxisSize.min,
              children: [
                // ── Drag handle ──────────────────────────────────────────
                GestureDetector(
                  onTap: () =>
                      setState(() => _isSheetExpanded = !_isSheetExpanded),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 6),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Expanded: full directions list header ─────────────────
                if (_isSheetExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                    child: Row(
                      children: [
                        // Back to stops button
                        GestureDetector(
                          onTap: () =>
                              setState(() => _isSheetExpanded = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF34A853).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF34A853).withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 13,
                                  color: const Color(0xFF34A853),
                                ),
                                const SizedBox(width: 5),
                                const Text(
                                  'Stops',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF34A853),
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4285F4).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.format_list_numbered_rounded,
                            size: 16,
                            color: Color(0xFF4285F4),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Turn-by-Turn  ·  ${_steps.length} steps',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A2E),
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Charging stops ────────────────────────────────────────
                if (!_isSheetExpanded) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.bolt_rounded,
                            size: 13, color: Color(0xFF34A853)),
                        const SizedBox(width: 5),
                        Text(
                          'Charging Stops',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[500],
                            letterSpacing: 0.5,
                          ),
                        ),
                        if (_waypointNames.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF34A853).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${_waypointNames.length}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF34A853),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _waypointNames.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF34A853).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: const Color(0xFF34A853)
                                      .withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle_outline_rounded,
                                    size: 18,
                                    color: Colors.grey[400]),
                                const SizedBox(width: 10),
                                Text(
                                  'No charging stops on this route',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[500],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SizedBox(
                          height: 135,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.fromLTRB(18, 0, 18, 0),
                            itemCount: _waypointNames.length,
                            itemBuilder: (ctx, i) => Padding(
                              padding: EdgeInsets.only(
                                  right:
                                      i < _waypointNames.length - 1 ? 10 : 0),
                              child: _buildStopChip(
                                _waypointNames[i],
                                i + 1,
                                160,
                                _getWaypointChargeTime(i),
                              ),
                            ),
                          ),
                        ),
                  const SizedBox(height: 12),
                ],

                // ── Expanded directions list ──────────────────────────────
                if (_isSheetExpanded) Expanded(child: _buildFullStepsList()),

                // ── Expand hint bar (collapsed only) ─────────────────────
                if (!_isSheetExpanded)
                  GestureDetector(
                    onTap: () =>
                        setState(() => _isSheetExpanded = !_isSheetExpanded),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                      padding: const EdgeInsets.symmetric(
                          vertical: 11, horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4285F4).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF4285F4).withOpacity(0.15),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.format_list_bulleted_rounded,
                            size: 15,
                            color: const Color(0xFF4285F4).withOpacity(0.8),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Tap to view turn-by-turn directions',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color:
                                  const Color(0xFF4285F4).withOpacity(0.85),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 16,
                            color: const Color(0xFF4285F4).withOpacity(0.7),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Start Navigation button ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_destinationLatLng == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GoogleNavScreen(
                              destinationLat: _destinationLatLng!.latitude,
                              destinationLng: _destinationLatLng!.longitude,
                              destinationName: _displayDestinationName,
                              destinationAddress: widget.destination,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.navigation_rounded, size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Start Navigation',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildPillBadge(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.withOpacity(0.8)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  String? _getWaypointChargeTime(int index) {
    final chargeMealSegs = widget.routeSegments
        .where((s) => s['segment_type'] == 'charge_meal')
        .toList();
    if (index < chargeMealSegs.length) {
      final t = chargeMealSegs[index]['charging_time'] as String?;
      return (t != null && t.trim().isNotEmpty) ? t.trim() : null;
    }
    return null;
  }

  Widget _buildStopChip(
      String name, int number, double width, String? chargeTime) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF34A853).withOpacity(0.08),
            const Color(0xFF34A853).withOpacity(0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF34A853).withOpacity(0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF34A853),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.bolt_rounded,
                  size: 14, color: Color(0xFF34A853)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A2E),
              height: 1.3,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          if (chargeTime != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 11, color: Colors.grey[500]),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    chargeTime,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Full vertical turn-by-turn step list with timeline connectors
  Widget _buildFullStepsList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      itemCount: _steps.length,
      itemBuilder: (context, index) {
        final step = _steps[index];
        final isFirst = index == 0;
        final isLast = index == _steps.length - 1;
        final Color nodeColor = isFirst
            ? const Color(0xFF34A853)
            : isLast
                ? const Color(0xFFEA4335)
                : const Color(0xFF4285F4);

        return GestureDetector(
          onTap: () {
            final loc = step['start_location'] as LatLng?;
            if (loc != null) {
              _mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: loc, zoom: 16, tilt: 30),
                ),
              );
            }
          },
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline column
                SizedBox(
                  width: 48,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Connector line above node
                      if (!isFirst)
                        Container(
                          width: 2,
                          height: 10,
                          color: const Color(0xFF4285F4).withOpacity(0.25),
                        ),
                      // Node icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [nodeColor, nodeColor.withOpacity(0.75)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: nodeColor.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          _getManeuverIcon(step['maneuver'] ?? ''),
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      // Connector line below node
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            margin: const EdgeInsets.only(top: 4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF4285F4).withOpacity(0.35),
                                  const Color(0xFF4285F4).withOpacity(0.10),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: 16),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Step content
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(bottom: isLast ? 8 : 14),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FE),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: nodeColor.withOpacity(0.15),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step['instruction'] ?? 'Continue',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A2E),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.straighten_rounded,
                              size: 13,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              step['distance'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 3),
                            Text(
                              step['duration'] ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
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
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepPreviewCard(
      Map<String, dynamic> step, int index, double cardWidth) {
    return GestureDetector(
      onTap: () {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: step['start_location'], zoom: 16, tilt: 30),
          ),
        );
      },
      child: Container(
        width: cardWidth,
        margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF4285F4).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _getManeuverIcon(step['maneuver'] ?? ''),
                size: 18,
                color: const Color(0xFF4285F4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              step['distance'] ?? '',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10,
                color: Color(0xFF4285F4),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              step['instruction'] ?? '',
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
                height: 1.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // Subtle map style for a premium look
  static const String _mapStyle = '''
[
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{"visibility": "off"}]
  },
  {
    "featureType": "transit",
    "elementType": "labels",
    "stylers": [{"visibility": "off"}]
  }
]
''';
}
