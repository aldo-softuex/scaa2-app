import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();

    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    // Mantener visible el splash por al menos 2.5 segundos
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');

      bool isTokenValid = false;

      if (token != null && token.isNotEmpty) {
        final parts = token.split('.');
        if (parts.length == 3) {
          // Intenta validar como si fuera un token JWT (json web token)
          try {
            final payload = parts[1];
            final normalized = base64Url.normalize(payload);
            final resp = utf8.decode(base64Url.decode(normalized));
            final payloadMap = json.decode(resp);

            if (payloadMap.containsKey('exp')) {
              final exp = payloadMap['exp'] * 1000;
              final expDate = DateTime.fromMillisecondsSinceEpoch(exp);
              if (DateTime.now().isBefore(expDate)) {
                isTokenValid = true; // Aún vigente
              } else {
                await prefs.remove('auth_token'); // Expirado
              }
            } else {
              isTokenValid = true; // No tiene fecha, se toma válido
            }
          } catch (e) {
            isTokenValid = true; // Si es inválido por parseo pero está en sesión, se deja avanzar
          }
        } else {
          // Tokens como Sanctum de Laravel o tokens sencillos
          isTokenValid = true; 
        }
      }

      if (mounted) {
        if (isTokenValid) {
          Navigator.pushReplacementNamed(context, '/home');
        } else {
          Navigator.pushReplacementNamed(context, '/login');
        }
      }
    } catch (e) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // White background so the logo doesn't get lost
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Image.asset(
              'assets/images/logo_scaa.png',
              width: 220, // Larger logo since we removed text
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
