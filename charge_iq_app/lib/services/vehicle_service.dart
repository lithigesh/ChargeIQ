import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/vehicle.dart';

class VehicleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _vehiclesCollection() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in');
    }
    return _firestore.collection('users').doc(user.uid).collection('vehicles');
  }

  DocumentReference<Map<String, dynamic>> _userDoc() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in');
    }
    return _firestore.collection('users').doc(user.uid);
  }

  // CREATE — Add a new vehicle
  Future<String> addVehicle(Vehicle vehicle) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to add a vehicle');
    }

    try {
      final docRef = _vehiclesCollection().doc();
      final now = DateTime.now();
      final newVehicle = vehicle.copyWith(
        id: docRef.id,
        userId: user.uid,
        createdAt: now,
        updatedAt: now,
      );
      await docRef.set(newVehicle.toMap());

      // If this is the first/only vehicle, auto-set as default
      final vehicleCount = await _vehiclesCollection().count().get();
      if (vehicleCount.count == 1) {
        await setDefaultVehicleId(docRef.id);
      }

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add vehicle: $e');
    }
  }

  // READ — Get all user's vehicles as a stream
  Stream<List<Vehicle>> getUserVehicles() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _vehiclesCollection()
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Vehicle.fromMap(doc.data(), doc.id);
          }).toList();
        });
  }

  // READ — Get a single vehicle by ID
  Future<Vehicle?> getVehicle(String vehicleId) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _vehiclesCollection().doc(vehicleId).get();
      if (!doc.exists) return null;
      return Vehicle.fromMap(doc.data()!, doc.id);
    } catch (e) {
      throw Exception('Failed to get vehicle: $e');
    }
  }

  // UPDATE — Update an existing vehicle
  Future<void> updateVehicle(Vehicle vehicle) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to update a vehicle');
    }

    try {
      final updatedVehicle = vehicle.copyWith(updatedAt: DateTime.now());
      await _vehiclesCollection()
          .doc(vehicle.id)
          .update(updatedVehicle.toMap());
    } catch (e) {
      throw Exception('Failed to update vehicle: $e');
    }
  }

  // DELETE — Delete a vehicle
  Future<void> deleteVehicle(String vehicleId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _vehiclesCollection().doc(vehicleId).delete();

      // If this was the default vehicle, clear it or set another
      final defaultId = await getDefaultVehicleId();
      if (defaultId == vehicleId) {
        // Try to set the next available vehicle as default
        final remaining = await _vehiclesCollection().limit(1).get();
        if (remaining.docs.isNotEmpty) {
          await setDefaultVehicleId(remaining.docs.first.id);
        } else {
          await clearDefaultVehicleId();
        }
      }
    } catch (e) {
      throw Exception('Failed to delete vehicle: $e');
    }
  }

  // DEFAULT VEHICLE — Set
  Future<void> setDefaultVehicleId(String vehicleId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _userDoc().set({
      'defaultVehicleId': vehicleId,
    }, SetOptions(merge: true));
  }

  // DEFAULT VEHICLE — Clear
  Future<void> clearDefaultVehicleId() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _userDoc().update({'defaultVehicleId': FieldValue.delete()});
  }

  // DEFAULT VEHICLE — Get ID
  Future<String?> getDefaultVehicleId() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final doc = await _userDoc().get();
      if (!doc.exists) return null;
      return doc.data()?['defaultVehicleId'] as String?;
    } catch (e) {
      return null;
    }
  }

  // DEFAULT VEHICLE — Get ID as a stream
  Stream<String?> getDefaultVehicleIdStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _userDoc().snapshots().map((doc) {
      if (!doc.exists) return null;
      return doc.data()?['defaultVehicleId'] as String?;
    });
  }

  // DEFAULT VEHICLE — Get the full vehicle object
  Future<Vehicle?> getDefaultVehicle() async {
    final defaultId = await getDefaultVehicleId();
    if (defaultId == null) return null;
    return getVehicle(defaultId);
  }

  // DEFAULT VEHICLE — Stream of the default vehicle object
  Stream<Vehicle?> getDefaultVehicleStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _userDoc().snapshots().asyncMap((userDoc) async {
      if (!userDoc.exists) return null;
      final defaultId = userDoc.data()?['defaultVehicleId'] as String?;
      if (defaultId == null) return null;

      try {
        final vehicleDoc = await _vehiclesCollection().doc(defaultId).get();
        if (!vehicleDoc.exists) return null;
        return Vehicle.fromMap(vehicleDoc.data()!, vehicleDoc.id);
      } catch (e) {
        return null;
      }
    });
  }
}
