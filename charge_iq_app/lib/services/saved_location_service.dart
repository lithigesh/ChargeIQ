import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class SavedLocationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Returns a stream of saved station documents for the current user
  Stream<QuerySnapshot> getSavedStationsStream() {
    final user = _auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('saved_locations')
        .snapshots();
  }

  // Future to get saved station IDs for initial load
  Future<Set<String>> getSavedStationIds() async {
    final user = _auth.currentUser;
    if (user == null) return {};

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('saved_locations')
          .get();
      return snapshot.docs.map((doc) => doc.id).toSet();
    } catch (e) {
      debugPrint('Error getting saved stations: $e');
      return {};
    }
  }

  // Check if a station is saved
  Future<bool> isStationSaved(String stationId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('saved_locations')
          .doc(stationId)
          .get();
      return doc.exists;
    } catch (e) {
      debugPrint('Error checking saved station: $e');
      return false;
    }
  }

  // Toggle saved status
  Future<bool> toggleSavedStation(Map<String, dynamic> station) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final stationId = station['id'];
    if (stationId == null) return false;

    final docRef = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('saved_locations')
        .doc(stationId.toString());

    try {
      final doc = await docRef.get();
      if (doc.exists) {
        // Remove it
        await docRef.delete();
        return false; // Result is unsaved
      } else {
        // Save it
        await docRef.set({
          'id': stationId,
          'name': station['name'] ?? 'Unknown Station',
          'lat': station['lat'],
          'lng': station['lng'],
          'vicinity': station['vicinity'] ?? '',
          'rating': station['rating'] ?? 0.0,
          'userRatingsTotal': station['userRatingsTotal'] ?? 0,
          'savedAt': FieldValue.serverTimestamp(),
        });
        return true; // Result is saved
      }
    } catch (e) {
      debugPrint('Error toggling saved station: $e');
      return false;
    }
  }

  // Optional: remove by ID directly
  Future<void> removeStation(String stationId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('saved_locations')
          .doc(stationId)
          .delete();
    } catch (e) {
      debugPrint('Error removing saved station: $e');
    }
  }
}
