import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _nombre = '';
  String _email = '';
  String _ubicacion = 'Detectando...';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nombre = prefs.getString('user_name') ?? 'Usuario';
      _email = prefs.getString('user_email') ?? '';
      _loading = false;
    });
    _obtenerUbicacion();
  }

  Future<void> _obtenerUbicacion() async {
    try {
      // Verificar permisos básicos
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _ubicacion = "Permiso denegado");
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final p = placemarks[0];
        setState(() {
          _ubicacion = "${p.locality ?? ''}, ${p.administrativeArea ?? ''}".trim();
          if (_ubicacion.startsWith(',')) _ubicacion = _ubicacion.substring(1).trim();
          if (_ubicacion.endsWith(',')) _ubicacion = _ubicacion.substring(0, _ubicacion.length - 1).trim();
          if (_ubicacion.isEmpty) _ubicacion = "Ubicación detectada";
        });
      }
    } catch (e) {
      if (mounted) setState(() => _ubicacion = "No disponible");
    }
  }

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
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE11D48)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 60,
                    backgroundColor: Color(0xFFF3F4F6),
                    child: Icon(Icons.person_rounded, size: 64, color: Color(0xFF374151)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _nombre.isNotEmpty ? _nombre : 'Usuario',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                  ),
                  const SizedBox(height: 32),
                  if (_email.isNotEmpty)
                    _buildProfileItem(Icons.email_outlined, 'Email', _email),
                  _buildProfileItem(Icons.phone_outlined, 'Teléfono', '+52 555 123 4567'),
                  _buildProfileItem(Icons.location_on_outlined, 'Ubicación', _ubicacion),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('auth_token');
                        await prefs.remove('user_name');
                        await prefs.remove('user_email');
                        if (context.mounted) {
                          Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                        }
                      },
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
