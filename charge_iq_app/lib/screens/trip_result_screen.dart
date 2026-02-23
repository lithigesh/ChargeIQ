import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import '../models/vehicle.dart';
import '../services/gemini_service.dart';
import '../services/trip_service.dart';
import '../services/directions_service.dart';
import '../services/vehicle_service.dart';
import 'main_screen.dart';

class TripResultScreen extends StatefulWidget {
  final String startLocation;
  final String destination;
  final String vehicleId;
  final String evRange;
  final String vehicleType;
  final bool useCurrentLocation;
  final String? preLoadedPlan;
  final String? tripId;
  final List<Vehicle> vehicles;
  final String startTime;
  final double? startLat;
  final double? startLng;
  final double? destLat;
  final double? destLng;
  final bool includeRestaurants;

  const TripResultScreen({
    super.key,
    required this.startLocation,
    required this.destination,
    required this.vehicleId,
    required this.evRange,
    required this.vehicleType,
    required this.useCurrentLocation,
    this.preLoadedPlan,
    this.tripId,
    this.vehicles = const [],
    this.startTime = '09:00',
    this.startLat,
    this.startLng,
    this.destLat,
    this.destLng,
    this.includeRestaurants = false,
  });

  @override
  State<TripResultScreen> createState() => _TripResultScreenState();
}

class _TripResultScreenState extends State<TripResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _directionsBtnController;
  late Animation<double> _directionsBtnAnimation;
  final GeminiService _geminiService = GeminiService();
  final TripService _tripService = TripService();
  final DirectionsService _directionsService = DirectionsService();
  final VehicleService _vehicleService = VehicleService();

  String? _generatedPlan;
  bool _isLoading = true;
  String? _error;
  String? _realTimeDistance;
  String? _realTimeDuration;
  bool _isSaved = false;
  Vehicle? _tripVehicle;
  bool _isVehicleExpanded = false;

  @override
  void initState() {
    super.initState();
    _directionsBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _directionsBtnAnimation = CurvedAnimation(
      parent: _directionsBtnController,
      curve: Curves.easeOutBack,
    );
    _loadVehicle();
    if (widget.preLoadedPlan != null) {
      _generatedPlan = widget.preLoadedPlan;
      _isLoading = false;
      _isSaved = true;
      _directionsBtnController.forward();
    } else {
      _generatePlan();
    }
  }

  Future<void> _loadVehicle() async {
    if (widget.vehicleId.isEmpty) return;
    
    try {
      final vehicle = await _vehicleService.getVehicle(widget.vehicleId);
      if (mounted && vehicle != null) {
        setState(() {
          _tripVehicle = vehicle;
        });
      }
    } catch (e) {
      print('Error loading vehicle: $e');
    }
  }

  @override
  void dispose() {
    _directionsBtnController.dispose();
    super.dispose();
  }

  Future<void> _generatePlan() async {
    String start = widget.startLocation;

    // Use coordinates if available for more accurate routing
    if (widget.useCurrentLocation && widget.startLat != null && widget.startLng != null) {
      start = '${widget.startLat}, ${widget.startLng}';
    }

    try {
      final plan = await _geminiService.planTrip(
        startLocation: start,
        destination: widget.destination,
        vehicles: widget.vehicles,
        startTime: widget.startTime,
        evRange: widget.evRange,
        vehicleType: widget.vehicleType,
        includeRestaurants: widget.includeRestaurants,
      );

      final directions = await _directionsService.getDirections(
        widget.startLocation,
        widget.destination,
      );

      if (mounted) {
        setState(() {
          _generatedPlan = plan;
          if (directions != null) {
            _realTimeDistance = directions['distance'];
            _realTimeDuration = directions['duration'];
          }
          _isLoading = false;
        });
        _directionsBtnController.forward();
        // Auto-save the trip
        _saveTrip();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveTrip() async {
    if (_generatedPlan == null || _isSaved) return;

    setState(() {
      _isSaved = true;
    });

    try {
      String finalPlanData = _generatedPlan!;
      if (_realTimeDistance != null && _realTimeDuration != null) {
        try {
          final decodedPlan = json.decode(_generatedPlan!);
          decodedPlan['total_distance'] = _realTimeDistance;
          decodedPlan['total_duration'] = _realTimeDuration;
          finalPlanData = json.encode(decodedPlan);
        } catch (e) {
          print('Error updating plan JSON: $e');
        }
      }

      await _tripService.saveTrip(
        startLocation: widget.startLocation,
        destination: widget.destination,
        vehicleId: widget.vehicleId,
        evRange: int.tryParse(widget.evRange) ?? 300,
        vehicleType: widget.vehicleType,
        planData: finalPlanData,
        startLat: widget.startLat,
        startLng: widget.startLng,
        destLat: widget.destLat,
        destLng: widget.destLng,
      );

      print(
        'Trip saved to Firestore path: users/${_tripService.currentUserId}/trips',
      );
      // Auto-saved silently, no need to show success message
    } catch (e) {
      print('Save Trip Error: $e');
      setState(() {
        _isSaved = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save trip: $e')));
      }
    }
  }

  Future<void> _deleteTrip() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Delete"),
          content: const Text(
            "Are you sure you want to delete this trip plan?",
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      if (widget.tripId != null) {
        await _tripService.deleteTrip(widget.tripId!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip deleted successfully')),
          );
          Navigator.of(context).pop();
        }
      } else {
        // Trip was just saved this session, no ID available
        setState(() {
          _isSaved = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Trip unsaved')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String titleText = '${widget.startLocation} → ${widget.destination}';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text(titleText, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        centerTitle: true,
        actions: [
          if (!_isLoading && _generatedPlan != null && widget.tripId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deleteTrip,
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoading()
          : _error != null
          ? _buildError()
          : _buildContent(),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(color: Color(0xFF00D26A)),
          SizedBox(height: 20),
          Text(
            'Planning your optimized journey...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 10),
          Text(
            'Finding best charging stops & dining...',
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 16),
            Text(
              'Planning Failed',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _generatePlan();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    Map<String, dynamic> plan;
    try {
      String jsonStr = _generatedPlan!;
      if (jsonStr.contains('```json')) {
        jsonStr = jsonStr.replaceAll('```json', '').replaceAll('```', '');
      } else if (jsonStr.contains('```')) {
        jsonStr = jsonStr.replaceAll('```', '');
      }
      plan = json.decode(jsonStr);
    } catch (e) {
      return Center(child: Text('Error parsing plan: $e'));
    }

    final segments = plan['route_segments'] as List? ?? [];

    return Column(
      children: [
        _buildSummaryCard(plan),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: segments.length + (_tripVehicle != null ? 1 : 0),
            itemBuilder: (context, index) {
              // Show vehicle card as first item in the scrollable list
              if (index == 0 && _tripVehicle != null) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: _buildVehicleCard(),
                );
              }
              // Adjust index for route segments
              final segIndex = _tripVehicle != null ? index - 1 : index;
              final seg = segments[segIndex];
              final isLast = segIndex == segments.length - 1;
              return _buildTimelineItem(seg, isLast);
            },
          ),
        ),
      ],
    );
  }

  void _openNavigation(List<dynamic> segments) {
    // Pop back to the main screen and show route on the map
    Navigator.of(context).popUntil((route) => route.isFirst);

    // Tell the MainScreen to switch to map tab and display the route
    MainScreen.mainKey.currentState?.showRouteOnMap(
      startLocation: widget.startLocation,
      destination: widget.destination,
      routeSegments: segments,
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> plan) {
    final segments = plan['route_segments'] as List? ?? [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Stats row
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                  Icons.directions_car,
                  _realTimeDistance ??
                      _cleanText(plan['total_distance'] ?? 'N/A'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatChip(
                  Icons.timer,
                  _cleanText(_realTimeDuration ??
                      plan['total_duration'] ?? 'N/A'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Directions button
          ScaleTransition(
            scale: _directionsBtnAnimation,
            child: Material(
              elevation: 2,
              shadowColor: const Color(0xFF4285F4).withOpacity(0.3),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openNavigation(segments),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4285F4), Color(0xFF3367D6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.navigation_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'View Directions on Map',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getVehicleIcon() {
    if (_tripVehicle == null) return Icons.directions_car;
    
    switch (_tripVehicle!.vehicleType) {
      case '2 Wheeler':
        return Icons.two_wheeler;
      case '3 Wheeler':
        return Icons.electric_rickshaw;
      case 'Bus':
        return Icons.directions_bus;
      default:
        return Icons.directions_car;
    }
  }

  Widget _buildVehicleCard() {
    if (_tripVehicle == null) return const SizedBox.shrink();
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _isVehicleExpanded = !_isVehicleExpanded;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getVehicleIcon(),
                    color: Colors.black87,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_tripVehicle!.brand} ${_tripVehicle!.model}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (_tripVehicle!.variant.isNotEmpty && !_isVehicleExpanded)
                        Text(
                          _tripVehicle!.variant,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _isVehicleExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  if (_tripVehicle!.variant.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            _tripVehicle!.variant,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _buildVehicleInfoChip(
                          Icons.battery_charging_full,
                          '${_tripVehicle!.batteryCapacity.toStringAsFixed(0)} kWh',
                          'Battery',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVehicleInfoChip(
                          Icons.speed,
                          '${_tripVehicle!.maxRange.toStringAsFixed(0)} km',
                          'Range',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildVehicleInfoChip(
                          Icons.bolt,
                          '${_tripVehicle!.maxDCFastChargingPower.toStringAsFixed(0)} kW',
                          'DC Fast',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildVehicleInfoChip(
                          Icons.power,
                          _tripVehicle!.chargingPortType,
                          'Port',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              crossFadeState: _isVehicleExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleInfoChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF1565C0)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1565C0)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF1565C0),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(dynamic segment, bool isLast) {
    final type = segment['segment_type'];
    final isStop = type == 'charge_meal';

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                _buildTimelineDot(isStop),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: isStop
                  ? _buildStopCard(segment)
                  : _buildDriveInfo(segment),
            ),
          ),
          if (!isStop)
            Container(
              width: 60,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _cleanText(segment['distance']?.toString() ?? ''),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  String _cleanText(String text) {
    String clean = text.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').trim();
    // Replace standalone 'mi' or 'miles' with 'km' (but NOT 'min')
    clean = clean.replaceAll(RegExp(r'\bmiles?\b'), 'km');
    // Replace 'hours' and 'hour' with 'hr'
    clean = clean.replaceAll(RegExp(r'\bhours?\b', caseSensitive: false), 'hr');
    // Replace 'minutes' and 'minute' with 'min'
    clean = clean.replaceAll(RegExp(r'\bminutes?\b', caseSensitive: false), 'min');
    return clean;
  }

  Widget _buildTimelineDot(bool isStop) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isStop ? Colors.transparent : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isStop ? Colors.transparent : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: isStop
          ? const Icon(Icons.ev_station, size: 20, color: Color(0xFF00D26A))
          : Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
            ),
    );
  }

  Widget _buildDriveInfo(dynamic segment) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Drive to ${segment['to']}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 4),
        Text(
          _cleanText(segment['duration'] ?? ''),
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildStopCard(dynamic segment) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  segment['location_name'] ?? 'Stop',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  segment['address'] ?? '',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 16,
                      color: Color(0xFF2E7D32),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _cleanText('Est. ${segment['charging_time'] ?? 'N/A'}'),
                        style: const TextStyle(
                          color: Color(0xFF2E7D32),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (segment['restaurant_name'] != null &&
              segment['restaurant_name'].toString().isNotEmpty &&
              segment['restaurant_name'].toString().toLowerCase() != 'null')
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _getMealIcon(segment['meal_type']),
                    size: 18,
                    color: _getMealColor(segment['meal_type']),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                segment['restaurant_name'] ?? 'Dining Option',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (segment['meal_type'] != null &&
                                segment['meal_type'] != 'none')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: _getMealColor(
                                    segment['meal_type'],
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  (segment['meal_type'] as String)
                                          .substring(0, 1)
                                          .toUpperCase() +
                                      (segment['meal_type'] as String)
                                          .substring(1),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _getMealColor(segment['meal_type']),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${segment['restaurant_rating'] ?? 'N/A'}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (segment['cuisine_type'] != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• ${segment['cuisine_type']}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (segment['notes'] != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            segment['notes'],
                            style: const TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Colors.black54,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _getMealIcon(String? mealType) {
    switch (mealType) {
      case 'breakfast':
        return Icons.free_breakfast;
      case 'lunch':
        return Icons.restaurant;
      case 'dinner':
        return Icons.dinner_dining;
      case 'snack':
        return Icons.local_cafe;
      default:
        return Icons.restaurant;
    }
  }

  Color _getMealColor(String? mealType) {
    switch (mealType) {
      case 'breakfast':
        return const Color(0xFFFF9800);
      case 'lunch':
        return const Color(0xFF4CAF50);
      case 'dinner':
        return const Color(0xFF9C27B0);
      case 'snack':
        return const Color(0xFF795548);
      default:
        return Colors.orange;
    }
  }
}
