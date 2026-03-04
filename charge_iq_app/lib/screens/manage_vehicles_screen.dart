import 'package:flutter/material.dart';
import 'package:charge_iq_app/widgets/app_lottie_loader.dart';
import '../models/vehicle.dart';
import '../services/vehicle_service.dart';
import '../utils/app_snackbar.dart';

// helper used across both screens in this file
bool _isDarkCtx(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

class ManageVehiclesScreen extends StatefulWidget {
  const ManageVehiclesScreen({super.key});

  @override
  State<ManageVehiclesScreen> createState() => _ManageVehiclesScreenState();
}

class _ManageVehiclesScreenState extends State<ManageVehiclesScreen> {
  final VehicleService _vehicleService = VehicleService();

  @override
  Widget build(BuildContext context) {
    final isDark = _isDarkCtx(context);
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FE),
      body: Column(
        children: [
          // ── Header matching profile / planner pages ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button row
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'My Vehicles',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Manage & track your EVs',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // ── Body ──
          Expanded(
            child: StreamBuilder<String?>(
              stream: _vehicleService.getDefaultVehicleIdStream(),
              builder: (context, defaultSnapshot) {
                final defaultVehicleId = defaultSnapshot.data;

                return StreamBuilder<List<Vehicle>>(
                  stream: _vehicleService.getUserVehicles(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: AppLottieLoader(color: Color(0xFF10B981)),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.redAccent,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Failed to load vehicles',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final vehicles = snapshot.data ?? [];

                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: vehicles.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF1565C0,
                                            ).withValues(alpha: 0.08),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.directions_car_outlined,
                                            size: 56,
                                            color: Color(0xFF1565C0),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'No vehicles added yet',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Add your EV to unlock smart features\nlike range prediction & trip planning',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color:
                                                Colors.grey[isDark ? 400 : 500],
                                            height: 1.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: vehicles.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) =>
                                        _buildVehicleCard(
                                          vehicles[index],
                                          defaultVehicleId,
                                          isDark,
                                        ),
                                  ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _navigateToForm(),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Vehicle'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleCard(
    Vehicle vehicle,
    String? defaultVehicleId,
    bool isDark,
  ) {
    final isDefault = vehicle.id == defaultVehicleId;
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isDefault
            ? Border.all(color: const Color(0xFF10B981), width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF263238), Color(0xFF37474F)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(vehicleIcon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${vehicle.brand} ${vehicle.model}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (vehicle.variant.isNotEmpty) vehicle.variant,
                        vehicle.vehicleType,
                        '${vehicle.manufacturingYear}',
                      ].join(' • '),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[isDark ? 400 : 600],
                      ),
                    ),
                  ],
                ),
              ),
              if (isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: Colors.grey[600], size: 22),
                onSelected: (value) {
                  if (value == 'edit') {
                    _navigateToForm(vehicle: vehicle);
                  } else if (value == 'delete') {
                    _confirmDelete(vehicle);
                  } else if (value == 'view') {
                    _showVehicleDetails(vehicle);
                  } else if (value == 'default') {
                    _setAsDefault(vehicle);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'view',
                    child: Row(
                      children: [
                        Icon(Icons.visibility_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('View Details'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 20),
                        SizedBox(width: 8),
                        Text('Edit'),
                      ],
                    ),
                  ),
                  if (!isDefault)
                    const PopupMenuItem(
                      value: 'default',
                      child: Row(
                        children: [
                          Icon(
                            Icons.star_outline,
                            size: 20,
                            color: Color(0xFF10B981),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Set as Default',
                            style: TextStyle(color: Color(0xFF10B981)),
                          ),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Delete',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Battery & Range quick info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickStat(
                  Icons.battery_charging_full,
                  '${vehicle.batteryCapacity} kWh',
                  'Battery',
                  const Color(0xFF10B981),
                  isDark,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                ),
                _buildQuickStat(
                  Icons.route,
                  '${vehicle.maxRange} km',
                  'Range',
                  const Color(0xFF1565C0),
                  isDark,
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                ),
                _buildQuickStat(
                  Icons.ev_station,
                  vehicle.chargingPortType,
                  'Port',
                  const Color(0xFFE65100),
                  isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat(
    IconData icon,
    String value,
    String label,
    Color color,
    bool isDark,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[isDark ? 400 : 500],
          ),
        ),
      ],
    );
  }

  void _setAsDefault(Vehicle vehicle) async {
    try {
      await _vehicleService.setDefaultVehicleId(vehicle.id);
      if (mounted) {
        AppSnackBar.success(
          context,
          '${vehicle.brand} ${vehicle.model} set as default',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Failed to set default: $e');
      }
    }
  }

  void _navigateToForm({Vehicle? vehicle}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VehicleFormScreen(vehicle: vehicle)),
    );
  }

  void _confirmDelete(Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Vehicle'),
        content: Text(
          'Are you sure you want to delete "${vehicle.brand} ${vehicle.model}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              try {
                await _vehicleService.deleteVehicle(vehicle.id);
                if (mounted) {
                  scaffoldMessenger.clearSnackBars();
                  AppSnackBar.info(context, 'Vehicle deleted');
                }
              } catch (e) {
                if (mounted) {
                  AppSnackBar.error(context, 'Failed to delete: $e');
                }
              }
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showVehicleDetails(Vehicle vehicle) {
    final isDark = _isDarkCtx(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
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
              const SizedBox(height: 20),
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.directions_car,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${vehicle.brand} ${vehicle.model}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (vehicle.variant.isNotEmpty)
                          Text(
                            vehicle.variant,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[isDark ? 400 : 600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Vehicle Info Section
              _buildDetailSection('🚗 Vehicle Info', [
                _buildDetailRow('Type', vehicle.vehicleType),
                _buildDetailRow('Year', '${vehicle.manufacturingYear}'),
                if (vehicle.registrationNumber.isNotEmpty)
                  _buildDetailRow('Registration', vehicle.registrationNumber),
              ]),
              const SizedBox(height: 16),

              // Battery & Range Section
              _buildDetailSection('🔋 Battery & Range', [
                _buildDetailRow(
                  'Battery Capacity',
                  '${vehicle.batteryCapacity} kWh',
                ),
                _buildDetailRow('Max Range', '${vehicle.maxRange} km'),
                _buildDetailRow('Charging Port', vehicle.chargingPortType),
                _buildDetailRow(
                  'Max AC Power',
                  '${vehicle.maxACChargingPower} kW',
                ),
                _buildDetailRow(
                  'Max DC Power',
                  '${vehicle.maxDCFastChargingPower} kW',
                ),
              ]),
              const SizedBox(height: 16),

              // Smart Settings Section
              _buildDetailSection('⚡ Smart Settings', [
                _buildDetailRow('Driving Style', vehicle.drivingStyle),
                _buildDetailRow(
                  'AC Usage',
                  vehicle.acUsageUsually ? 'Yes' : 'No',
                ),
                if (vehicle.batteryHealthPercent != null)
                  _buildDetailRow(
                    'Battery Health',
                    '${vehicle.batteryHealthPercent}%',
                  ),
                _buildDetailRow(
                  'Preferred Charging',
                  vehicle.preferredChargingType,
                ),
                _buildDetailRow(
                  'Stop Charging At',
                  '${vehicle.stopChargingAtPercent}%',
                ),
                _buildDetailRow(
                  'Home Charging',
                  vehicle.homeChargingAvailable ? 'Yes' : 'No',
                ),
              ]),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailSection(String title, List<Widget> children) {
    final isDark = _isDarkCtx(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final isDark = _isDarkCtx(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[isDark ? 400 : 600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VEHICLE FORM SCREEN — Add / Edit
// ─────────────────────────────────────────────────────────────────────────────

class VehicleFormScreen extends StatefulWidget {
  final Vehicle? vehicle;

  const VehicleFormScreen({super.key, this.vehicle});

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final VehicleService _vehicleService = VehicleService();
  bool _isLoading = false;

  // ── Section 1: Vehicle Info ──
  String _brand = 'Tata';
  final TextEditingController _modelController = TextEditingController();
  String _variant = '';
  String _vehicleType = 'Car';
  int _manufacturingYear = DateTime.now().year;
  final TextEditingController _registrationController = TextEditingController();

  // ── Section 2: Battery & Range ──
  final TextEditingController _batteryCapacityController =
      TextEditingController();
  final TextEditingController _maxRangeController = TextEditingController();
  String _chargingPortType = 'CCS2';
  double _maxACPower = 7.2;
  double _maxDCPower = 50;

  // ── Section 3: Smart Settings ──
  String _drivingStyle = 'Normal';
  bool _acUsageUsually = false;
  final TextEditingController _batteryHealthController =
      TextEditingController();
  String _preferredChargingType = 'Fast';
  int _stopChargingAt = 80;
  bool _homeChargingAvailable = false;

  // ── Dropdown lists ──
  static const List<String> _brands = [
    'Tata',
    'MG',
    'Tesla',
    'Hyundai',
    'BYD',
    'Mahindra',
    'Ola',
    'Ather',
    'Other',
  ];

  static const List<String> _vehicleTypes = [
    '2 Wheeler',
    '3 Wheeler',
    'Car',
    'Bus',
  ];

  static const List<String> _chargingPorts = [
    'Type 2',
    'CCS2',
    'CHAdeMO',
    'GB/T',
  ];

  static const List<double> _acPowerOptions = [3.3, 7.2, 11, 22];
  static const List<double> _dcPowerOptions = [25, 50, 60, 120, 150];

  static const List<String> _drivingStyles = ['Eco', 'Normal', 'Sport'];
  static const List<String> _chargingPreferences = ['Fast', 'Cheap', 'Nearby'];

  bool get _isEditing => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final v = widget.vehicle!;
      _brand = _brands.contains(v.brand) ? v.brand : 'Other';
      _modelController.text = v.model;
      _variant = v.variant;
      _vehicleType = v.vehicleType;
      _manufacturingYear = v.manufacturingYear;
      _registrationController.text = v.registrationNumber;

      _batteryCapacityController.text = v.batteryCapacity.toString();
      _maxRangeController.text = v.maxRange.toString();
      _chargingPortType = v.chargingPortType;
      _maxACPower = v.maxACChargingPower;
      _maxDCPower = v.maxDCFastChargingPower;

      _drivingStyle = v.drivingStyle;
      _acUsageUsually = v.acUsageUsually;
      if (v.batteryHealthPercent != null) {
        _batteryHealthController.text = v.batteryHealthPercent.toString();
      }
      _preferredChargingType = v.preferredChargingType;
      _stopChargingAt = v.stopChargingAtPercent;
      _homeChargingAvailable = v.homeChargingAvailable;
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    _registrationController.dispose();
    _batteryCapacityController.dispose();
    _maxRangeController.dispose();
    _batteryHealthController.dispose();
    super.dispose();
  }

  Future<void> _saveVehicle() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final vehicle = Vehicle(
        id: _isEditing ? widget.vehicle!.id : '',
        userId: '',
        brand: _brand,
        model: _modelController.text.trim(),
        variant: _variant,
        vehicleType: _vehicleType,
        manufacturingYear: _manufacturingYear,
        registrationNumber: _registrationController.text.trim(),
        batteryCapacity:
            double.tryParse(_batteryCapacityController.text.trim()) ?? 0,
        maxRange: double.tryParse(_maxRangeController.text.trim()) ?? 0,
        chargingPortType: _chargingPortType,
        maxACChargingPower: _maxACPower,
        maxDCFastChargingPower: _maxDCPower,
        drivingStyle: _drivingStyle,
        acUsageUsually: _acUsageUsually,
        batteryHealthPercent: double.tryParse(
          _batteryHealthController.text.trim(),
        ),
        preferredChargingType: _preferredChargingType,
        stopChargingAtPercent: _stopChargingAt,
        homeChargingAvailable: _homeChargingAvailable,
        createdAt: _isEditing ? widget.vehicle!.createdAt : DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (_isEditing) {
        await _vehicleService.updateVehicle(vehicle);
      } else {
        await _vehicleService.addVehicle(vehicle);
      }

      if (mounted) {
        AppSnackBar.success(
          context,
          _isEditing ? 'Vehicle updated!' : 'Vehicle added!',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'Error: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDarkCtx(context);
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF8F9FE),
      body: Column(
        children: [
          // ── Header matching profile / planner pages ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isEditing ? 'Edit Vehicle' : 'Add Vehicle',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isEditing
                      ? 'Update your EV details below'
                      : 'Fill in your EV details to get started',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          // ── Form Body ──
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ━━━ Section 1: Vehicle Info ━━━
                  _buildSectionHeader(
                    Icons.directions_car_filled,
                    'Vehicle Information',
                    'Basic details about your EV',
                    const Color(0xFF1565C0),
                  ),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildDropdown(
                      label: 'Vehicle Brand',
                      value: _brand,
                      items: _brands,
                      onChanged: (v) => setState(() => _brand = v!),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _modelController,
                      decoration: _inputDecoration(
                        label: 'Vehicle Model',
                        hint: 'e.g., Nexon EV, ZS EV, Kona',
                        icon: Icons.directions_car_outlined,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Model is required'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: _variant,
                      decoration: _inputDecoration(
                        label: 'Variant (Optional)',
                        hint: 'e.g., Long Range, Prime, Base',
                        icon: Icons.style_outlined,
                      ),
                      onChanged: (v) => _variant = v.trim(),
                    ),
                    const SizedBox(height: 14),
                    _buildDropdown(
                      label: 'Vehicle Type',
                      value: _vehicleType,
                      items: _vehicleTypes,
                      onChanged: (v) => setState(() => _vehicleType = v!),
                    ),
                    const SizedBox(height: 14),
                    _buildDropdown(
                      label: 'Manufacturing Year',
                      value: _manufacturingYear.toString(),
                      items: List.generate(
                        15,
                        (i) => (DateTime.now().year - i).toString(),
                      ),
                      onChanged: (v) =>
                          setState(() => _manufacturingYear = int.parse(v!)),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _registrationController,
                      decoration: _inputDecoration(
                        label: 'Registration Number (Optional)',
                        hint: 'e.g., KA 01 AB 1234',
                        icon: Icons.confirmation_number_outlined,
                      ),
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ━━━ Section 2: Battery & Range ━━━
                  _buildSectionHeader(
                    Icons.battery_charging_full,
                    'Battery & Range',
                    'Enable smart features like range prediction',
                    const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 12),
                  _buildCard([
                    TextFormField(
                      controller: _batteryCapacityController,
                      decoration: _inputDecoration(
                        label: 'Battery Capacity (kWh)',
                        hint: 'e.g., 30.2',
                        icon: Icons.battery_full,
                        suffix: 'kWh',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Battery capacity is required';
                        }
                        if (double.tryParse(v.trim()) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _maxRangeController,
                      decoration: _inputDecoration(
                        label: 'Max Range (km)',
                        hint: 'e.g., 312',
                        icon: Icons.route,
                        suffix: 'km',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Max range is required';
                        }
                        if (double.tryParse(v.trim()) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildDropdown(
                      label: 'Charging Port Type',
                      value: _chargingPortType,
                      items: _chargingPorts,
                      onChanged: (v) => setState(() => _chargingPortType = v!),
                    ),
                    const SizedBox(height: 14),
                    _buildDropdown(
                      label: 'Max AC Charging Power (kW)',
                      value: _acPowerOptions.contains(_maxACPower)
                          ? _maxACPower.toString()
                          : _acPowerOptions.first.toString(),
                      items: _acPowerOptions.map((e) => e.toString()).toList(),
                      onChanged: (v) =>
                          setState(() => _maxACPower = double.parse(v!)),
                    ),
                    const SizedBox(height: 14),
                    _buildDropdown(
                      label: 'Max DC Fast Charging Power (kW)',
                      value: _dcPowerOptions.contains(_maxDCPower)
                          ? _maxDCPower.toString()
                          : _dcPowerOptions.first.toString(),
                      items: _dcPowerOptions.map((e) => e.toString()).toList(),
                      onChanged: (v) =>
                          setState(() => _maxDCPower = double.parse(v!)),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // ━━━ Section 3: Smart Settings ━━━
                  _buildSectionHeader(
                    Icons.auto_awesome,
                    'Smart Settings',
                    'Optional but powerful for personalization',
                    const Color(0xFFE65100),
                  ),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildDropdown(
                      label: 'Driving Style',
                      value: _drivingStyle,
                      items: _drivingStyles,
                      onChanged: (v) => setState(() => _drivingStyle = v!),
                    ),
                    const SizedBox(height: 14),
                    _buildToggleRow(
                      'AC Usage Usually?',
                      _acUsageUsually,
                      (v) => setState(() => _acUsageUsually = v),
                      icon: Icons.ac_unit,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _batteryHealthController,
                      decoration: _inputDecoration(
                        label: 'Battery Health % (Optional)',
                        hint: 'e.g., 95',
                        icon: Icons.health_and_safety_outlined,
                        suffix: '%',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (v) {
                        if (v != null && v.trim().isNotEmpty) {
                          final val = double.tryParse(v.trim());
                          if (val == null || val < 0 || val > 100) {
                            return 'Enter a value between 0 and 100';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _buildDropdown(
                      label: 'Preferred Charging Type',
                      value: _preferredChargingType,
                      items: _chargingPreferences,
                      onChanged: (v) =>
                          setState(() => _preferredChargingType = v!),
                    ),
                    const SizedBox(height: 18),
                    // Stop Charging At % Slider
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Stop Charging At',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.grey[700],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$_stopChargingAt%',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF10B981),
                            inactiveTrackColor: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.2),
                            thumbColor: const Color(0xFF10B981),
                            overlayColor: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.15),
                            trackHeight: 6,
                          ),
                          child: Slider(
                            value: _stopChargingAt.toDouble(),
                            min: 50,
                            max: 100,
                            divisions: 10,
                            label: '$_stopChargingAt%',
                            onChanged: (v) =>
                                setState(() => _stopChargingAt = v.toInt()),
                          ),
                        ),
                        Text(
                          '80% recommended for battery longevity',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[isDark ? 400 : 500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildToggleRow(
                      'Home Charging Available?',
                      _homeChargingAvailable,
                      (v) => setState(() => _homeChargingAvailable = v),
                      icon: Icons.home_outlined,
                    ),
                  ]),

                  const SizedBox(height: 32),

                  // ━━━ Submit Button ━━━
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveVehicle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        disabledBackgroundColor: const Color(
                          0xFF10B981,
                        ).withValues(alpha: 0.5),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: AppLottieLoader(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEditing ? 'Save Changes' : 'Add Vehicle',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helper Widgets ──

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
    String? suffix,
  }) {
    final isDark = _isDarkCtx(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      prefixIcon: Container(
        margin: const EdgeInsets.only(left: 12, right: 8),
        child: Icon(
          icon,
          size: 20,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      filled: true,
      fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget _buildSectionHeader(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    final isDark = _isDarkCtx(context);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[isDark ? 400 : 500],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    final isDark = _isDarkCtx(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF2C2C2C) : Colors.grey.shade100,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = _isDarkCtx(context);
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FE),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
      isExpanded: true,
    );
  }

  Widget _buildToggleRow(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    IconData? icon,
  }) {
    final isDark = _isDarkCtx(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: value
                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                    : (isDark ? const Color(0xFF333333) : Colors.grey.shade100),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: value
                    ? const Color(0xFF10B981)
                    : Colors.grey[isDark ? 400 : 600],
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.grey[700],
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: const Color(0xFF10B981).withValues(alpha: 0.4),
            activeColor: const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }
}
