import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_navigation_flutter/google_navigation_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A full-screen navigation experience powered by the Google Navigation SDK.
///
/// **Phase 1 – Route Preview (Aerial):**
/// Shows a top-down map with a blue polyline drawn from the user's current
/// location to the destination.  A bottom panel displays distance / ETA and
/// a prominent "Start Navigation" button.
///
/// **Phase 2 – Active Navigation:**
/// Switches to Google's native navigation UI (turn-card, speed indicator,
/// etc.) by enabling `NavigationUIEnabledPreference` and calling
/// `startGuidance()`.  A red close button in the top-right corner lets the
/// user stop and exit.
class GoogleNavScreen extends StatefulWidget {
  final double destinationLat;
  final double destinationLng;
  final String destinationName;
  final String? destinationAddress;

  /// Optional intermediate waypoints (charging stops) from the trip planner.
  /// Each map must have 'lat' (double), 'lng' (double), and 'name' (String).
  final List<Map<String, dynamic>> tripWaypoints;

  /// When true, skips the route-preview phase and starts turn-by-turn
  /// guidance immediately once the route is calculated.
  final bool autoStart;

  const GoogleNavScreen({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationName,
    this.destinationAddress,
    this.tripWaypoints = const [],
    this.autoStart = false,
  });

  @override
  State<GoogleNavScreen> createState() => _GoogleNavScreenState();
}

class _GoogleNavScreenState extends State<GoogleNavScreen>
    with TickerProviderStateMixin {
  // ─── Navigation SDK state ────────────────────────────────────────────────
  GoogleNavigationViewController? _navViewController;
  bool _isSessionInitialized = false;
  bool _isNavigating = false;
  bool _routeSet = false;
  // Guard: only treat NavState.stopped as arrival after guidance was confirmed active.
  bool _guidanceActive = false;

  // ─── UI state ────────────────────────────────────────────────────────────
  bool _isLoading = true;
  String _loadingMessage = 'Initializing Navigation…';
  String? _errorMessage;
  String _distance = '';
  String _duration = '';
  bool _isMuted = false;

  // ─── Progression tracking ────────────────────────────────────────────────
  int? _initialDistanceMeters;
  bool _routeRecorded = false;

  // ─── Animations ──────────────────────────────────────────────────────────
  late AnimationController _panelController;
  late Animation<double> _panelAnimation;

  // ─── Location ────────────────────────────────────────────────────────────
  StreamSubscription<Position>? _locationSub;

  // ─── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    // Force light status-bar icons regardless of system theme.
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    _panelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _panelAnimation = CurvedAnimation(
      parent: _panelController,
      curve: Curves.easeOutCubic,
    );

    _init();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _panelController.dispose();
    // Restore default system UI overlay so the rest of the app is unaffected.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    if (_isSessionInitialized) {
      GoogleMapsNavigator.cleanup();
    }
    super.dispose();
  }

  // ─── Initialization ──────────────────────────────────────────────────────

  Future<void> _init() async {
    // 0. Always tear down any lingering session so we start fresh in light mode.
    try {
      await GoogleMapsNavigator.cleanup();
    } catch (_) {}

    // 1. Ensure location permission is granted
    final status = await Permission.location.status;
    if (!status.isGranted) {
      await Permission.location.request();
    }

    if (!mounted) return;

    // 2. Accept T&C if needed
    setState(() => _loadingMessage = 'Checking terms & conditions…');
    try {
      if (!await GoogleMapsNavigator.areTermsAccepted()) {
        await GoogleMapsNavigator.showTermsAndConditionsDialog(
          'Navigation',
          'ChargeIQ',
        );
      }
    } catch (_) {
      // Terms dialog might fail on emulators — proceed anyway
    }

    if (!mounted) return;

    // 3. Initialize the navigation session
    setState(() => _loadingMessage = 'Starting navigation session…');
    try {
      await GoogleMapsNavigator.initializeNavigationSession(
        taskRemovedBehavior: TaskRemovedBehavior.quitService,
      );
      if (mounted) {
        setState(() {
          _isSessionInitialized = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not start navigation session.\n${e.toString()}';
        });
      }
    }
  }

  // ─── View callbacks ──────────────────────────────────────────────────────

  Future<void> _onViewCreated(GoogleNavigationViewController controller) async {
    _navViewController = controller;

    // Ensure nav UI is hidden for the preview phase
    await controller.setNavigationUIEnabled(false);
    await controller.setMyLocationEnabled(true);

    // Always force light mode on the map, regardless of the system theme.
    await controller.setMapColorScheme(MapColorScheme.light);

    // Compute route
    await _setDestinationAndPreviewRoute();
  }

  // ─── Route calculation ───────────────────────────────────────────────────

  Future<void> _setDestinationAndPreviewRoute() async {
    setState(() {
      _loadingMessage = 'Calculating route…';
      _isLoading = true;
    });

    // Build the ordered list of waypoints: intermediate trip stops first,
    // then the final destination.
    final List<NavigationWaypoint> allWaypoints = [];
    for (final stop in widget.tripWaypoints) {
      final lat = (stop['lat'] as num).toDouble();
      final lng = (stop['lng'] as num).toDouble();
      final name = stop['name']?.toString() ?? 'Stop';
      allWaypoints.add(
        NavigationWaypoint.withLatLngTarget(
          title: name,
          target: LatLng(latitude: lat, longitude: lng),
        ),
      );
    }
    // Final destination
    allWaypoints.add(
      NavigationWaypoint.withLatLngTarget(
        title: widget.destinationName,
        target: LatLng(
          latitude: widget.destinationLat,
          longitude: widget.destinationLng,
        ),
      ),
    );

    try {
      final status = await GoogleMapsNavigator.setDestinations(
        Destinations(
          waypoints: allWaypoints,
          displayOptions: NavigationDisplayOptions(
            showDestinationMarkers: true,
          ),
          routingOptions: RoutingOptions(
            travelMode: NavigationTravelMode.driving,
          ),
        ),
      );

      if (!mounted) return;

      if (status == NavigationRouteStatus.statusOk) {
        // Fetch ETA & distance
        try {
          final info = await GoogleMapsNavigator.getCurrentTimeAndDistance();
          if (mounted) {
            setState(() {
              _initialDistanceMeters = info.distance.toInt();
              _distance = _formatDistance(info.distance.toInt());
              _duration = _formatDuration(info.time.toInt());
            });
          }
        } catch (_) {
          // Fallback: leave empty — will fill in once navigation starts
        }

        // Zoom to show the full route (aerial / overview)
        await Future.delayed(const Duration(milliseconds: 400));
        try {
          await _navViewController?.showRouteOverview();
        } catch (_) {
          // showRouteOverview may not be available on all SDK versions; ignore
        }

        if (mounted) {
          setState(() {
            _routeSet = true;
            _isLoading = false;
          });
          if (widget.autoStart) {
            // Skip preview — jump straight into turn-by-turn guidance.
            await _startNavigation();
          } else {
            _panelController.forward();
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Could not calculate a route to this destination.\nPlease try again.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Route error: ${e.toString()}';
        });
      }
    }
  }

  // ─── Navigation control ──────────────────────────────────────────────────

  Future<void> _startNavigation() async {
    if (!_routeSet || _navViewController == null) return;

    // Enable Google Nav UI (turn card, speed alert, etc.)
    await _navViewController!.setNavigationUIEnabled(true);
    // Keep SDK incident report button enabled.
    await _navViewController!.setReportIncidentButtonEnabled(true);
    // Keep map in light mode after nav UI takes over
    await _navViewController!.setMapColorScheme(MapColorScheme.light);

    // Start turn-by-turn guidance
    await GoogleMapsNavigator.startGuidance();

    // Listen for arrival (NavInfo events)
    GoogleMapsNavigator.setNavInfoListener(_onNavInfo);

    if (mounted) {
      setState(() => _isNavigating = true);
    }
  }

  void _onNavInfo(NavInfoEvent event) {
    final state = event.navInfo.navState;

    // Mark guidance as truly active once we see enroute or rerouting.
    if (state == NavState.enroute || state == NavState.rerouting) {
      _guidanceActive = true;
    }

    // Check for >= 80% route completion tracking
    if (_guidanceActive && !_routeRecorded && _initialDistanceMeters != null) {
      final remaining = event.navInfo.distanceToFinalDestinationMeters;
      if (remaining != null) {
        // If remaining is <= 20% of initial distance -> 80% traversed
        if (remaining <= _initialDistanceMeters! * 0.2) {
          _routeRecorded = true;
          _incrementRoutesTaken();
        }
      }
    }

    // Update distance while navigating.
    final cur = event.navInfo.currentStep;
    if (cur != null && mounted) {
      setState(() {
        if (cur.distanceFromPrevStepMeters != null) {
          _distance = _formatDistance(cur.distanceFromPrevStepMeters!.toInt());
        }
      });
    }

    // Only treat stopped as arrival after guidance was confirmed running.
    if (state == NavState.stopped && _guidanceActive && mounted) {
      _guidanceActive = false;
      _onArrived();
    }
  }

  void _onArrived() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stopNavigation() async {
    _guidanceActive = false;
    await GoogleMapsNavigator.stopGuidance();
    await _navViewController?.setNavigationFooterEnabled(true);
    await _navViewController?.setNavigationUIEnabled(false);

    if (mounted) setState(() => _isNavigating = false);
  }

  Future<void> _toggleMute() async {
    final muted = !_isMuted;
    try {
      await GoogleMapsNavigator.setAudioGuidance(
        NavigationAudioGuidanceSettings(
          guidanceType: muted
              ? NavigationAudioGuidanceType.silent
              : NavigationAudioGuidanceType.alertsAndGuidance,
        ),
      );
    } catch (_) {
      // Ignore if the SDK version does not support audio guidance control
    }
    if (mounted) setState(() => _isMuted = muted);
  }

  Future<void> _incrementRoutesTaken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getInt('stats_routes_taken') ?? 0;
      await prefs.setInt('stats_routes_taken', current + 1);
      debugPrint('Route taken! Total routes: ${current + 1}');
    } catch (e) {
      debugPrint('Failed to save route progress: $e');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _formatDistance(int meters) {
    if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
    return '$meters m';
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '$m min';
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // ── Google Navigation View ──────────────────────────────────────
              if (_isSessionInitialized)
                GoogleMapsNavigationView(
                  onViewCreated: _onViewCreated,
                  initialNavigationUIEnabledPreference:
                      NavigationUIEnabledPreference.disabled,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      latitude: widget.destinationLat,
                      longitude: widget.destinationLng,
                    ),
                    zoom: 12,
                  ),
                  initialMapType: MapType.normal,
                  initialMapColorScheme: MapColorScheme.light,
                ),

              // ── Loading overlay ─────────────────────────────────────────────
              if (_isLoading) _buildLoadingOverlay(),

              // ── Error overlay ───────────────────────────────────────────────
              if (_errorMessage != null && !_isLoading) _buildErrorOverlay(),

              // ── Preview phase UI ────────────────────────────────────────────
              if (!_isLoading && _errorMessage == null && !_isNavigating) ...[
                _buildTopBar(),
                if (_routeSet)
                  AnimatedBuilder(
                    animation: _panelAnimation,
                    builder: (_, child) => Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Transform.translate(
                        offset: Offset(0, (1 - _panelAnimation.value) * 300),
                        child: Opacity(
                          opacity: _panelAnimation.value.clamp(0.0, 1.0),
                          child: child,
                        ),
                      ),
                    ),
                    child: _buildPreviewPanel(),
                  ),
              ],

              // ── Navigating phase UI ─────────────────────────────────────────
              if (_isNavigating) _buildNavControls(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    return const Center(
      child: SizedBox(
        width: 48,
        height: 48,
        child: CircularProgressIndicator(
          color: Color(0xFF4285F4),
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wrong_location_outlined,
                size: 56,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              const Text(
                'Navigation Unavailable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Go Back'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _errorMessage = null;
                          _isLoading = true;
                        });
                        _init();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4285F4),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Retry'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(16),
        shadowColor: Colors.black26,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Back button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 18,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Destination info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.destinationName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Color(0xFF1A1A2E),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.tripWaypoints.isNotEmpty)
                      Text(
                        'Via ${widget.tripWaypoints.length} charging stop${widget.tripWaypoints.length > 1 ? 's' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF34A853),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else if (widget.destinationAddress != null)
                      Text(
                        widget.destinationAddress!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Info chips row
              Row(
                children: [
                  _buildInfoChip(
                    Icons.route_rounded,
                    _distance.isNotEmpty ? _distance : '—',
                    const Color(0xFF4285F4),
                  ),
                  const SizedBox(width: 10),
                  _buildInfoChip(
                    Icons.access_time_filled_rounded,
                    _duration.isNotEmpty ? _duration : '—',
                    const Color(0xFFEA4335),
                  ),
                  if (widget.tripWaypoints.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    _buildInfoChip(
                      Icons.ev_station_rounded,
                      '${widget.tripWaypoints.length} Stop${widget.tripWaypoints.length > 1 ? 's' : ''}',
                      const Color(0xFF34A853),
                    ),
                  ],
                ],
              ),
              // Charging stops list
              if (widget.tripWaypoints.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 28,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.tripWaypoints.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, i) {
                      final name =
                          widget.tripWaypoints[i]['name']?.toString() ??
                          'Stop ${i + 1}';
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF34A853).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF34A853).withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.ev_station,
                              size: 12,
                              color: Color(0xFF34A853),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF34A853),
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // ── Start Navigation Button ───────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _startNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    elevation: 4,
                    shadowColor: const Color(0xFF4285F4).withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation_rounded, size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Start Navigation',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavControls() {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Positioned(
      right: 16,
      bottom: safeBottom + 160,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            elevation: 6,
            shape: const CircleBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () async {
                await _stopNavigation();
                if (mounted) Navigator.pop(context);
              },
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.red,
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Material(
            elevation: 6,
            shape: const CircleBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: _toggleMute,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _isMuted ? const Color(0xFF1A1A2E) : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: _isMuted ? Colors.white : const Color(0xFF1A1A2E),
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
