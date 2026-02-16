import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/trip_plan.dart';

class TripService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get currentUserId => _auth.currentUser?.uid;

  // Add a new trip
  Future<void> saveTrip({
    required String startLocation,
    required String destination,
    required int evRange,
    required String vehicleType,
    required String planData, // The raw JSON plan string
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User must be logged in to save a trip');
    }

    try {
      final tripRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('trips')
          .doc();

      final trip = TripPlan(
        id: tripRef.id,
        userId: user.uid,
        startLocation: startLocation,
        destination: destination,
        evRange: evRange,
        vehicleType: vehicleType,
        planData: planData,
        timestamp: DateTime.now(),
      );

      await tripRef.set(trip.toMap());
    } catch (e) {
      print('Error saving trip: $e');
      throw Exception('Failed to save trip');
    }
  }

  // Get user's trips
  Stream<List<TripPlan>> getUserTrips() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('trips')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return TripPlan.fromMap(doc.data(), doc.id);
          }).toList();
        });
  }

  // Delete a trip
  Future<void> deleteTrip(String tripId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('trips')
          .doc(tripId)
          .delete();
    } catch (e) {
      print('Error deleting trip: $e');
      throw Exception('Failed to delete trip');
    }
  }
}
