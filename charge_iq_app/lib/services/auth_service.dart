import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AuthService {
  // Singleton instance
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (!_googleInitialized && !kIsWeb) {
      await _googleSignIn.initialize();
      _googleInitialized = true;
    }
  }

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Sign in with email and password
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } on FirebaseException catch (e) {
      throw _handleFirebaseException(e);
    } catch (e) {
      throw 'Sign in failed: ${e.toString()}';
    }
  }

  // Sign up with email and password
  Future<UserCredential?> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Store user details in Firestore
      if (result.user != null) {
        await _firestore.collection('users').doc(result.user!.uid).set({
          'uid': result.user!.uid,
          'email': email,
          'fullName': fullName ?? '',
          'createdAt': FieldValue.serverTimestamp(),
          'loginType': 'email',
          'authMethod': 'email',
          'photoURL': null,
          'isGoogleLinked': false,
        });

        // Update display name
        if (fullName != null) {
          await result.user!.updateDisplayName(fullName);
        }
      }

      return result;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } on FirebaseException catch (e) {
      throw _handleFirebaseException(e);
    } catch (e) {
      throw 'Sign up failed: ${e.toString()}';
    }
  }

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      UserCredential credential;
      if (kIsWeb) {
        // For Web: Use Firebase Auth's signInWithPopup (no Client ID needed)
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        credential = await _auth.signInWithPopup(googleProvider);
      } else {
        // For Mobile: Use google_sign_in package
        await _ensureGoogleInitialized();

        // Trigger the authentication flow
        final GoogleSignInAccount googleUser = await _googleSignIn
            .authenticate();

        // Obtain the auth details from the request
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        // Create a new credential
        final OAuthCredential cred = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        // Sign in to Firebase with the Google credential
        credential = await _auth.signInWithCredential(cred);
      }

      // Store/Update user details in Firestore
      if (credential.user != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(credential.user!.uid)
            .get();

        if (!userDoc.exists) {
          await _firestore.collection('users').doc(credential.user!.uid).set({
            'uid': credential.user!.uid,
            'email': credential.user!.email,
            'fullName': credential.user!.displayName ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'loginType': 'google',
            'authMethod': 'google',
            'photoURL': credential.user!.photoURL,
            'isGoogleLinked': true,
          });
        } else {
          // Update last login or merge data if needed
          await _firestore.collection('users').doc(credential.user!.uid).update(
            {
              'lastLogin': FieldValue.serverTimestamp(),
              'isGoogleLinked': true, // Ensure this is true on Google sign-in
            },
          );
        }
      }

      return credential;
    } on GoogleSignInException catch (e) {
      throw 'Google Sign In failed: ${e.code.name}';
    } on PlatformException catch (e) {
      throw 'Google Sign In failed: ${e.message ?? e.code}';
    } catch (e) {
      throw 'Google Sign In failed: ${e.toString()}';
    }
  }

  // Link Google Account
  Future<void> linkWithGoogle() async {
    try {
      if (kIsWeb) {
        GoogleAuthProvider googleProvider = GoogleAuthProvider();
        await _auth.currentUser?.linkWithPopup(googleProvider);
      } else {
        await _ensureGoogleInitialized();
        final GoogleSignInAccount googleUser = await _googleSignIn
            .authenticate();

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;
        final OAuthCredential credential = GoogleAuthProvider.credential(
          idToken: googleAuth.idToken,
        );

        await _auth.currentUser?.linkWithCredential(credential);
      }

      // Update Firestore
      if (_auth.currentUser != null) {
        await _firestore.collection('users').doc(_auth.currentUser!.uid).update(
          {'isGoogleLinked': true},
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw 'This Google account is already linked to another user.';
      }
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Link with Google failed: ${e.toString()}';
    }
  }

  // Reset Password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      throw 'Password reset failed: ${e.toString()}';
    }
  }

  // Sign out
  Future<void> signOut() async {
    if (!kIsWeb) {
      await _ensureGoogleInitialized();
      await _googleSignIn.signOut();
    }
    await _auth.signOut();
  }

  // Handle auth exceptions
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check connection.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled.';
      case 'credential-already-in-use':
        return 'Account already linked to another user.';
      case 'provider-already-linked':
        return 'Account is already linked.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }

  // Handle general Firebase exceptions
  String _handleFirebaseException(FirebaseException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Network error. Check your internet connection.';
      default:
        return e.message ?? 'An error occurred. Please try again.';
    }
  }
}
