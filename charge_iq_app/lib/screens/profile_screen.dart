import 'package:flutter/material.dart';
import 'package:charge_iq_app/widgets/app_lottie_loader.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vehicle.dart';
import '../services/auth_service.dart';
import '../services/vehicle_service.dart';
import '../utils/app_snackbar.dart';
import '../utils/theme_provider.dart';
import 'sign_in_page.dart';
import 'manage_vehicles_screen.dart';
import 'saved_locations_screen.dart';
import '../services/saved_location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final VehicleService _vehicleService = VehicleService();
  final SavedLocationService _savedLocationService = SavedLocationService();
  User? _user;
  bool _quickChargeUseAI = true;
  late final Stream<Vehicle?> _defaultVehicleStream;

  int _routesTaken = 0;
  int _stationsFound = 0;
  int _minsSaved = 0;

  static const String _aiPrefKey = 'quick_charge_use_ai';
  static const String _routesPrefKey = 'stats_routes_taken';
  static const String _stationsPrefKey = 'stats_stations_found';
  static const String _minsPrefKey = 'stats_mins_saved';

  // ── Theme helpers ────────────────────────────────────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _cardColor => _isDark ? const Color(0xFF1E1E1E) : Colors.white;
  Color get _bgColor =>
      _isDark ? const Color(0xFF121212) : const Color(0xFFF8F9FE);
  Color get _textPrimary => _isDark ? Colors.white : Colors.black87;
  Color get _textSecondary => _isDark ? Colors.grey[400]! : Colors.grey[600]!;
  Color get _textHint => _isDark ? Colors.grey[500]! : Colors.grey[500]!;
  Color get _dividerColor =>
      _isDark ? const Color(0xFF2C2C2C) : Colors.grey[200]!;
  Color get _borderColor =>
      _isDark ? Colors.grey[800]! : Colors.grey.shade100;
  Color get _iconBgColor =>
      _isDark ? const Color(0xFF1A3A36) : const Color(0xFFE0F2F1);
  Color get _statBgColor =>
      _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FE);
  Color get _progressBgColor =>
      _isDark ? const Color(0xFF333333) : Colors.grey[200]!;

  @override
  void initState() {
    super.initState();
    _user = _authService.currentUser;
    _defaultVehicleStream = _vehicleService.getDefaultVehicleStream();
    _loadAIPref();
  }

  Future<void> _loadAIPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _quickChargeUseAI = prefs.getBool(_aiPrefKey) ?? true;
      _routesTaken = prefs.getInt(_routesPrefKey) ?? 0;
      _stationsFound = prefs.getInt(_stationsPrefKey) ?? 0;
      _minsSaved = prefs.getInt(_minsPrefKey) ?? 0;
    });
  }

  Future<void> _saveAIPref(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiPrefKey, value);
  }

  Future<void> _signOut() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const SignInPage()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Error signing out: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 35,
                      backgroundColor: Colors.white,
                      backgroundImage: _user?.photoURL != null
                          ? NetworkImage(_user!.photoURL!)
                          : null,
                      child: _user?.photoURL == null
                          ? const Icon(
                              Icons.person_outline,
                              size: 40,
                              color: Colors.blue,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _user?.displayName ?? 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _user?.email ?? '',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Theme mode popup in header
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: AppTheme.themeNotifier,
                    builder: (context, mode, _) {
                      final headerIcon = switch (mode) {
                        ThemeMode.dark => Icons.dark_mode,
                        ThemeMode.light => Icons.light_mode,
                        _ => Icons.brightness_auto,
                      };
                      final popupIsDark =
                          Theme.of(context).brightness == Brightness.dark;
                      return PopupMenuButton<ThemeMode>(
                        onSelected: AppTheme.setThemeMode,
                        initialValue: mode,
                        color: popupIsDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        offset: const Offset(0, 44),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: ThemeMode.light,
                            child: Row(
                              children: [
                                const Icon(Icons.light_mode,
                                    size: 18, color: Color(0xFFF9A825)),
                                const SizedBox(width: 10),
                                Text('Light',
                                    style: TextStyle(
                                        color: popupIsDark
                                            ? Colors.white
                                            : Colors.black87)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ThemeMode.system,
                            child: Row(
                              children: [
                                const Icon(Icons.brightness_auto,
                                    size: 18, color: Color(0xFF7E57C2)),
                                const SizedBox(width: 10),
                                Text('System',
                                    style: TextStyle(
                                        color: popupIsDark
                                            ? Colors.white
                                            : Colors.black87)),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: ThemeMode.dark,
                            child: Row(
                              children: [
                                const Icon(Icons.dark_mode,
                                    size: 18, color: Color(0xFF5C6BC0)),
                                const SizedBox(width: 10),
                                Text('Dark',
                                    style: TextStyle(
                                        color: popupIsDark
                                            ? Colors.white
                                            : Colors.black87)),
                              ],
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            headerIcon,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Stats Row
            Transform.translate(
              offset: const Offset(0, -25),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 15,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildStatItem(
                        '$_routesTaken',
                        'Routes Taken',
                        Icons.alt_route,
                        const Color(0xFF00D26A),
                      ),
                      Container(width: 1, height: 40, color: _dividerColor),
                      _buildStatItem(
                        '$_stationsFound',
                        'Stations Found',
                        Icons.ev_station,
                        const Color(0xFF1565C0),
                      ),
                      Container(width: 1, height: 40, color: _dividerColor),
                      _buildStatItem(
                        '$_minsSaved',
                        'Mins Saved',
                        Icons.timer,
                        const Color(0xFF7E57C2),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'My Vehicle',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _textPrimary,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const ManageVehiclesScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.chevron_right),
                        color: _textSecondary,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        splashRadius: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Default Vehicle Card — Dynamic
                  _buildDefaultVehicleCard(),

                  const SizedBox(height: 24),

                  // (Recent Activity section removed)
                  const SizedBox(height: 24),

                  Text(
                    'Settings',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Theme mode selector
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: AppTheme.themeNotifier,
                    builder: (context, mode, _) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _isDark
                                    ? const Color(0xFF2A1F3D)
                                    : const Color(0xFFEDE7F6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                switch (mode) {
                                  ThemeMode.dark => Icons.dark_mode,
                                  ThemeMode.light => Icons.light_mode,
                                  _ => Icons.brightness_auto,
                                },
                                color: const Color(0xFF7E57C2),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Appearance',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: _textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    switch (mode) {
                                      ThemeMode.dark => 'Dark theme',
                                      ThemeMode.light => 'Light theme',
                                      _ => 'Follows system',
                                    },
                                    style: TextStyle(
                                        fontSize: 11, color: _textHint),
                                  ),
                                ],
                              ),
                            ),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<ThemeMode>(
                                value: mode,
                                isDense: true,
                                dropdownColor: _isDark
                                    ? const Color(0xFF2A2A2A)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: _textSecondary,
                                  size: 18,
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: ThemeMode.light,
                                    child: Row(children: [
                                      const Icon(Icons.light_mode,
                                          size: 15,
                                          color: Color(0xFFF9A825)),
                                      const SizedBox(width: 8),
                                      Text('Light',
                                          style: TextStyle(
                                              color: _textPrimary,
                                              fontSize: 13)),
                                    ]),
                                  ),
                                  DropdownMenuItem(
                                    value: ThemeMode.system,
                                    child: Row(children: [
                                      const Icon(Icons.brightness_auto,
                                          size: 15,
                                          color: Color(0xFF7E57C2)),
                                      const SizedBox(width: 8),
                                      Text('System',
                                          style: TextStyle(
                                              color: _textPrimary,
                                              fontSize: 13)),
                                    ]),
                                  ),
                                  DropdownMenuItem(
                                    value: ThemeMode.dark,
                                    child: Row(children: [
                                      const Icon(Icons.dark_mode,
                                          size: 15,
                                          color: Color(0xFF5C6BC0)),
                                      const SizedBox(width: 8),
                                      Text('Dark',
                                          style: TextStyle(
                                              color: _textPrimary,
                                              fontSize: 13)),
                                    ]),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v != null) AppTheme.setThemeMode(v);
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // AI for Quick Charge toggle
                  _buildToggleItem(
                    title: 'AI for Quick Charge',
                    subtitle: _quickChargeUseAI
                        ? 'Gemini AI picks the best station'
                        : 'Scoring algorithm used instead',
                    icon: Icons.psychology_outlined,
                    value: _quickChargeUseAI,
                    onChanged: (val) async {
                      setState(() => _quickChargeUseAI = val);
                      await _saveAIPref(val);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).clearSnackBars();
                        AppSnackBar.info(
                          context,
                          val
                              ? 'AI station selection enabled'
                              : 'Scoring algorithm enabled',
                          icon: val
                              ? Icons.psychology_outlined
                              : Icons.calculate_outlined,
                        );
                      }
                    },
                    activeColor: const Color(0xFF00D26A),
                    iconBgColor: _iconBgColor,
                    iconColor: const Color(0xFF00D26A),
                  ),

                  // _buildSettingItem(
                  //   'Payment Methods',
                  //   Icons.payment,
                  //   badgeCount: 2,
                  // ),
                  StreamBuilder<QuerySnapshot>(
                    stream: _savedLocationService.getSavedStationsStream(),
                    builder: (context, snapshot) {
                      int? count;
                      if (snapshot.hasData) {
                        count = snapshot.data!.docs.length;
                        if (count == 0) count = null; // Don't show badge if 0
                      }

                      return _buildSettingItem(
                        'Saved Locations',
                        Icons.bookmark_border,
                        badgeCount: count,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SavedLocationsScreen(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (!(_user?.providerData.any(
                        (p) => p.providerId == 'google.com',
                      ) ??
                      false))
                    _buildSettingItem(
                      'Link Google Account',
                      Icons.link,
                      onTap: () async {
                        try {
                          await _authService.linkWithGoogle();
                          await _user?.reload();
                          setState(() {
                            _user = _authService.currentUser;
                          });
                          if (mounted) {
                            AppSnackBar.success(
                              context,
                              'Google account linked successfully!',
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            AppSnackBar.error(context, e.toString());
                          }
                        }
                      },
                    ),
                  if (_user?.email != null)
                    _buildSettingItem(
                      'Reset Password',
                      Icons.lock_outline,
                      onTap: () {
                        final cardColor = _cardColor;
                        final textPrimary = _textPrimary;
                        final textSecondary = _textSecondary;
                        showDialog(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            backgroundColor: cardColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: Text(
                              'Reset Password',
                              style: TextStyle(color: textPrimary),
                            ),
                            content: Text(
                              'Send a password reset email to ${_user!.email}?',
                              style: TextStyle(color: textSecondary),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(color: textSecondary),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  Navigator.pop(dialogContext);
                                  try {
                                    await _authService.resetPassword(
                                      _user!.email!,
                                    );
                                    if (mounted) {
                                      AppSnackBar.success(
                                        context,
                                        'Password reset link sent to ${_user!.email}!',
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      AppSnackBar.error(context, e.toString());
                                    }
                                  }
                                },
                                child: const Text(
                                  'Send Link',
                                  style: TextStyle(
                                    color: Color(0xFF1565C0),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  _buildSettingItem(
                    'Log Out',
                    Icons.logout,
                    isLogout: true,
                    onTap: _signOut,
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultVehicleCard() {
    return StreamBuilder<Vehicle?>(
      stream: _defaultVehicleStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: AppLottieLoader(strokeWidth: 2),
              ),
            ),
          );
        }

        final vehicle = snapshot.data;

        if (vehicle == null) {
          return _buildNoVehicleCard();
        }

        return _buildVehicleCardContent(vehicle);
      },
    );
  }

  Widget _buildNoVehicleCard() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const ManageVehiclesScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _borderColor,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1565C0).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_outlined,
                size: 32,
                color: Color(0xFF1565C0),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No vehicle added yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to add your first EV',
              style: TextStyle(fontSize: 13, color: _textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleCardContent(Vehicle vehicle) {
    IconData vehicleIcon;
    switch (vehicle.vehicleType) {
      case '2 Wheeler':
        vehicleIcon = Icons.two_wheeler;
        break;
      case '3 Wheeler':
        vehicleIcon = Icons.electric_rickshaw;
        break;
      case 'Bus':
        vehicleIcon = Icons.directions_bus;
        break;
      default:
        vehicleIcon = Icons.directions_car;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF263238),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(vehicleIcon, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vehicle.brand} ${vehicle.model}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      vehicle.variant.isNotEmpty
                          ? vehicle.variant
                          : vehicle.vehicleType,
                      style: TextStyle(fontSize: 14, color: _textSecondary),
                    ),
                  ],
                ),
              ),
              // Default badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 12, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text(
                      'Default',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Vehicle stats row
          Row(
            children: [
              _buildVehicleStat(
                Icons.battery_charging_full,
                '${vehicle.batteryCapacity.toStringAsFixed(0)} kWh',
                'Battery',
              ),
              const SizedBox(width: 16),
              _buildVehicleStat(
                Icons.speed,
                '${vehicle.maxRange.toStringAsFixed(0)} km',
                'Range',
              ),
              const SizedBox(width: 16),
              _buildVehicleStat(
                Icons.electrical_services,
                vehicle.chargingPortType,
                'Port',
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Charge-to percentage bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Charge Limit',
                style: TextStyle(color: _textSecondary),
              ),
              Text(
                '${vehicle.stopChargingAtPercent}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: vehicle.stopChargingAtPercent / 100,
              backgroundColor: _progressBgColor,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF00D26A),
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Driving: ${vehicle.drivingStyle}',
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
              Text(
                vehicle.homeChargingAvailable
                    ? '🏠 Home charging'
                    : 'No home charging',
                style: TextStyle(
                  fontSize: 12,
                  color: vehicle.homeChargingAvailable
                      ? const Color(0xFF00D26A)
                      : _textSecondary,
                  fontWeight: vehicle.homeChargingAvailable
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleStat(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: _statBgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF1565C0)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: _textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: _textSecondary),
        ),
      ],
    );
  }

  /// A row toggle for boolean settings (Dark Mode, AI, etc.)
  Widget _buildToggleItem({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
    required Color iconBgColor,
    required Color iconColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: _textHint),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: activeColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(
    String title,
    IconData icon, {
    int? badgeCount,
    bool isLogout = false,
    VoidCallback? onTap,
  }) {
    final Color itemBg = isLogout
        ? (_isDark ? const Color(0xFF3E1515) : const Color(0xFFFFEBEE))
        : _cardColor;
    final Color borderCol = isLogout
        ? (_isDark ? const Color(0xFF7B1A1A) : Colors.red.shade100)
        : _borderColor;
    final Color iconBg = isLogout
        ? (_isDark ? const Color(0xFF5C2020) : Colors.white)
        : _iconBgColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: itemBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: isLogout ? Colors.red : const Color(0xFF00D26A),
            size: 20,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isLogout ? Colors.red : _textPrimary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFF00D26A),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  badgeCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            Icon(
              Icons.chevron_right,
              color: isLogout ? Colors.red.shade300 : _textSecondary,
              size: 20,
            ),
          ],
        ),
        onTap: onTap ?? () {},
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

