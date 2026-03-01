import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../models/vehicle.dart';
import '../services/places_service.dart';
import '../services/trip_service.dart';
import '../services/vehicle_service.dart';
import '../models/trip_plan.dart';
import 'trip_result_screen.dart';
import 'all_trips_screen.dart';

class TripPlanningScreen extends StatefulWidget {
  const TripPlanningScreen({super.key});

  @override
  State<TripPlanningScreen> createState() => _TripPlanningScreenState();
}

class _TripPlanningScreenState extends State<TripPlanningScreen> {
  // Services
  final PlacesService _placesService = PlacesService();
  final TripService _tripService = TripService();
  final VehicleService _vehicleService = VehicleService();

  // State
  bool _useCurrentLocation = true;
  String? _startLocationName;
  String? _destinationLocationName;
  double? _startLat;
  double? _startLng;
  double? _destLat;
  double? _destLng;

  // Vehicle selection
  List<Vehicle> _allVehicles = [];
  List<Vehicle> _selectedVehicles = [];
  bool _vehiclesLoading = true;

  // Start time
  TimeOfDay _startTime = TimeOfDay.now();
  bool _useCurrentTime = true;

  // Preferences
  bool _includeRestaurants = false;
  bool _isPlanning = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  void _loadVehicles() async {
    // Get the default vehicle ID first
    final defaultId = await _vehicleService.getDefaultVehicleId();

    _vehicleService.getUserVehicles().listen((vehicles) {
      if (mounted) {
        setState(() {
          _allVehicles = vehicles;
          _vehiclesLoading = false;
          // Auto-select the default vehicle, or first vehicle if no default
          if (_selectedVehicles.isEmpty && vehicles.isNotEmpty) {
            if (defaultId != null) {
              final defaultVehicle = vehicles
                  .where((v) => v.id == defaultId)
                  .toList();
              if (defaultVehicle.isNotEmpty) {
                _selectedVehicles = [defaultVehicle.first];
              } else {
                _selectedVehicles = [vehicles.first];
              }
            } else {
              _selectedVehicles = [vehicles.first];
            }
          }
        });
      }
    });
  }

  String _getStartTimeString() {
    if (_useCurrentTime) {
      final now = TimeOfDay.now();
      return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    return '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>?> _resolveCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition();
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final placemark = placemarks.first;
          final cityName =
              placemark.locality ??
              placemark.subAdministrativeArea ??
              'Current Location';
          return {
            'name': cityName,
            'lat': position.latitude,
            'lng': position.longitude,
          };
        }
      }
    } catch (e) {
      print('Error resolving current location: $e');
    }
    return null;
  }

  void _showTripSnackBar(
    String message, {
    Color bgColor = const Color(0xFF323232),
    IconData icon = Icons.info_outline,
    Color iconColor = Colors.white,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: duration,
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _planTrip() async {
    if (_isPlanning) return;
    if (_selectedVehicles.isEmpty) {
      _showTripSnackBar(
        'Please select at least one vehicle',
        bgColor: const Color(0xFFE53935),
        icon: Icons.directions_car_outlined,
      );
      return;
    }

    if (_destinationLocationName == null || _destinationLocationName!.isEmpty) {
      _showTripSnackBar(
        'Please select a destination',
        bgColor: const Color(0xFFE53935),
        icon: Icons.location_off_outlined,
      );
      return;
    }

    if (!_useCurrentLocation &&
        (_startLocationName == null || _startLocationName!.isEmpty)) {
      _showTripSnackBar(
        'Please select a starting point',
        bgColor: const Color(0xFFE53935),
        icon: Icons.my_location,
      );
      return;
    }

    // Validation: Ensure locations are within India
    bool isIndiaLocation(String location) {
      // Normalize string for checking
      final normalized = location.toLowerCase();
      // Basic check - reliable if using Google Places Autocomplete which returns "State, Country"
      return normalized.contains('india') || normalized.contains('bharat');
    }

    if (_destinationLocationName != null &&
        !isIndiaLocation(_destinationLocationName!)) {
      _showTripSnackBar(
        'Service is currently available only within India',
        bgColor: const Color(0xFFF57C00),
        icon: Icons.public_off_outlined,
      );
      return;
    }

    if (!_useCurrentLocation &&
        _startLocationName != null &&
        !isIndiaLocation(_startLocationName!)) {
      _showTripSnackBar(
        'Starting point must be within India',
        bgColor: const Color(0xFFF57C00),
        icon: Icons.public_off_outlined,
      );
      return;
    }

    // Resolve current location to city name if needed
    String finalStartLocation = _startLocationName ?? 'Current Location';
    double? finalStartLat = _startLat;
    double? finalStartLng = _startLng;

    setState(() => _isPlanning = true);

    if (_useCurrentLocation) {
      final resolved = await _resolveCurrentLocation();
      if (resolved != null) {
        finalStartLocation = resolved['name'];
        finalStartLat = resolved['lat'];
        finalStartLng = resolved['lng'];
      }
    }

    // Use the selected vehicle
    final selectedVehicle = _selectedVehicles.first;

    if (!mounted) return;

    setState(() => _isPlanning = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripResultScreen(
          startLocation: finalStartLocation,
          destination: _destinationLocationName!,
          vehicleId: selectedVehicle.id,
          evRange: selectedVehicle.maxRange.toStringAsFixed(0),
          vehicleType: '${selectedVehicle.brand} ${selectedVehicle.model}',
          useCurrentLocation: _useCurrentLocation,
          vehicles: _selectedVehicles,
          startTime: _getStartTimeString(),
          startLat: finalStartLat,
          startLng: finalStartLng,
          destLat: _destLat,
          destLng: _destLng,
          includeRestaurants: _includeRestaurants,
        ),
      ),
    );
  }

  void _loadTrip(TripPlan trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripResultScreen(
          startLocation: trip.startLocation,
          destination: trip.destination,
          vehicleId: trip.vehicleId,
          evRange: trip.evRange.toString(),
          vehicleType: trip.vehicleType,
          useCurrentLocation: false,
          preLoadedPlan: trip.planData,
          tripId: trip.id,
          vehicles: _selectedVehicles,
          startTime: _getStartTimeString(),
          startLat: trip.startLat,
          startLng: trip.startLng,
          destLat: trip.destLat,
          destLng: trip.destLng,
        ),
      ),
    );
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xFF1565C0)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _useCurrentTime = false;
      });
    }
  }

  void _showVehicleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDE3EE),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header row
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: const Text(
                  'Select Vehicle',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF0F4FB)),
              // Vehicle list
              if (_allVehicles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 40,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'No vehicles added yet',
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Add vehicles from your profile',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              else
                ..._allVehicles.map((vehicle) {
                  final isSel =
                      _selectedVehicles.isNotEmpty &&
                      _selectedVehicles.first.id == vehicle.id;

                  IconData vehicleIcon;
                  switch (vehicle.vehicleType) {
                    case '2 Wheeler':
                      vehicleIcon = Icons.two_wheeler;
                      break;
                    case '3 Wheeler':
                      vehicleIcon = Icons.electric_rickshaw;
                      break;
                    case 'Bus':
                      vehicleIcon = Icons.directions_bus;
                      break;
                    default:
                      vehicleIcon = Icons.directions_car;
                  }

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedVehicles = [vehicle];
                      });
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          // Vehicle icon
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? const Color(0xFF1A1A2E)
                                  : const Color(0xFFF0F4FB),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              vehicleIcon,
                              color: isSel
                                  ? Colors.white
                                  : const Color(0xFF1565C0),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Name & port
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${vehicle.brand} ${vehicle.model}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  vehicle.chargingPortType,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF90A4AE),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Range pill
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1565C0,
                              ).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${vehicle.maxRange.toStringAsFixed(0)} km',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Check indicator
                          if (isSel)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF00C853,
                                ).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF00C853),
                                size: 14,
                              ),
                            )
                          else
                            const SizedBox(width: 22),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  _buildInputCard(),
                  const SizedBox(height: 20),
                  _buildActionButtons(),
                  const SizedBox(height: 24),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Plans',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => AllTripsScreen(
                                selectedVehicles: _selectedVehicles,
                              ),
                            ),
                          );
                        },
                        child: const Row(
                          children: [
                            Text(
                              'View All',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color.fromARGB(255, 51, 155, 33),
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 14,
                              color: Color.fromARGB(255, 51, 155, 33),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildRecentTripsList(),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Trip Planner',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Plan your journey with optimal charging stops',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 18),
          // Vehicle selector card in header
          _buildVehicleHeaderCard(),
        ],
      ),
    );
  }

  Widget _buildVehicleHeaderCard() {
    if (_vehiclesLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_allVehicles.isEmpty) {
      return GestureDetector(
        onTap: () {
          _showTripSnackBar(
            'Add vehicles from Profile → My Vehicles',
            bgColor: const Color(0xFF1565C0),
            icon: Icons.directions_car_outlined,
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Add a vehicle to get started',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _showVehicleSelector,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _selectedVehicles.isEmpty
            ? Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.directions_car,
                      color: Color(0xFF1565C0),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Tap to select a vehicle',
                      style: TextStyle(fontSize: 15, color: Colors.grey),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
                ],
              )
            : _buildSingleVehicleDisplay(_selectedVehicles.first),
      ),
    );
  }

  Widget _buildSingleVehicleDisplay(Vehicle vehicle) {
    IconData vehicleIcon;
    switch (vehicle.vehicleType) {
      case '2 Wheeler':
        vehicleIcon = Icons.two_wheeler;
        break;
      case '3 Wheeler':
        vehicleIcon = Icons.electric_rickshaw;
        break;
      case 'Bus':
        vehicleIcon = Icons.directions_bus;
        break;
      default:
        vehicleIcon = Icons.directions_car;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(vehicleIcon, color: Colors.white, size: 15),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${vehicle.brand} ${vehicle.model}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                vehicle.chargingPortType,
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Max Range',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
            const SizedBox(height: 2),
            Text(
              '${vehicle.maxRange.toStringAsFixed(0)} km',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1565C0),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
      ],
    );
  }

  Widget _buildMultiVehicleDisplay() {
    final minRange = _selectedVehicles
        .map((v) => v.maxRange)
        .reduce((a, b) => a < b ? a : b);

    return Row(
      children: [
        // Stacked vehicle icons
        SizedBox(
          width: 54,
          height: 42,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF263238),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
              Positioned(
                left: 18,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(
                    Icons.directions_car,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_selectedVehicles.length} Vehicles Selected',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _selectedVehicles
                    .map((v) => '${v.brand} ${v.model}')
                    .join(', '),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Min Range',
              style: TextStyle(fontSize: 10, color: Colors.grey[500]),
            ),
            const SizedBox(height: 2),
            Text(
              '${minRange.toStringAsFixed(0)} km',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1565C0),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
      ],
    );
  }

  Widget _buildInputCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Starting Point Option
          const Text(
            'Starting Point',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Current Location'),
                selected: _useCurrentLocation,
                onSelected: (selected) {
                  setState(() {
                    _useCurrentLocation = selected;
                    if (selected) _startLocationName = null;
                  });
                },
                selectedColor: const Color.fromARGB(
                  255,
                  51,
                  155,
                  33,
                ).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _useCurrentLocation
                      ? const Color.fromARGB(255, 51, 155, 33)
                      : Colors.black,
                  fontWeight: _useCurrentLocation
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 10),
              ChoiceChip(
                label: const Text('Search'),
                selected: !_useCurrentLocation,
                onSelected: (selected) {
                  setState(() {
                    _useCurrentLocation = !selected;
                  });
                },
                selectedColor: const Color(0xFF1565C0).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: !_useCurrentLocation
                      ? const Color(0xFF1565C0)
                      : Colors.black,
                  fontWeight: !_useCurrentLocation
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),

          if (!_useCurrentLocation) ...[
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                return Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    if (textEditingValue.text.length < 3) {
                      return const Iterable<String>.empty();
                    }
                    try {
                      final places = await _placesService.searchPlaces(
                        textEditingValue.text,
                      );
                      return places.map((e) => e.description);
                    } catch (e) {
                      return const Iterable<String>.empty();
                    }
                  },
                  onSelected: (String selection) {
                    setState(() {
                      _startLocationName = selection;
                    });
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 6,
                        shadowColor: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                        child: Container(
                          width: constraints.maxWidth,
                          constraints: const BoxConstraints(maxHeight: 260),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade100),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                indent: 56,
                                endIndent: 16,
                                color: Colors.grey.shade100,
                              ),
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return InkWell(
                                  onTap: () => onSelected(option),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: const Color.fromARGB(
                                              255,
                                              51,
                                              155,
                                              33,
                                            ).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.location_on_outlined,
                                            size: 18,
                                            color: Color.fromARGB(
                                              255,
                                              51,
                                              155,
                                              33,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            option,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF1A1A2E),
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.north_west,
                                          size: 14,
                                          color: Colors.grey.shade400,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  fieldViewBuilder:
                      (
                        context,
                        textEditingController,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextField(
                          controller: textEditingController,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            hintText: 'Search starting point...',
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Colors.grey,
                            ),
                            fillColor: const Color(0xFFF8F9FE),
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        );
                      },
                );
              },
            ),
          ],

          const SizedBox(height: 20),

          // Destination
          const Text(
            'Destination',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              return Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) async {
                  if (textEditingValue.text.length < 3) {
                    return const Iterable<String>.empty();
                  }
                  try {
                    final places = await _placesService.searchPlaces(
                      textEditingValue.text,
                    );
                    return places.map((e) => e.description);
                  } catch (e) {
                    return const Iterable<String>.empty();
                  }
                },
                onSelected: (String selection) {
                  setState(() {
                    _destinationLocationName = selection;
                  });
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 6,
                      shadowColor: Colors.black.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: Container(
                        width: constraints.maxWidth,
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              indent: 56,
                              endIndent: 16,
                              color: Colors.grey.shade100,
                            ),
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              return InkWell(
                                onTap: () => onSelected(option),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.redAccent.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.location_on_outlined,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          option,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF1A1A2E),
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.north_west,
                                        size: 14,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
                fieldViewBuilder:
                    (
                      context,
                      textEditingController,
                      focusNode,
                      onFieldSubmitted,
                    ) {
                      return TextField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: 'Where to?',
                          prefixIcon: const Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                          ),
                          fillColor: const Color(0xFFF8F9FE),
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      );
                    },
              );
            },
          ),

          const SizedBox(height: 20),

          // Restaurants & Cafes toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FE),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEEFF4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restaurants & Cafes',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Include meal stops along the route',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _includeRestaurants,
                  onChanged: (val) => setState(() => _includeRestaurants = val),
                  activeColor: const Color.fromARGB(255, 51, 155, 33),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Start Time
          const Text(
            'Start Time',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _useCurrentTime = true;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: _useCurrentTime
                          ? const Color.fromARGB(
                              255,
                              51,
                              155,
                              33,
                            ).withValues(alpha: 0.1)
                          : const Color(0xFFF8F9FE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _useCurrentTime
                            ? const Color.fromARGB(255, 51, 155, 33)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 18,
                          color: _useCurrentTime
                              ? const Color.fromARGB(255, 51, 155, 33)
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Now',
                          style: TextStyle(
                            fontWeight: _useCurrentTime
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _useCurrentTime
                                ? const Color.fromARGB(255, 51, 155, 33)
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: _pickStartTime,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: !_useCurrentTime
                          ? const Color(0xFF1565C0).withValues(alpha: 0.1)
                          : const Color(0xFFF8F9FE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !_useCurrentTime
                            ? const Color(0xFF1565C0)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 18,
                          color: !_useCurrentTime
                              ? const Color(0xFF1565C0)
                              : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          !_useCurrentTime
                              ? _startTime.format(context)
                              : 'Pick Time',
                          style: TextStyle(
                            fontWeight: !_useCurrentTime
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: !_useCurrentTime
                                ? const Color(0xFF1565C0)
                                : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isPlanning ? null : _planTrip,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color.fromARGB(255, 51, 155, 33),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color.fromARGB(
            255,
            51,
            155,
            33,
          ).withValues(alpha: 0.7),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 5,
          shadowColor: const Color.fromARGB(
            255,
            51,
            155,
            33,
          ).withValues(alpha: 0.4),
        ),
        child: _isPlanning
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Planning Route...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : const Text(
                'Plan Optimal Route',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  Widget _buildRecentTripsList() {
    return StreamBuilder<List<TripPlan>>(
      stream: _tripService.getUserTrips(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                'No recent trips found.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final trips = snapshot.data!;
        final displayTrips = trips.length > 3 ? trips.sublist(0, 3) : trips;
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayTrips.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final trip = displayTrips[index];
            final dateStr = trip.timestamp.toString().split(' ')[0];

            return Dismissible(
              key: Key(trip.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20.0),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return await showDialog(
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
                          child: const Text(
                            "Delete",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              onDismissed: (direction) {
                _tripService.deleteTrip(trip.id);
                _showTripSnackBar(
                  'Trip plan deleted',
                  bgColor: const Color(0xFFB71C1C),
                  icon: Icons.delete_outline,
                  duration: const Duration(seconds: 4),
                );
              },
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(
                        255,
                        51,
                        155,
                        33,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.route_rounded,
                      color: Color.fromARGB(255, 51, 155, 33),
                    ),
                  ),
                  title: Text(
                    '${trip.startLocation} → ${trip.destination}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    'Range: ${trip.evRange} km • $dateStr',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Color.fromARGB(255, 51, 155, 33),
                  ),
                  onTap: () => _loadTrip(trip),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
