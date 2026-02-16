import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceArg {
  final String description;
  final String placeId;

  PlaceArg({required this.description, required this.placeId});

  factory PlaceArg.fromJson(Map<String, dynamic> json) {
    return PlaceArg(
      description: json['description'] ?? '',
      placeId: json['place_id'] ?? '',
    );
  }
}

class PlaceDetails {
  final String name;
  final String formattedAddress;
  final LatLng location;

  PlaceDetails({
    required this.name,
    required this.formattedAddress,
    required this.location,
  });

  factory PlaceDetails.fromJson(Map<String, dynamic> json) {
    final result = json['result'] ?? {};
    final geometry = result['geometry'] ?? {};
    final location = geometry['location'] ?? {};

    return PlaceDetails(
      name: result['name'] ?? '',
      formattedAddress: result['formatted_address'] ?? '',
      location: LatLng(
        (location['lat'] as num?)?.toDouble() ?? 0.0,
        (location['lng'] as num?)?.toDouble() ?? 0.0,
      ),
    );
  }
}

class PlacesService {
  final String _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  Future<List<PlaceArg>> searchPlaces(String query) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' || data['status'] == 'ZERO_RESULTS') {
          // Also handle ZERO_RESULTS gracefully
          final predictions = data['predictions'] as List? ?? [];
          return predictions.map((p) => PlaceArg.fromJson(p)).toList();
        }
        print(
          'Place Search Error: ${data['status']} - ${data['error_message']}',
        );
        return [];
      } else {
        print('HTTP Error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Places Service Exception: $e');
      return [];
    }
  }

  Future<PlaceDetails?> getPlaceDetails(String placeId) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$_apiKey&fields=name,geometry,formatted_address',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK') {
          return PlaceDetails.fromJson(data);
        }
        print('Place Details Error: ${data['status']}');
        return null;
      } else {
        return null;
      }
    } catch (e) {
      print('Place Details Exception: $e');
      return null;
    }
  }
}
