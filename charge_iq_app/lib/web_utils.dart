import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void injectMapsScript() {
  final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
  if (apiKey != null && apiKey.isNotEmpty) {
    if (html.document.querySelector('script[src*="maps.googleapis.com"]') ==
        null) {
      final script = html.ScriptElement()
        ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey'
        ..async = true;
      html.document.head?.append(script);
    }
  } else {
    debugPrint('WARNING: Google Maps API key not found in .env');
  }
}
