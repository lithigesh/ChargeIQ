import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/vehicle.dart';

class GeminiService {
  late final GenerativeModel _model;
  final String _apiKey = dotenv.env['GEMINI_API'] ?? '';

  GeminiService() {
    if (_apiKey.isEmpty) {
      print('Warning: GEMINI_API key is missing in .env');
    }
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );
  }

  Future<String> planTrip({
    required String startLocation,
    required String destination,
    required List<Vehicle> vehicles,
    required String startTime,
    String? vehicleType,
    String? evRange,
  }) async {
    try {
      // Build vehicle context
      final vehicleContext = vehicles
          .map((v) {
            return '''
        - ${v.brand} ${v.model} ${v.variant}
          Type: ${v.vehicleType}
          Battery: ${v.batteryCapacity} kWh
          Max Range: ${v.maxRange} km
          Charging Port: ${v.chargingPortType}
          Max AC Charging: ${v.maxACChargingPower} kW
          Max DC Fast Charging: ${v.maxDCFastChargingPower} kW
          Driving Style: ${v.drivingStyle}
          AC Usage Usually: ${v.acUsageUsually ? 'Yes' : 'No'}
          Battery Health: ${v.batteryHealthPercent != null ? '${v.batteryHealthPercent}%' : 'N/A'}
          Preferred Charging: ${v.preferredChargingType}
          Stop Charging At: ${v.stopChargingAtPercent}%
          Home Charging: ${v.homeChargingAvailable ? 'Yes' : 'No'}''';
          })
          .join('\n');

      // Determine the effective range (minimum across all vehicles for safety)
      final effectiveRange = vehicles.isNotEmpty
          ? vehicles.map((v) => v.maxRange).reduce((a, b) => a < b ? a : b)
          : (double.tryParse(evRange ?? '300') ?? 300);

      // Determine driving adjustments
      final drivingAdjustment = vehicles.isNotEmpty
          ? vehicles.first.drivingStyle
          : 'Normal';
      final acUsage = vehicles.isNotEmpty && vehicles.first.acUsageUsually;
      final batteryHealth = vehicles.isNotEmpty
          ? vehicles.first.batteryHealthPercent
          : null;

      // Calculate realistic range
      double rangeMultiplier = 1.0;
      if (drivingAdjustment == 'Sport') rangeMultiplier *= 0.85;
      if (drivingAdjustment == 'Eco') rangeMultiplier *= 1.1;
      if (acUsage) rangeMultiplier *= 0.88;
      if (batteryHealth != null && batteryHealth < 90) {
        rangeMultiplier *= (batteryHealth / 100);
      }
      final realisticRange = (effectiveRange * rangeMultiplier).round();

      // Determine max charge percent
      final maxCharge = vehicles.isNotEmpty
          ? vehicles.first.stopChargingAtPercent
          : 80;

      final prompt =
          '''
      Plan a detailed EV road trip from "$startLocation" to "$destination".
      
      VEHICLE DETAILS:
$vehicleContext

      TRIP PARAMETERS:
      - Realistic usable range (adjusted for driving style, AC, battery health): $realisticRange km
      - Max charge to: $maxCharge%
      - Start time: $startTime (24-hr format IST)
      
      SMART PLANNING RULES:
      1. Use the realistic range to plan charging stops. Plan stops BEFORE the battery gets below 15%.
      2. Consider the vehicle's charging port type and max DC fast charging power when suggesting stations.
      3. If preferred charging type is "Cheap", prefer slower AC stations; if "Fast", prefer DC fast chargers; if "Nearby", pick nearest.
      4. Only charge up to $maxCharge% at each stop for battery longevity.
      
      MEAL PLANNING RULES (based on start time $startTime):
      - Calculate the estimated arrival time at each charging stop.
      - ONLY suggest meal stops that align with the appropriate meal time:
        * Breakfast: 7:00 AM - 10:00 AM → suggest a restaurant
        * Lunch: 12:00 PM - 2:30 PM → suggest a restaurant
        * Snack: 3:00 PM - 5:30 PM → suggest a cafe or bakery
        * Dinner: 7:00 PM - 10:00 PM → suggest a restaurant
      - If a charging stop does NOT fall during a meal time, mark restaurant_name as null and meal_type as "none".
      - If it DOES fall during a meal time, suggest a highly-rated restaurant/cafe/bakery nearby with the correct meal_type.
      
      Provide the response in structured JSON format:
      {
        "summary": "Brief summary of the trip",
        "total_distance": "X km",
        "total_duration": "Y hours Z mins",
        "estimated_arrival": "HH:MM AM/PM",
        "vehicles_used": ["Brand Model"],
        "route_segments": [
          {
            "segment_type": "drive",
            "from": "Location A",
            "to": "Location B",
            "distance": "X km",
            "duration": "Y mins",
            "estimated_time_at_arrival": "HH:MM AM/PM",
            "description": "Drive from A to B..."
          },
          {
            "segment_type": "charge_meal",
            "location_name": "Charging Station Name",
            "address": "Full Address",
            "charging_time": "30 mins",
            "charger_type": "DC Fast / AC",
            "estimated_time_at_arrival": "HH:MM AM/PM",
            "meal_type": "breakfast" | "lunch" | "snack" | "dinner" | "none",
            "restaurant_name": "Restaurant/Cafe Name or null",
            "restaurant_rating": "4.5 or null",
            "cuisine_type": "Indian / Chinese / etc or null",
            "notes": "Why this stop was chosen"
          }
        ]
      }
      Include specific Google Maps searchable names or addresses for all stops.
      ''';

      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);

      return response.text ?? '{"error": "No response generated"}';
    } catch (e) {
      return '{"error": "Failed to generate plan: $e"}';
    }
  }
}
