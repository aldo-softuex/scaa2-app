import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _recentInes = [];

  @override
  void initState() {
    super.initState();
    _loadRecentActivity();
  }

  Future<void> _loadRecentActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('saved_ines');
    if (data != null) {
      if (mounted) {
        setState(() {
          _recentInes = json.decode(data);
        });
      }
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'ahora';
      if (diff.inHours < 1) return '${diff.inMinutes} min ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                : [const Color(0xFFFFF1F2), Colors.white],
            stops: const [0.0, 0.35],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.more_horiz_rounded,
                          size: 32,
                          color: isDarkMode ? Colors.white : const Color(0xFF374151)),
                      onPressed: () => Navigator.pushNamed(context, '/settings'),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pushNamed(context, '/profile'),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 22,
                          backgroundColor: isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6),
                          child: Icon(Icons.person_rounded,
                              color: isDarkMode ? Colors.white : const Color(0xFF374151),
                              size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),
              // Stat Card (Highlight)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDarkMode ? 0.3 : 0.04),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _recentInes.length.toString(),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE11D48),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Escaneos procesados',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.show_chart_rounded, color: Color(0xFFE11D48)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  height: 160,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    clipBehavior: Clip.none,
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildActionCard(context, 'NUEVO\nESCANEO', Icons.camera_alt_rounded,
                          const Color(0xFFE11D48), isDarkMode),
                      _buildActionCard(
                          context,
                          'REVISAR\nDATOS',
                          Icons.assignment_rounded,
                          isDarkMode ? const Color(0xFF1F2937) : Colors.white,
                          isDarkMode),
                      _buildActionCard(
                          context,
                          'AJUSTES',
                          Icons.settings_rounded,
                          isDarkMode ? const Color(0xFF1F2937) : Colors.white,
                          isDarkMode),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Actividad Reciente',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : const Color(0xFF374151),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Recent list looking like cards from design
              Expanded(
                child: _recentInes.isEmpty 
                    ? Center(
                        child: Text(
                          'No hay actividad reciente', 
                          style: TextStyle(color: isDarkMode ? Colors.white54 : Colors.grey)
                        )
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        itemCount: _recentInes.length,
                        itemBuilder: (context, index) {
                          final record = _recentInes[index];
                          final timeStr = _formatTime(record['timestamp']);
                          
                          String nombres = record['NOMBRES'] ?? '';
                          String paterno = record['PATERNO'] ?? '';
                          String materno = record['MATERNO'] ?? '';
                          
                          String nameFirstWord = nombres.isNotEmpty ? nombres.split(' ').first : 'N/D';
                          String docTitle = 'INE - $nameFirstWord $paterno';
                          String fullName = '$nombres $paterno $materno'.trim();
                          
                          return _buildRecentCard(docTitle, fullName, timeStr, isDarkMode);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF0F172A) : Colors.white,
          border: Border(
              top: BorderSide(
                  color: isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6), width: 1)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(Icons.home_filled,
                  size: 28, color: isDarkMode ? Colors.white : const Color(0xFF374151)),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded, size: 28, color: Color(0xFF9CA3AF)),
              onPressed: () => Navigator.pushNamed(context, '/logs'),
            ),
            IconButton(
              icon: const Icon(Icons.person_rounded, size: 28, color: Color(0xFF9CA3AF)),
              onPressed: () => Navigator.pushNamed(context, '/profile'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(
      BuildContext context, String title, IconData icon, Color bgColor, bool isDarkMode) {
    bool isDark = bgColor == const Color(0xFFE11D48) ||
        bgColor == const Color(0xFF1F2937) ||
        bgColor == const Color(0xFF374151);
    return InkWell(
      onTap: () async {
        if (title.contains('ESCANEO')) {
          await Navigator.pushNamed(context, '/scan');
          _loadRecentActivity();
        } else if (title.contains('DATOS')) {
          Navigator.pushNamed(context, '/logs');
        } else if (title.contains('AJUSTES')) {
          Navigator.pushNamed(context, '/settings');
        }
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark 
                ? Colors.white.withOpacity(0.1) 
                : (isDarkMode ? const Color(0xFF374151) : const Color(0xFFE2E8F0)),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 32, color: isDark ? Colors.white : const Color(0xFFD32F2F)),
            Text(
              title,
              style: TextStyle(
                color: isDark
                    ? Colors.white
                    : (isDarkMode ? Colors.white70 : const Color(0xFF374151)),
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard(String title, String data, String time, bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.description_rounded, color: Color(0xFFE11D48)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9CA3AF)),
                ),
                Text(
                  data,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF374151),
                      fontSize: 15),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(time, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFE5E7EB)),
            ],
          ),
        ],
      ),
    );
  }
}
