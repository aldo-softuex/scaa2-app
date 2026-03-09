import 'package:flutter/material.dart';

class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Registros de Escaneo', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF374151),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
        child: Column(
          children: [
            _buildLogCard('INE - Juan Perez', '24 min ago', 'Aprobado', Colors.green),
            _buildLogCard('PASAPORTE - M. Garza', '52 min ago', 'Aprobado', Colors.green),
            _buildLogCard('INE - Carlos Lopez', '2h ago', 'Rechazado', const Color(0xFFE11D48)),
            _buildLogCard('INE - Ana Martinez', '3h ago', 'Aprobado', Colors.green),
            _buildLogCard('PASAPORTE - Roberto Solis', '4h ago', 'Pendiente', Colors.orange),
            _buildLogCard('INE - Sofia Ruiz', 'Yesterday', 'Aprobado', Colors.green),
            _buildLogCard('PASAPORTE - Esteban Garcia', 'Yesterday', 'Aprobado', Colors.green),
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(String title, String time, String status, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.history_rounded, color: statusColor.withOpacity(0.8)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151), fontSize: 16),
                ),
                Text(
                  time,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
