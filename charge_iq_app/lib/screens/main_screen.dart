import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:charge_iq_app/screens/map_screen.dart';
import 'package:charge_iq_app/screens/stations_list_screen.dart';
import 'package:charge_iq_app/screens/trip_planning_screen.dart';
import 'package:charge_iq_app/screens/profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  // Static key to access MainScreen state from anywhere
  static final GlobalKey<_MainScreenState> mainKey =
      GlobalKey<_MainScreenState>();

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  bool _fabLoading = false;

  final GlobalKey<MapScreenState> _mapKey = GlobalKey<MapScreenState>();

  late final List<Widget> _widgetOptions;

  @override
  void initState() {
    super.initState();
    _widgetOptions = <Widget>[
      MapScreen(key: _mapKey),
      const StationsListScreen(),
      const TripPlanningScreen(),
      const ProfileScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _showQuickChargeSettings() {
    final mapState = _mapKey.currentState;
    if (mapState == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Quick Charge Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Long-press the charge button to access these settings.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Use AI for Station Selection',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mapState.useAIForQuickCharge
                                  ? 'Gemini AI picks the optimal station'
                                  : 'Scoring algorithm ranks stations locally',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: mapState.useAIForQuickCharge,
                        onChanged: (val) async {
                          setSheet(() {});
                          setState(() {
                            mapState.useAIForQuickCharge = val;
                          });
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('quick_charge_use_ai', val);
                        },
                        activeColor: const Color(0xFF00D26A),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          mapState.useAIForQuickCharge
                              ? Icons.psychology_outlined
                              : Icons.calculate_outlined,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            mapState.useAIForQuickCharge
                                ? 'AI mode: Gemini analyses each station and selects the best one. Slightly slower but more accurate.'
                                : 'Score mode: Stations are ranked instantly using a weighted score of open status, rating, distance and ports.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Switch to map tab and display the given trip route
  void showRouteOnMap({
    required String startLocation,
    required String destination,
    required List<dynamic> routeSegments,
  }) {
    // Switch to map tab
    setState(() {
      _selectedIndex = 0;
    });
    // Trigger route display on map after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapKey.currentState?.showTripRoute(
        startLocation: startLocation,
        destination: destination,
        routeSegments: routeSegments,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _widgetOptions.elementAt(_selectedIndex),
        transitionBuilder: (Widget child, Animation<double> animation) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomAppBar(
          height: 80,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          clipBehavior: Clip.none,
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
                selected: _selectedIndex == 0,
                onTap: () => _onItemTapped(0),
              ),
              _NavItem(
                icon: Icons.format_list_bulleted,
                activeIcon: Icons.format_list_bulleted,
                label: 'Stations',
                selected: _selectedIndex == 1,
                onTap: () => _onItemTapped(1),
              ),
              const SizedBox(width: 48), // Space for FAB
              _NavItem(
                icon: Icons.timeline,
                activeIcon: Icons.timeline,
                label: 'Planner',
                selected: _selectedIndex == 2,
                onTap: () => _onItemTapped(2),
              ),
              _NavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
                selected: _selectedIndex == 3,
                onTap: () => _onItemTapped(3),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: MediaQuery.of(context).viewInsets.bottom != 0
          ? null
          : SizedBox(
              width: 65,
              height: 65,
              child: GestureDetector(
                onLongPress: () => _showQuickChargeSettings(),
                child: FloatingActionButton(
                  onPressed: _fabLoading
                      ? null
                      : () async {
                          setState(() => _fabLoading = true);
                          try {
                            if (_selectedIndex != 0) {
                              _onItemTapped(0);
                              await Future.delayed(
                                const Duration(milliseconds: 400),
                              );
                            }
                            if (mounted) {
                              await _mapKey.currentState?.quickCharge();
                            }
                          } finally {
                            if (mounted) setState(() => _fabLoading = false);
                          }
                        },
                  backgroundColor: const Color.fromARGB(255, 51, 155, 33),
                  elevation: 4,
                  shape: const CircleBorder(),
                  child: _fabLoading
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.bolt, size: 32, color: Colors.white),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        width: 70, // Fixed width for consistent spacing
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? const Color.fromARGB(
                        255,
                        51,
                        155,
                        33,
                      ).withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                selected ? activeIcon : icon,
                color: selected
                    ? const Color.fromARGB(255, 51, 155, 33)
                    : Colors.grey.shade500,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color.fromARGB(255, 51, 155, 33)
                    : Colors.grey.shade500,
                fontFamily: 'Roboto', // Keep consistent with theme
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
