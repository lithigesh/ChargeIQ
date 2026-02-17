import 'package:flutter/material.dart';

class ManageVehiclesScreen extends StatefulWidget {
  const ManageVehiclesScreen({super.key});

  @override
  State<ManageVehiclesScreen> createState() => _ManageVehiclesScreenState();
}

class _ManageVehiclesScreenState extends State<ManageVehiclesScreen> {
  final List<_Vehicle> _vehicles = [
    _Vehicle(name: 'Tesla Model 3', trim: 'Long Range AWD'),
  ];

  Future<void> _showVehicleForm({int? index}) async {
    final isEditing = index != null;
    final nameController = TextEditingController(
      text: isEditing ? _vehicles[index].name : '',
    );
    final trimController = TextEditingController(
      text: isEditing ? _vehicles[index].trim : '',
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEditing ? 'Edit Vehicle' : 'Add Vehicle',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Vehicle Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: trimController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Trim or Variant',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  final trim = trimController.text.trim();
                  if (name.isEmpty) return;

                  setState(() {
                    if (isEditing) {
                      _vehicles[index] = _Vehicle(name: name, trim: trim);
                    } else {
                      _vehicles.add(_Vehicle(name: name, trim: trim));
                    }
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(isEditing ? 'Save Changes' : 'Add Vehicle'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Vehicles'),
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage your vehicles',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _vehicles.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final vehicle = _vehicles[index];
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF263238),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vehicle.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                vehicle.trim.isEmpty
                                    ? 'Trim not set'
                                    : vehicle.trim,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => _showVehicleForm(index: index),
                          child: const Text('Edit'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showVehicleForm(),
                icon: const Icon(Icons.add),
                label: const Text('Add Vehicle'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Vehicle {
  _Vehicle({required this.name, required this.trim});

  final String name;
  final String trim;
}
