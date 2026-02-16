import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DirectionsService {
  final String? _apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];

  Future<Map<String, String>?> getDirections(
    String origin,
    String destination,
  ) async {
    if (_apiKey == null) return null;

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&units=metric&key=$_apiKey',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final leg = data['routes'][0]['legs'][0];
          return {
            'distance': leg['distance']['text'],
            'duration': leg['duration']['text'],
          };
        }
      }
    } catch (e) {
      print('Directions API Error: $e');
    }
    return null;
  }
}
