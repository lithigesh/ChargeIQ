class Vehicle {
  final String id;
  final String userId;

  // Section 1 — Vehicle Info
  final String brand;
  final String model;
  final String variant;
  final String vehicleType;
  final int manufacturingYear;
  final String registrationNumber;

  // Section 2 — Battery & Range
  final double batteryCapacity; // kWh
  final double maxRange; // km
  final String chargingPortType;
  final double maxACChargingPower; // kW
  final double maxDCFastChargingPower; // kW

  // Section 3 — Smart Settings
  final String drivingStyle;
  final bool acUsageUsually;
  final double? batteryHealthPercent;
  final String preferredChargingType;
  final int stopChargingAtPercent;
  final bool homeChargingAvailable;

  final DateTime createdAt;
  final DateTime updatedAt;

  Vehicle({
    required this.id,
    required this.userId,
    required this.brand,
    required this.model,
    this.variant = '',
    required this.vehicleType,
    required this.manufacturingYear,
    this.registrationNumber = '',
    required this.batteryCapacity,
    required this.maxRange,
    required this.chargingPortType,
    required this.maxACChargingPower,
    required this.maxDCFastChargingPower,
    this.drivingStyle = 'Normal',
    this.acUsageUsually = false,
    this.batteryHealthPercent,
    this.preferredChargingType = 'Fast',
    this.stopChargingAtPercent = 80,
    this.homeChargingAvailable = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'brand': brand,
      'model': model,
      'variant': variant,
      'vehicleType': vehicleType,
      'manufacturingYear': manufacturingYear,
      'registrationNumber': registrationNumber,
      'batteryCapacity': batteryCapacity,
      'maxRange': maxRange,
      'chargingPortType': chargingPortType,
      'maxACChargingPower': maxACChargingPower,
      'maxDCFastChargingPower': maxDCFastChargingPower,
      'drivingStyle': drivingStyle,
      'acUsageUsually': acUsageUsually,
      'batteryHealthPercent': batteryHealthPercent,
      'preferredChargingType': preferredChargingType,
      'stopChargingAtPercent': stopChargingAtPercent,
      'homeChargingAvailable': homeChargingAvailable,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Vehicle.fromMap(Map<String, dynamic> map, String docId) {
    return Vehicle(
      id: docId,
      userId: map['userId'] ?? '',
      brand: map['brand'] ?? '',
      model: map['model'] ?? '',
      variant: map['variant'] ?? '',
      vehicleType: map['vehicleType'] ?? 'Car',
      manufacturingYear: map['manufacturingYear'] ?? DateTime.now().year,
      registrationNumber: map['registrationNumber'] ?? '',
      batteryCapacity: (map['batteryCapacity'] ?? 0).toDouble(),
      maxRange: (map['maxRange'] ?? 0).toDouble(),
      chargingPortType: map['chargingPortType'] ?? 'CCS2',
      maxACChargingPower: (map['maxACChargingPower'] ?? 0).toDouble(),
      maxDCFastChargingPower: (map['maxDCFastChargingPower'] ?? 0).toDouble(),
      drivingStyle: map['drivingStyle'] ?? 'Normal',
      acUsageUsually: map['acUsageUsually'] ?? false,
      batteryHealthPercent: map['batteryHealthPercent']?.toDouble(),
      preferredChargingType: map['preferredChargingType'] ?? 'Fast',
      stopChargingAtPercent: map['stopChargingAtPercent'] ?? 80,
      homeChargingAvailable: map['homeChargingAvailable'] ?? false,
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
    );
  }

  Vehicle copyWith({
    String? id,
    String? userId,
    String? brand,
    String? model,
    String? variant,
    String? vehicleType,
    int? manufacturingYear,
    String? registrationNumber,
    double? batteryCapacity,
    double? maxRange,
    String? chargingPortType,
    double? maxACChargingPower,
    double? maxDCFastChargingPower,
    String? drivingStyle,
    bool? acUsageUsually,
    double? batteryHealthPercent,
    String? preferredChargingType,
    int? stopChargingAtPercent,
    bool? homeChargingAvailable,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Vehicle(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      variant: variant ?? this.variant,
      vehicleType: vehicleType ?? this.vehicleType,
      manufacturingYear: manufacturingYear ?? this.manufacturingYear,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      batteryCapacity: batteryCapacity ?? this.batteryCapacity,
      maxRange: maxRange ?? this.maxRange,
      chargingPortType: chargingPortType ?? this.chargingPortType,
      maxACChargingPower: maxACChargingPower ?? this.maxACChargingPower,
      maxDCFastChargingPower:
          maxDCFastChargingPower ?? this.maxDCFastChargingPower,
      drivingStyle: drivingStyle ?? this.drivingStyle,
      acUsageUsually: acUsageUsually ?? this.acUsageUsually,
      batteryHealthPercent: batteryHealthPercent ?? this.batteryHealthPercent,
      preferredChargingType:
          preferredChargingType ?? this.preferredChargingType,
      stopChargingAtPercent:
          stopChargingAtPercent ?? this.stopChargingAtPercent,
      homeChargingAvailable:
          homeChargingAvailable ?? this.homeChargingAvailable,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
