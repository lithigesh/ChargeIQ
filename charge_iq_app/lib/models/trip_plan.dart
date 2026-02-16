class TripPlan {
  final String id;
  final String userId;
  final String startLocation;
  final String destination;
  final int evRange;
  final String vehicleType;
  final String planData; // JSON string of the plan
  final DateTime timestamp;

  TripPlan({
    required this.id,
    required this.userId,
    required this.startLocation,
    required this.destination,
    required this.evRange,
    required this.vehicleType,
    required this.planData,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'startLocation': startLocation,
      'destination': destination,
      'evRange': evRange,
      'vehicleType': vehicleType,
      'planData': planData,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory TripPlan.fromMap(Map<String, dynamic> map, String docId) {
    return TripPlan(
      id: docId,
      userId: map['userId'] ?? '',
      startLocation: map['startLocation'] ?? '',
      destination: map['destination'] ?? '',
      evRange: map['evRange'] ?? 0,
      vehicleType: map['vehicleType'] ?? 'Unknown',
      planData: map['planData'] ?? '{}',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
    );
  }
}
