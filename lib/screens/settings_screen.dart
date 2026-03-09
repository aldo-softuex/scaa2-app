import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Ajustes', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF374151),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: Column(
          children: [
            _buildSection('Cuenta', [
              _buildSettingItem(Icons.person_outline_rounded, 'Información del Perfil', 'antonio.sanchez@scaa.com'),
              _buildSettingItem(Icons.lock_outline_rounded, 'Seguridad', 'Contraseña y 2FA'),
            ]),
            const SizedBox(height: 24),
            _buildSection('Notificaciones', [
              _buildSettingItem(Icons.notifications_none_rounded, 'Push Notifications', 'Activado'),
              _buildSettingItem(Icons.email_outlined, 'Email Alerts', 'Importante solamente'),
            ]),
            const SizedBox(height: 24),
            _buildSection('App', [
              _buildSettingItem(Icons.language_rounded, 'Idioma', 'Español (MX)'),
              _buildSettingItem(Icons.dark_mode_outlined, 'Modo Oscuro', 'Seguir sistema'),
              _buildSettingItem(Icons.help_outline_rounded, 'Ayuda y Soporte', ''),
            ]),
            const SizedBox(height: 24),
            Text(
              'Versión 1.0.0 (Build 001)',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF9CA3AF),
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          color: Colors.white,
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingItem(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF374151)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF374151))),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: const TextStyle(color: Color(0xFF9CA3AF))) : null,
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFFE5E7EB)),
      onTap: () {},
    );
  }
}
