import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _recentInes = [];
  bool _loadingActivity = true;
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRecentActivity();
  }

  Future<void> _loadRecentActivity() async {
    setState(() => _loadingActivity = true);
    
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final token = prefs.getString('auth_token') ?? '';

    if (userId == 0) {
      if (mounted) setState(() => _loadingActivity = false);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('https://scaa.olgasosa.mx/api/v1/seccion/promotores/dev/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _recentInes = data['data'] ?? [];
            _totalCount = data['total'] ?? 0;
            _loadingActivity = false;
          });
        }
      } else {
        if (mounted) setState(() => _loadingActivity = false);
      }
    } catch (e) {
      debugPrint('Error al cargar actividad: $e');
      // Intentar cargar local como fallback si falló la API
      final localData = prefs.getString('saved_ines');
      if (localData != null && mounted) {
        setState(() {
          _recentInes = json.decode(localData);
          _totalCount = _recentInes.length;
          _loadingActivity = false;
        });
      } else {
        if (mounted) setState(() => _loadingActivity = false);
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
                    const SizedBox(width: 48), // Espaciador para mantener el diseño
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
                          _totalCount.toString(),
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
                child: _loadingActivity
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFFE11D48)))
                    : _recentInes.isEmpty 
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
                              
                              // El formato de la API trae los datos dentro del objeto 'persona'
                              final persona = record['persona'];
                              if (persona == null) return const SizedBox();

                              final timeStr = _formatTime(record['created_at']);
                              
                              String curp = persona['clave_curp'] ?? 'SIN CURP';
                              String nombres = persona['nombre'] ?? '';
                              String paterno = persona['paterno'] ?? '';
                              String materno = persona['materno'] ?? '';
                              
                              String docTitle = 'INE - $curp';
                              String fullName = '$paterno $materno $nombres'.trim();
                              
                              return _buildRecentCard(context, docTitle, fullName, timeStr, record, isDarkMode);
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

  void _showRecordDetail(BuildContext context, Map<String, dynamic> record, bool isDarkMode) {
    // Detectar si es API (objeto 'persona' anidado) o Local (plano)
    final persona = record['persona'];
    final bool isApi = persona != null;
    final Map<String, dynamic> source = isApi ? persona : record;

    dynamic imgFrente, imgTrasera, imgCara;

    if (isApi) {
      imgFrente = source['url_imagen_ine'];
      imgTrasera = source['url_imagen_ine_trasera'];
      imgCara = source['url_imagen_face'];
    } else {
      try { if ((record['imagenb64'] ?? '').isNotEmpty) imgFrente = base64Decode(record['imagenb64']); } catch (_) {}
      try { if ((record['ine_trasera'] ?? '').isNotEmpty) imgTrasera = base64Decode(record['ine_trasera']); } catch (_) {}
      try { if ((record['imagen_face'] ?? '').isNotEmpty) imgCara = base64Decode(record['imagen_face']); } catch (_) {}
    }

    final fields = [
      ['CURP', isApi ? source['clave_curp'] : source['CURP']],
      ['Nombre(s)', isApi ? source['nombre'] : source['NOMBRES']],
      ['Paterno', isApi ? source['paterno'] : source['PATERNO']],
      ['Materno', isApi ? source['materno'] : source['MATERNO']],
      ['Sección', isApi ? source['seccion']?.toString() : source['SECCION']],
      ['Vigencia', isApi ? source['vigencia_ine'] : source['VIGENCIA']],
      ['Nacimiento', isApi ? source['fecha_nac'] : source['NACIMIENTO']],
      ['Municipio', isApi ? (source['municipio_vive'] != null ? source['municipio_vive']['municipio'] : 'N/D') : source['MUNICIPIO']],
      ['CP', isApi ? source['codigo_postal'] : source['CODIGO_POSTAL']],
      ['Colonia', isApi ? source['colonia'] : source['COLONIA']],
      ['Calle', isApi ? source['calle'] : source['CALLE']],
      ['Número', isApi ? source['numero'] : source['NUMERO']],
      ['Domicilio', isApi ? source['domicilio'] : source['DOMICILIO']],
      ['Coordenadas', record['coordenadas'] ?? 'N/D'],
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF111827) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  // Titulo
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.description_rounded, color: Color(0xFFE11D48)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isApi 
                                ? '${source['nombre'] ?? ''} ${source['paterno'] ?? ''}'.trim()
                                : '${record['NOMBRES'] ?? ''} ${record['PATERNO'] ?? ''}'.trim(),
                            style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : const Color(0xFF374151),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Contenido desplazable
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // ---- Fila de las 3 imágenes ----
                        if (imgFrente != null || imgTrasera != null || imgCara != null) ...[
                          Row(
                            children: [
                              if (imgFrente != null)
                                _buildImageTile(imgFrente, 'Delantera', isDarkMode),
                              if (imgTrasera != null)
                                _buildImageTile(imgTrasera, 'Trasera', isDarkMode),
                              if (imgCara != null)
                                _buildImageTile(imgCara, 'Cara', isDarkMode, isCircle: true),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                        // ---- Campos extraídos ----
                        ...fields.where((f) => f[1] != null && f[1] != 'N/D' && f[1]!.isNotEmpty).map((f) =>
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 120,
                                  child: Text(f[0]!, style: TextStyle(fontSize: 12, color: isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280))),
                                ),
                                Expanded(
                                  child: Text(f[1]!, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isDarkMode ? Colors.white : const Color(0xFF374151))),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildImageTile(dynamic imageData, String label, bool isDarkMode, {bool isCircle = false}) {
    if (imageData == null) return const SizedBox();
    
    ImageProvider provider;
    if (imageData is Uint8List) {
      provider = MemoryImage(imageData);
    } else if (imageData is String && imageData.startsWith('http')) {
      provider = NetworkImage(imageData);
    } else {
      return const SizedBox();
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            isCircle
                ? CircleAvatar(radius: 40, backgroundColor: Colors.grey[200], backgroundImage: provider)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                        child: Container(
                          color: Colors.grey[200],
                          child: Image(image: provider, height: 80, fit: BoxFit.cover, width: double.infinity, 
                            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 20),
                            loadingBuilder: (c, child, progress) => progress == null ? child : const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE11D48)))),
                          ),
                        ),
                  ),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280))),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCard(BuildContext context, String title, String data, String time, Map<String, dynamic> record, bool isDarkMode) {
    return GestureDetector(
      onTap: () => _showRecordDetail(context, record, isDarkMode),
      child: Container(
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
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF9CA3AF))),
                  Text(data, style: TextStyle(fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : const Color(0xFF374151), fontSize: 15)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time, style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFE11D48)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
