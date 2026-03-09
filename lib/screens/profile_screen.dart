import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Mi Perfil', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF374151),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const CircleAvatar(
              radius: 60,
              backgroundColor: Color(0xFFF3F4F6),
              child: Icon(Icons.person_rounded, size: 64, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Antonio Sánchez',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
            ),
            const Text(
              'Administrador',
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 32),
            _buildProfileItem(Icons.email_outlined, 'Email', 'antonio@scaa.com'),
            _buildProfileItem(Icons.phone_outlined, 'Teléfono', '+52 555 123 4567'),
            _buildProfileItem(Icons.location_on_outlined, 'Ubicación', 'Ciudad de México, MX'),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushReplacementNamed(context, '/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Cerrar Sesión', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFFE11D48)),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151))),
            ],
          ),
        ],
      ),
    );
  }
}
