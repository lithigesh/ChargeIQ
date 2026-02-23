import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  /// Select optimal EV charging station using AI analysis
  /// Takes a list of nearby stations and returns the best one based on multiple factors
  Future<Map<String, dynamic>?> selectOptimalStation({
    required List<Map<String, dynamic>> nearbyStations,
    required double currentLatitude,
    required double currentLongitude,
  }) async {
    try {
      if (nearbyStations.isEmpty) {
        debugPrint('❌ No stations to analyze');
        return null;
      }

      debugPrint(
        '📡 [GEMINI API] Starting API call to select optimal station...',
      );
      debugPrint('📊 [GEMINI API] Analyzing ${nearbyStations.length} stations');

      // Format stations data for AI analysis
      final stationsData = nearbyStations
          .asMap()
          .entries
          .map((entry) {
            final idx = entry.key;
            final station = entry.value;
            return '''
        Station ${idx + 1}:
        - Name: ${station['name'] ?? 'N/A'}
        - Distance: ${station['distance']?.toStringAsFixed(1) ?? 'N/A'} km
        - Rating: ${station['rating']?.toStringAsFixed(1) ?? 'N/A'}/5 (${station['userRatingsTotal'] ?? 0} reviews)
        - Status: ${station['isOpen'] == true
                ? 'Open Now'
                : station['isOpen'] == false
                ? 'Closed'
                : 'Unknown'}
        - Available Ports: ${station['available_ports']?.toString() ?? 'N/A'}
        - Price: ${station['price']?.toStringAsFixed(2) ?? 'N/A'}/kWh
        - Address: ${station['vicinity'] ?? 'N/A'}
        ''';
          })
          .join('\n');

      final prompt =
          '''
      You are an intelligent EV charging station selector. Analyze these nearby charging stations and recommend the SINGLE BEST station for immediate charging.

$stationsData

      SELECTION CRITERIA (in order of importance):
      1. **Availability**: Must show as "Open Now"
      2. **Distance**: Prefer closer stations (less than 5km is excellent, 5-10km is good)
      3. **Quality**: High rating (4.0+ is excellent, 3.5+ is good)
      4. **Availability Ports**: More available ports = better
      5. **Price**: Prefer cheaper options when other factors are equal

      Rules:
      - If a station is "Closed", it should NOT be selected unless all others are closed
      - Balance between distance and quality - don't just pick the closest if it has poor ratings
      - A moderately close (8km) highly-rated station (4.5+ stars) is better than a very close (2km) poorly-rated station (2 stars)
      - Consider practical factors: would you wait 15-20 mins extra to use a station with 4.5 stars vs nearby 2-star station?

      Return ONLY a JSON response with this exact format:
      {
        "selected_index": 0,
        "station_name": "Station Name",
        "reason": "Brief explanation (1-2 sentences) why this is optimal",
        "score": 0.0,
        "distance_km": 0.0,
        "rating": 0.0,
        "confidence": 0.95
      }

      IMPORTANT: Return ONLY valid JSON, no additional text.
      ''';

      final content = [Content.text(prompt)];
      debugPrint(
        '📡 [GEMINI API] 🚀 Sending request to Gemini API (model: gemini-2.5-flash)...',
      );

      final response = await _model.generateContent(content);

      debugPrint('✅ [GEMINI API] 🎉 API Response received successfully!');

      if (response.text == null) {
        debugPrint('❌ [GEMINI API] Response was null');
        return null;
      }

      debugPrint(
        '📄 [GEMINI API] Response preview: ${response.text!.substring(0, 100)}...',
      );

      // Parse the AI response
      final responseText = response.text!.trim();

      // Extract JSON from response (handle cases where AI adds extra text)
      String jsonStr = responseText;
      final jsonStart = responseText.indexOf('{');
      final jsonEnd = responseText.lastIndexOf('}');

      if (jsonStart != -1 && jsonEnd != -1) {
        jsonStr = responseText.substring(jsonStart, jsonEnd + 1);
      }

      debugPrint('🔍 [GEMINI API] Parsing JSON response...');

      final jsonResponse = jsonDecode(jsonStr) as Map<String, dynamic>;
      final selectedIndex = (jsonResponse['selected_index'] as num).toInt();

      debugPrint(
        '✔️ [GEMINI API] JSON parsed successfully. Selected index: $selectedIndex',
      );

      if (selectedIndex >= 0 && selectedIndex < nearbyStations.length) {
        // Add AI selection metadata to the selected station
        final selectedStation = Map<String, dynamic>.from(
          nearbyStations[selectedIndex],
        );
        selectedStation['ai_reason'] = jsonResponse['reason'] ?? '';
        selectedStation['ai_score'] = jsonResponse['score'] ?? 0.0;
        selectedStation['ai_confidence'] = jsonResponse['confidence'] ?? 0.0;
        selectedStation['selected_via_ai'] = true;

        debugPrint(
          '🎯 [GEMINI API] ✅ AI SUCCESSFULLY SELECTED: ${selectedStation['name']} '
          '| Confidence: ${(jsonResponse['confidence'] * 100).toStringAsFixed(0)}%',
        );

        return selectedStation;
      }

      debugPrint('❌ [GEMINI API] Selected index out of range: $selectedIndex');
      return null;
    } catch (e, stackTrace) {
      debugPrint('❌ [GEMINI API] 🔴 ERROR OCCURRED: $e');
      debugPrint(
        '📍 [GEMINI API] Stack: ${stackTrace.toString().split('\n').first}',
      );
      return null;
    }
  }
}
