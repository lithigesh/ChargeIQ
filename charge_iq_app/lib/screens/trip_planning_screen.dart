import 'package:flutter/material.dart';

import '../services/places_service.dart';
import '../services/trip_service.dart';
import '../models/trip_plan.dart';
import 'trip_result_screen.dart'; // Import the new screen

class TripPlanningScreen extends StatefulWidget {
  const TripPlanningScreen({super.key});

  @override
  State<TripPlanningScreen> createState() => _TripPlanningScreenState();
}

class _TripPlanningScreenState extends State<TripPlanningScreen> {
  final TextEditingController _rangeController = TextEditingController(
    text: '300',
  );
  // removed formKey

  // Services
  final PlacesService _placesService = PlacesService();
  final TripService _tripService = TripService();

  // State
  bool _useCurrentLocation = true;
  String? _startLocationName;
  String? _destinationLocationName;
  // Removed local plan state _generatedPlan and _isLoading

  // Controllers for Autocomplete
  // We don't need TextEditingControllers for Autocomplete if we use onSelected,
  // but we might want initial values.

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  void _planTrip() {
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

    // Navigate to TripResultScreen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripResultScreen(
          startLocation: _startLocationName ?? 'Current Location',
          destination: _destinationLocationName!,
          evRange: _rangeController.text,
          vehicleType: 'Tesla Model 3',
          useCurrentLocation: _useCurrentLocation,
        ),
      ),
    );
  }

  // Removed _saveTrip as it is now in ResultScreen

  void _loadTrip(TripPlan trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TripResultScreen(
          startLocation: trip.startLocation,
          destination: trip.destination,
          evRange: trip.evRange.toString(),
          vehicleType: trip.vehicleType,
          useCurrentLocation: trip.startLocation == 'Current Location',
          preLoadedPlan: trip.planData,
          tripId: trip.id,
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

                  // Removed local results display
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
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 30),
      decoration: const BoxDecoration(
        color: Color(0xFF1565C0),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Trip Planner',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'AI-Powered EV Route Optimization',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        ],
      ),
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
            color: Colors.black.withOpacity(0.05),
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
                selectedColor: const Color(0xFF00D26A).withOpacity(0.2),
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
                selectedColor: const Color(0xFF1565C0).withOpacity(0.2),
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
                    // Fetch places from PlacesService
                    try {
                      final places = await _placesService.searchPlaces(
                        textEditingValue.text,
                      );
                      return places.map(
                        (e) => e.description,
                      ); // Return descriptions
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

          // Vehicle Range
          const Text(
            'Vehicle Range (km)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rangeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              suffixText: 'km',
              prefixIcon: const Icon(
                Icons.battery_charging_full,
                color: Colors.green,
              ),
              fillColor: const Color(0xFFF8F9FE),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
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
          shadowColor: const Color(0xFF00D26A).withOpacity(0.4),
        ),
        child: const Text(
          'Plan Optimal Route',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // Removed _buildPlanResult as it is moved to TripResultScreen

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
            final dateStr = trip.timestamp.toString().split(
              ' ',
            )[0]; // Simple formatting

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
