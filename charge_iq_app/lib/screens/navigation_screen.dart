import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';

class NavigationScreen extends StatefulWidget {
  final String startLocation;
  final String destination;
  final List<dynamic> routeSegments;

  const NavigationScreen({
    super.key,
    required this.startLocation,
    required this.destination,
    required this.routeSegments,
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
  bool _hasError = false;
  int _currentStepIndex = 0;

  LatLng? _startLatLng;
  LatLng? _destinationLatLng;
  List<LatLng> _waypoints = [];

  // Animation controllers
  late AnimationController _bottomSheetController;
  late Animation<double> _bottomSheetAnimation;
  late AnimationController _startButtonController;
  late Animation<double> _startButtonScale;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
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

    _startButtonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _startButtonScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _startButtonController, curve: Curves.elasticOut),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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
    _startButtonController.dispose();
    _pulseController.dispose();
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
              for (int i = 0; i < _waypoints.length; i++) {
                final seg = widget.routeSegments.firstWhere(
                  (s) => s['segment_type'] == 'charge_meal',
                  orElse: () => {},
                );
                _markers.add(
                  Marker(
                    markerId: MarkerId('waypoint_$i'),
                    position: _waypoints[i],
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange,
                    ),
                    infoWindow: InfoWindow(
                      title: seg['location_name'] ?? 'Charging Stop ${i + 1}',
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
            Future.delayed(const Duration(milliseconds: 600), () {
              if (mounted) _startButtonController.forward();
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

  void _startNavigation() {
    setState(() {
      _isNavigating = true;
      _currentStepIndex = 0;
    });

    // Zoom into the first step
    if (_steps.isNotEmpty) {
      final firstStep = _steps[0];
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: firstStep['start_location'],
            zoom: 17,
            tilt: 45,
            bearing: 0,
          ),
        ),
      );
    }

    // Start live location tracking
    _startLocationTracking();
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

  void _startLocationTracking() {
    _locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 10,
          ),
        ).listen((Position position) {
          if (!mounted) return;

          final newPos = LatLng(position.latitude, position.longitude);
          setState(() {
            // Update current location marker
            _markers.removeWhere((m) => m.markerId.value == 'current_nav');
            _markers.add(
              Marker(
                markerId: const MarkerId('current_nav'),
                position: newPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueAzure,
                ),
                infoWindow: const InfoWindow(title: 'You'),
                anchor: const Offset(0.5, 0.5),
              ),
            );
          });

          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: newPos,
                zoom: 17,
                tilt: 45,
                bearing: position.heading,
              ),
            ),
          );
        });
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
    return Scaffold(
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
            AnimatedBuilder(
              animation: _fabSlide,
              builder: (context, child) {
                return Positioned(
                  right: 16,
                  bottom: _isNavigating ? 180 : 340,
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
            ),
        ],
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
                  Text(
                    'Finding the best path to\n${widget.destination}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
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
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.destination,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _totalDistance,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_totalDistance.isNotEmpty &&
                            _totalDuration.isNotEmpty)
                          Text(
                            '  •  ',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                          ),
                        Text(
                          _totalDuration,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4285F4),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(_bottomSheetAnimation),
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
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Route summary
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      _buildInfoChip(
                        Icons.route,
                        _totalDistance,
                        const Color(0xFF4285F4),
                      ),
                      const SizedBox(width: 10),
                      _buildInfoChip(
                        Icons.access_time_filled,
                        _totalDuration,
                        const Color(0xFFEA4335),
                      ),
                      const SizedBox(width: 10),
                      _buildInfoChip(
                        Icons.ev_station,
                        '${_waypoints.length} Stops',
                        const Color(0xFF34A853),
                      ),
                    ],
                  ),
                ),

                // Turn-by-turn steps preview
                if (_steps.isNotEmpty)
                  Container(
                    height: 120,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _steps.length > 5 ? 5 : _steps.length,
                      itemBuilder: (context, index) {
                        final step = _steps[index];
                        return _buildStepPreviewCard(step, index);
                      },
                    ),
                  ),

                // Start button
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: ScaleTransition(
                    scale: _startButtonScale,
                    child: AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: child,
                        );
                      },
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _startNavigation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(
                              0xFF4285F4,
                            ).withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.navigation_rounded, size: 24),
                              SizedBox(width: 10),
                              Text(
                                'Start Navigation',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildStepPreviewCard(Map<String, dynamic> step, int index) {
    return GestureDetector(
      onTap: () {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: step['start_location'], zoom: 16, tilt: 30),
          ),
        );
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 10, top: 8, bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F9FE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4285F4).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getManeuverIcon(step['maneuver'] ?? ''),
                    size: 16,
                    color: const Color(0xFF4285F4),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  step['distance'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF4285F4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                step['instruction'] ?? 'Continue',
                style: const TextStyle(fontSize: 11, color: Color(0xFF444444)),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
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
