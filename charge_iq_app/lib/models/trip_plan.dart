class TripPlan {
  final String id;
  final String userId;
  final String startLocation;
  final String destination;
  final String vehicleId; // Primary vehicle used for this trip
  final int evRange; // Kept for backward compatibility
  final String vehicleType; // Kept for backward compatibility
  final String planData; // JSON string of the plan
  final DateTime timestamp;
  final double? startLat;
  final double? startLng;
  final double? destLat;
  final double? destLng;

  TripPlan({
    required this.id,
    required this.userId,
    required this.startLocation,
    required this.destination,
    required this.vehicleId,
    required this.evRange,
    required this.vehicleType,
    required this.planData,
    required this.timestamp,
    this.startLat,
    this.startLng,
    this.destLat,
    this.destLng,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'startLocation': startLocation,
      'destination': destination,
      'vehicleId': vehicleId,
      'evRange': evRange,
      'vehicleType': vehicleType,
      'planData': planData,
      'timestamp': timestamp.toIso8601String(),
      'startLat': startLat,
      'startLng': startLng,
      'destLat': destLat,
      'destLng': destLng,
    };
  }

  factory TripPlan.fromMap(Map<String, dynamic> map, String docId) {
    return TripPlan(
      id: docId,
      userId: map['userId'] ?? '',
      startLocation: map['startLocation'] ?? '',
      destination: map['destination'] ?? '',
      vehicleId: map['vehicleId'] ?? '', // New field
      evRange: map['evRange'] ?? 0,
      vehicleType: map['vehicleType'] ?? 'Unknown',
      planData: map['planData'] ?? '{}',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      startLat: map['startLat']?.toDouble(),
      startLng: map['startLng']?.toDouble(),
      destLat: map['destLat']?.toDouble(),
      destLng: map['destLng']?.toDouble(),
    );
  }
}
