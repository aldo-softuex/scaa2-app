import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/cupertino.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final List<dynamic> _logs = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _nextPageUrl; // Para controlar si hay más páginas según la API
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchInitialLogs();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      if (notification.metrics.extentAfter < 100) { // Menos de 100px para el final
        if (!_isLoadingMore && _nextPageUrl != null) {
          _fetchMoreLogs();
        }
      }
    }
    return false;
  }

  Future<void> _fetchInitialLogs() async {
    setState(() => _isLoading = true);
    await _fetchLogs(1);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchMoreLogs() async {
    if (_nextPageUrl == null) return;
    setState(() => _isLoadingMore = true);
    await _fetchLogs(_currentPage + 1);
    if (mounted) setState(() => _isLoadingMore = false);
  }

  Future<void> _fetchLogs(int page) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;
    final token = prefs.getString('auth_token') ?? '';

    if (userId == 0) return;

    try {
      final response = await http.get(
        Uri.parse('https://scaa.olgasosa.mx/api/v1/seccion/promotores/dev/$userId?page=$page'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List newItems = data['data'] ?? [];
        
        if (mounted) {
          setState(() {
            if (page == 1) _logs.clear();
            _logs.addAll(newItems);
            _currentPage = data['current_page'] ?? page;
            _nextPageUrl = data['next_page_url'];
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching logs: $e');
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'ahora';
      if (diff.inHours < 1) return '${diff.inMinutes}m';
      if (diff.inDays < 1) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Registros de Escaneo', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF374151),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE11D48)))),
            )
        ],
      ),
      body: _isLoading && _logs.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE11D48)))
          : RefreshIndicator(
              onRefresh: _fetchInitialLogs,
              color: const Color(0xFFE11D48),
              child: _logs.isEmpty
                  ? const Center(child: Text('No hay registros encontrados'))
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                        itemCount: _logs.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _logs.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CupertinoActivityIndicator()),
                            );
                          }
                          
                          final record = _logs[index];
                          final persona = record['persona'];
                          if (persona == null) return const SizedBox();

                          final timeStr = _formatTime(record['created_at']);
                          String curp = persona['clave_curp'] ?? 'SIN CURP';
                          String fullName = '${persona['paterno'] ?? ''} ${persona['materno'] ?? ''} ${persona['nombre'] ?? ''}'.trim();

                          return _buildLogCard(context, 'INE - $curp', fullName, timeStr, record);
                        },
                      ),
                    ),
            ),
    );
  }

  Widget _buildLogCard(BuildContext context, String title, String subtitle, String time, Map<String, dynamic> record) {
    final persona = record['persona'];
    return GestureDetector(
      onTap: () => _showRecordDetail(context, record),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF3F4F6)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 48,
                height: 48,
                color: const Color(0xFFF9FAFB),
                child: persona?['url_imagen_face'] != null
                    ? Image.network(
                        persona!['url_imagen_face'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.person, color: Color(0xFFE11D48)),
                      )
                    : const Icon(Icons.person, color: Color(0xFFE11D48)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151), fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF1F2937), fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFD1D5DB)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRecordDetail(BuildContext context, Map<String, dynamic> record) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
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
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
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
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
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
                        ...fields.where((f) => f[1] != null && f[1] != 'N/D' && f[1]!.toString().isNotEmpty).map((f) =>
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
}
