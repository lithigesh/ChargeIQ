import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {

  final String apiKey = "81bb8211-e4a9-4df9-b694-81e74afe4908";

  Set<Marker> _markers = {};
  MapType _currentMapType = MapType.normal;

  final List<LatLng> tamilNaduCities = [
    LatLng(13.0827, 80.2707),
    LatLng(11.0168, 76.9558),
    LatLng(9.9252, 78.1198),
    LatLng(10.7905, 78.7047),
    LatLng(11.6643, 78.1460),
    LatLng(8.7139, 77.7567),
  ];

  @override
  void initState() {
    super.initState();
    _loadTamilNaduStations();
  }

  Future<void> _loadTamilNaduStations() async {
    Set<Marker> newMarkers = {};

    for (var city in tamilNaduCities) {
      final url =
          "https://api.openchargemap.io/v3/poi/"
          "?output=json"
          "&countrycode=IN"
          "&latitude=${city.latitude}"
          "&longitude=${city.longitude}"
          "&distance=30"
          "&distanceunit=KM"
          "&maxresults=100";

      final response = await http.get(
        Uri.parse(url),
        headers: {
          "X-API-Key": apiKey,
          "User-Agent": "ChargeIQ-Flutter-App",
        },
      );

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);

        for (var station in data) {
          final info = station['AddressInfo'];
          final status = station['StatusType'];
          final usage = station['UsageType'];

          if (info != null &&
              info['Latitude'] != null &&
              info['Longitude'] != null &&
              status != null &&
              status['IsOperational'] == true &&
              usage != null &&
              usage['Title'] != "Private - Restricted Access") {

            final lat = (info['Latitude'] as num).toDouble();
            final lng = (info['Longitude'] as num).toDouble();

            if (lat > 5 && lat < 40 && lng > 65 && lng < 100) {
              newMarkers.add(
                Marker(
                  markerId: MarkerId(info['ID'].toString()),
                  position: LatLng(lat, lng),
                  infoWindow: InfoWindow(
                    title: info['Title'] ?? "EV Station",
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen),
                ),
              );
            }
          }
        }
      }
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  void _toggleMapType() {
    setState(() {
      _currentMapType =
          _currentMapType == MapType.normal ? MapType.hybrid : MapType.normal;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(11.1271, 78.6569),
          zoom: 7,
        ),
        markers: _markers,
        mapType: _currentMapType,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleMapType,
        child: const Icon(Icons.layers),
      ),
    );
  }
}
