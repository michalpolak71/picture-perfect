import 'package:flutter/material.dart';

class FloorData {
  final int number;
  final String label;
  final double defaultHeight;

  FloorData({
    required this.number,
    required this.label,
    required this.defaultHeight,
  });

  @override
  bool operator ==(Object other) => other is FloorData && other.number == number;

  @override
  int get hashCode => number.hashCode;
}

class FloorPickerWidget extends StatelessWidget {
  final int? selectedFloor;
  final Function(FloorData) onFloorSelected;

  const FloorPickerWidget({
    super.key,
    this.selectedFloor,
    required this.onFloorSelected,
  });

  static final List<FloorData> floors = [
    FloorData(number: -2, label: 'Piwnica -2', defaultHeight: -6.0),
    FloorData(number: -1, label: 'Piwnica -1', defaultHeight: -3.0),
    FloorData(number: 0, label: 'Parter', defaultHeight: 0.0),
    FloorData(number: 1, label: 'Piętro 1', defaultHeight: 3.5),
    FloorData(number: 2, label: 'Piętro 2', defaultHeight: 7.0),
    FloorData(number: 3, label: 'Piętro 3', defaultHeight: 10.5),
    FloorData(number: 4, label: 'Piętro 4', defaultHeight: 14.0),
    FloorData(number: 5, label: 'Piętro 5', defaultHeight: 17.5),
    FloorData(number: 99, label: 'Dach', defaultHeight: 20.0),
  ];

  static FloorData? getFloorByNumber(int? number) {
    if (number == null) return null;
    try {
      return floors.firstWhere((f) => f.number == number);
    } catch (_) {
      return floors[2]; // Parter default
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFloor = getFloorByNumber(selectedFloor);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<FloorData>(
          value: currentFloor,
          hint: const Text(
            'Kondygnacja',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          dropdownColor: Colors.grey[900],
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
          style: const TextStyle(color: Colors.white, fontSize: 12),
          items: floors.map((floor) {
            return DropdownMenuItem<FloorData>(
              value: floor,
              child: Row(
                children: [
                  Icon(
                    floor.number < 0
                        ? Icons.arrow_downward
                        : floor.number == 0
                            ? Icons.home
                            : floor.number == 99
                                ? Icons.roofing
                                : Icons.layers,
                    size: 15,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Text(floor.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (FloorData? floor) {
            if (floor != null) onFloorSelected(floor);
          },
        ),
      ),
    );
  }
}
