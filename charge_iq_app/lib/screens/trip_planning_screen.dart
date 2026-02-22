import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../models/vehicle.dart';
import '../services/places_service.dart';
import '../services/trip_service.dart';
import '../services/vehicle_service.dart';
import '../models/trip_plan.dart';
import 'trip_result_screen.dart';

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

  void _planTrip() async {
    if (_selectedVehicles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one vehicle')),
      );
      return;
    }

    if (_destinationLocationName == null || _destinationLocationName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a destination')),
      );
      return;
    }

    if (!_useCurrentLocation &&
        (_startLocationName == null || _startLocationName!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a starting point')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Service is currently available only within India 🇮🇳',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_useCurrentLocation &&
        _startLocationName != null &&
        !isIndiaLocation(_startLocationName!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Starting point must be within India 🇮🇳'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Resolve current location to city name if needed
    String finalStartLocation = _startLocationName ?? 'Current Location';
    double? finalStartLat = _startLat;
    double? finalStartLng = _startLng;

    if (_useCurrentLocation) {
      final resolved = await _resolveCurrentLocation();
      if (resolved != null) {
        finalStartLocation = resolved['name'];
        finalStartLat = resolved['lat'];
        finalStartLng = resolved['lng'];
      }
    }

    // Get the minimum range across selected vehicles
    final minRange = _selectedVehicles
        .map((v) => v.maxRange)
        .reduce((a, b) => a < b ? a : b);

    // Build a vehicle name string
    final vehicleNames = _selectedVehicles
        .map((v) => '${v.brand} ${v.model}')
        .join(', ');

    // Use the first selected vehicle as primary vehicle for the trip
    final primaryVehicle = _selectedVehicles.first;

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripResultScreen(
          startLocation: finalStartLocation,
          destination: _destinationLocationName!,
          vehicleId: primaryVehicle.id,
          evRange: minRange.toStringAsFixed(0),
          vehicleType: vehicleNames,
          useCurrentLocation: _useCurrentLocation,
          vehicles: _selectedVehicles,
          startTime: _getStartTimeString(),
          startLat: finalStartLat,
          startLng: finalStartLng,
          destLat: _destLat,
          destLng: _destLng,
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
    // Create a temporary selection list
    final tempSelected = List<Vehicle>.from(_selectedVehicles);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.55,
              maxChildSize: 0.85,
              minChildSize: 0.35,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    // Handle
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 8),
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Title
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Select Vehicles',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedVehicles = List<Vehicle>.from(
                                  tempSelected,
                                );
                              });
                              Navigator.pop(context);
                            },
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: Color(0xFF1565C0),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Vehicle list
                    Expanded(
                      child: _allVehicles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.directions_car_outlined,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No vehicles added yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Add vehicles from your profile',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _allVehicles.length,
                              itemBuilder: (context, index) {
                                final vehicle = _allVehicles[index];
                                final isSelected = tempSelected.any(
                                  (v) => v.id == vehicle.id,
                                );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildVehicleSelectorCard(
                                    vehicle,
                                    isSelected,
                                    () {
                                      setModalState(() {
                                        if (isSelected) {
                                          tempSelected.removeWhere(
                                            (v) => v.id == vehicle.id,
                                          );
                                        } else {
                                          tempSelected.add(vehicle);
                                        }
                                      });
                                    },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildVehicleSelectorCard(
    Vehicle vehicle,
    bool isSelected,
    VoidCallback onTap,
  ) {
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

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F5E9) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF10B981)
                    : const Color(0xFF263238),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(vehicleIcon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${vehicle.brand} ${vehicle.model}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    vehicle.variant.isNotEmpty
                        ? vehicle.variant
                        : vehicle.vehicleType,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            // Range badge
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            // Checkbox indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF10B981)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF10B981)
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
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
                  const Text(
                    'Recent Plans',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Add vehicles from your Profile → My Vehicles'),
            ),
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
            : _selectedVehicles.length == 1
            ? _buildSingleVehicleDisplay(_selectedVehicles.first)
            : _buildMultiVehicleDisplay(),
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
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF263238),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(vehicleIcon, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${vehicle.brand} ${vehicle.model}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vehicle.variant.isNotEmpty
                    ? vehicle.variant
                    : vehicle.vehicleType,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                selectedColor: const Color(0xFF00D26A).withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  color: _useCurrentLocation
                      ? const Color(0xFF00D26A)
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
                          ? const Color(0xFF00D26A).withValues(alpha: 0.1)
                          : const Color(0xFFF8F9FE),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _useCurrentTime
                            ? const Color(0xFF00D26A)
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
                              ? const Color(0xFF00D26A)
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
                                ? const Color(0xFF00D26A)
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
        onPressed: _planTrip,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00D26A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 5,
          shadowColor: const Color(0xFF00D26A).withValues(alpha: 0.4),
        ),
        child: const Text(
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
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: trips.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final trip = trips[index];
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Trip deleted')));
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
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.map, color: Colors.blue),
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
                    color: Colors.grey,
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
