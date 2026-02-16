import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  late final GenerativeModel _model;
  final String _apiKey = dotenv.env['GEMINI_API'] ?? '';

  GeminiService() {
    if (_apiKey.isEmpty) {
      print('Warning: GEMINI_API key is missing in .env');
    }
    // Using gemini-1.5-flash as it is the current standard fast model.
    // If the user specifically meant a newer preview model, this string can be updated.
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );
  }

  Future<String> planTrip({
    required String startLocation,
    required String destination,
    required String evRange,
    String? vehicleType,
  }) async {
    try {
      final prompt =
          '''
      Plan a detailed EV road trip from "$startLocation" to "$destination".
      Vehicle Range: $evRange km.
      Vehicle Type: ${vehicleType ?? 'EV'}.
      
      Objective: Find the most optimized route.
      CRITICAL REQUIREMENT: Combine charging stations with highly-rated restaurants or dining options to save time. 
      The user wants to eat while charging.
      
      Please provide the response in a structured JSON format (without markdown code blocks if possible, or wrap in ```json).
      structure:
      {
        "summary": "Brief summary of the trip (total distance, duration, stops)",
        "total_distance": "X km",
        "total_duration": "Y hours Z mins",
        "route_segments": [
          {
            "segment_type": "drive" or "stop",
            "from": "Location A",
            "to": "Location B",
            "distance": "X km",
            "duration": "Y mins",
            "description": "Drive from A to B..."
          },
          {
            "segment_type": "charge_meal",
            "location_name": "Charging Station Name",
            "address": "Address",
            "restaurant_name": "Restaurant Name",
            "restaurant_rating": "4.5",
            "charging_time": "30 mins",
            "notes": "Why this stop was chosen"
          }
        ]
      }
      Also include specific Google Maps searchable names or addresses for the stops.
      ''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      return response.text ?? '{"error": "No response generated"}';
    } catch (e) {
      return '{"error": "Failed to generate plan: $e"}';
    }
  }
}
