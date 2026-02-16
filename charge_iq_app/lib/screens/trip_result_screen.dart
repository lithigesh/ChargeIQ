import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import '../services/gemini_service.dart';
import '../services/trip_service.dart';
import '../services/directions_service.dart';

class TripResultScreen extends StatefulWidget {
  final String startLocation;
  final String destination;
  final String evRange;
  final String vehicleType;
  final bool useCurrentLocation;
  final String? preLoadedPlan;
  final String? tripId; // For deletion from Firestore

  const TripResultScreen({
    super.key,
    required this.startLocation,
    required this.destination,
    required this.evRange,
    required this.vehicleType,
    required this.useCurrentLocation,
    this.preLoadedPlan,
    this.tripId,
  });

  @override
  State<TripResultScreen> createState() => _TripResultScreenState();
}

class _TripResultScreenState extends State<TripResultScreen> {
  final GeminiService _geminiService = GeminiService();
  final TripService _tripService = TripService();
  final DirectionsService _directionsService = DirectionsService();

  String? _generatedPlan;
  bool _isLoading = true;
  String? _error;
  String? _realTimeDistance;
  String? _realTimeDuration;
  bool _isSaved = false;
  String _currentCity = '';

  @override
  void initState() {
    super.initState();
    _fetchCurrentCity();
    if (widget.preLoadedPlan != null) {
      _generatedPlan = widget.preLoadedPlan;
      _isLoading = false;
      _isSaved = true;
    } else {
      _generatePlan();
    }
  }

  Future<void> _fetchCurrentCity() async {
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
        if (placemarks.isNotEmpty && mounted) {
          setState(() {
            _currentCity = placemarks.first.locality ?? '';
          });
        }
      }
    } catch (e) {
      print('Error fetching city: $e');
    }
  }

  Future<void> _generatePlan() async {
    String start = widget.startLocation;

    if (widget.useCurrentLocation &&
        start.toLowerCase().contains('current location')) {
      try {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition();
          start = '${position.latitude}, ${position.longitude}';
        }
      } catch (e) {
        print('Location fetch failed: $e');
      }
    }

    try {
      final plan = await _geminiService.planTrip(
        startLocation: start,
        destination: widget.destination,
        evRange: widget.evRange,
        vehicleType: widget.vehicleType,
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
        evRange: int.tryParse(widget.evRange) ?? 300,
        vehicleType: widget.vehicleType,
        planData: finalPlanData,
      );

      print(
        'Trip saved to Firestore path: users/${_tripService.currentUserId}/trips',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip saved successfully!')),
        );
      }
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
    String titleText;
    if (widget.startLocation == 'Current Location' ||
        widget.startLocation.contains(',')) {
      titleText = _currentCity.isNotEmpty
          ? '$_currentCity → ${widget.destination}'
          : 'Trip to ${widget.destination}';
    } else {
      titleText = '${widget.startLocation} → ${widget.destination}';
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: Text(titleText, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.white,
        centerTitle: true,
        actions: [
          if (!_isLoading && _generatedPlan != null)
            _isSaved
                ? IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _deleteTrip,
                  )
                : IconButton(
                    icon: const Icon(Icons.save_alt),
                    onPressed: _saveTrip,
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
            itemCount: segments.length,
            itemBuilder: (context, index) {
              final seg = segments[index];
              final isLast = index == segments.length - 1;
              return _buildTimelineItem(seg, isLast);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(Map<String, dynamic> plan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildStatChip(
              Icons.directions_car,
              _realTimeDistance ?? _cleanText(plan['total_distance'] ?? 'N/A'),
            ),
            const SizedBox(width: 12),
            _buildStatChip(
              Icons.timer,
              _realTimeDuration ?? _cleanText(plan['total_duration'] ?? 'N/A'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E7FF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF1565C0)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF1565C0),
              fontWeight: FontWeight.bold,
              fontSize: 13,
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
                      color: Colors.grey.withOpacity(0.3),
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
    if (clean.toLowerCase().contains('mi')) {
      clean = clean.replaceAll('mi', 'km').replaceAll('miles', 'km');
    }
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
          '${segment['duration'] ?? ''}',
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
          ListTile(
            dense: true,
            title: Text(
              segment['location_name'] ?? 'Stop',
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              segment['address'] ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                segment['charging_time'] ?? '',
                style: const TextStyle(
                  color: Color(0xFF2E7D32),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.restaurant, size: 18, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        segment['restaurant_name'] ?? 'Dining Option',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '${segment['restaurant_rating'] ?? 'N/A'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
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
}
