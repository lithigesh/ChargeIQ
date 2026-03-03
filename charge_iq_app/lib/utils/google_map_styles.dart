/// Shared Google Maps (google_maps_flutter) style JSON strings.
///
/// Keeping these in one place ensures MapScreen and NavigationScreen stay
/// visually identical in both light and dark modes.
const String googleMapStyleLightDecluttered = '''
[
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]}
]
''';

/// Google Night Mode map style (JSON) used across the app.
/// Includes explicit landscape/terrain rules so natural terrain areas
/// (mountains, forests, hills) do not fall back to the default teal-green.
const String googleMapStyleDarkNightMode = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d2535"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1d2535"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8899aa"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#9ab8d4"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#1d2535"}]},
  {"featureType":"landscape","elementType":"geometry.fill","stylers":[{"color":"#1d2535"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#22303f"}]},
  {"featureType":"landscape.natural","elementType":"geometry.fill","stylers":[{"color":"#22303f"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#1d2535"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#1e3040"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#1a3030"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#2e3a4e"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#18202c"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#8899aa"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3b5068"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1a2535"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0cce0"}]},
  {"featureType":"transit","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#253040"}]},
  {"featureType":"transit.station","elementType":"labels.text.fill","stylers":[{"color":"#7aaec8"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f1d2e"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d5a70"}]},
  {"featureType":"water","elementType":"labels.text.stroke","stylers":[{"color":"#0f1d2e"}]}
]
''';
