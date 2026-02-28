import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND handler — MUST be a top-level function (not inside any class).
// This is called when the app is in the background OR terminated.
// It runs in a separate isolate, so you can NOT use flutter UI here.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background notifications are shown automatically by the system.
  // This function is for extra processing (e.g. saving to DB).
  debugPrint('📩 [FCM Background] title: ${message.notification?.title}');
  debugPrint('📩 [FCM Background] body:  ${message.notification?.body}');
  debugPrint('📩 [FCM Background] data:  ${message.data}');
}

// ─────────────────────────────────────────────────────────────────────────────
// FCMService — handles all FCM setup and listeners.
// Call FCMService.initialize() in main() AFTER Firebase.initializeApp().
// ─────────────────────────────────────────────────────────────────────────────
class FCMService {
  FCMService._(); // private constructor — singleton pattern

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Call this once from main() after Firebase.initializeApp()
  static Future<void> initialize() async {
    // ── Step 1: Register the background handler ───────────────────────────
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // ── Step 2: Request notification permission ───────────────────────────
    final settings = await _messaging.requestPermission(
      alert: true,        // Show alert banner
      badge: true,        // Show badge on app icon
      sound: true,        // Play sound
      provisional: false, // Ask explicitly (true = quiet notifications on iOS)
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ [FCM] Notifications permission granted');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('⚠️ [FCM] Provisional notification permission granted');
    } else {
      debugPrint('❌ [FCM] Notifications permission denied');
    }

    // ── Step 3: Get & print the FCM device token ──────────────────────────
    // This token is used to send a push notification to THIS specific device.
    await _printToken();

    // Refresh token listener — token can change, always save the latest one
    _messaging.onTokenRefresh.listen((newToken) {
      debugPrint('🔄 [FCM] Token refreshed: $newToken');
      // TODO: Save newToken to your backend / Firestore if needed
    });

    // ── Step 4: Foreground notification listener ──────────────────────────
    // By default, FCM does NOT show a banner when the app is in the foreground.
    // This tells FCM to show heads-up banners, badges and sound even in foreground.
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Listen for messages while the app is open (foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('🔔 [FCM Foreground] title: ${message.notification?.title}');
      debugPrint('🔔 [FCM Foreground] body:  ${message.notification?.body}');
      debugPrint('🔔 [FCM Foreground] data:  ${message.data}');
      // The system will show the notification banner automatically
      // because we set setForegroundNotificationPresentationOptions above.
      // Optionally, you can also show a local dialog/snackbar here.
    });

    // ── Step 5: Handle notification tap when app is in background ─────────
    // Called when app is in background and user taps the notification.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('👆 [FCM Tapped from Background] title: ${message.notification?.title}');
      debugPrint('👆 [FCM Tapped from Background] data:  ${message.data}');
      // TODO: Navigate to a specific screen based on message.data
    });

    // ── Step 6: Handle notification tap when app was terminated ──────────
    // If the user tapped a notification while the app was completely closed,
    // this gives you that initial message when the app opens.
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('🚀 [FCM App Opened from Terminated] title: ${initialMessage.notification?.title}');
      debugPrint('🚀 [FCM App Opened from Terminated] data:  ${initialMessage.data}');
      // TODO: Navigate to a specific screen based on initialMessage.data
    }
  }

  /// Prints the FCM token to the console.
  /// Copy this token and use it in Firebase Console to test notifications.
  static Future<void> _printToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('─────────────────────────────────────────────');
        debugPrint('📱 [FCM] Device Token:');
        debugPrint(token);
        debugPrint('─────────────────────────────────────────────');
        debugPrint('👉 Use this token in Firebase Console to send a test notification.');
      } else {
        debugPrint('⚠️ [FCM] Token is null. Check Firebase setup.');
      }
    } catch (e) {
      debugPrint('❌ [FCM] Failed to get token: $e');
    }
  }
}
