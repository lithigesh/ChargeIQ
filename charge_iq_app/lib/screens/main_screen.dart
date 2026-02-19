import 'package:flutter/material.dart';
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
              child: FloatingActionButton(
                onPressed: () async {
                  // Quick Charge: Find and navigate to nearest EV charging station
                  if (_selectedIndex == 0) {
                    _mapKey.currentState?.quickCharge();
                  } else {
                    _onItemTapped(0);
                    await Future.delayed(const Duration(milliseconds: 500));
                    if (mounted) {
                      _mapKey.currentState?.quickCharge();
                    }
                  }
                },
                backgroundColor: const Color(0xFF00D26A),
                elevation: 4,
                shape: const CircleBorder(),
                child: const Icon(Icons.bolt, size: 32, color: Colors.white),
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
                    ? const Color(0xFF00D26A).withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                selected ? activeIcon : icon,
                color: selected
                    ? const Color(0xFF00D26A)
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
                    ? const Color(0xFF00D26A)
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
