import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ner_scanner_service.dart';
import '../services/ocr_service.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final GlobalKey _scannerKey = GlobalKey();
  final GlobalKey _frameKey = GlobalKey();

  bool showResults = false;
  bool _torchOn = false;
  bool _isCapturing = false;
  bool _isProcessing = false;
  
  Uint8List? _frontImage;
  Uint8List? _backImage;
  bool _isCapturingBack = false;

  Map<String, dynamic>? _apiData;
  Map<String, String>? _backApiData;
  String? _apiError;

  final OCRService _ocrService = OCRService();
  final NERScannerService _nerService = NERScannerService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _nerService.loadModel();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _pulseController.dispose();
    _ocrService.dispose();
    super.dispose();
  }

  void _toggleTorch() async {
    await _cameraController.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _switchCamera() async {
    await _cameraController.switchCamera();
  }

  Future<void> _onCapture() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      final double pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(3.0, 4.5);
      await Future.delayed(const Duration(milliseconds: 80));

      final RenderRepaintBoundary boundary = _scannerKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final ui.Image fullImage = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await fullImage.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List fullBytes = byteData!.buffer.asUint8List();

      final RenderBox frameBox = _frameKey.currentContext!.findRenderObject()! as RenderBox;
      final Offset frameOffset = frameBox.localToGlobal(Offset.zero);
      final Size frameSize = frameBox.size;

      final img.Image decoded = img.decodeImage(fullBytes)!;
      final int cropX = (frameOffset.dx * pixelRatio).round();
      final int cropY = (frameOffset.dy * pixelRatio).round();
      final int cropW = (frameSize.width * pixelRatio).round();
      final int cropH = (frameSize.height * pixelRatio).round();

      img.Image cropped = img.copyCrop(
        decoded,
        x: cropX.clamp(0, decoded.width - 1),
        y: cropY.clamp(0, decoded.height - 1),
        width: cropW.clamp(1, decoded.width - cropX.clamp(0, decoded.width - 1)),
        height: cropH.clamp(1, decoded.height - cropY.clamp(0, decoded.height - 1)),
      );

      // Mejora de calidad
      if (cropped.width < 1200) {
        cropped = img.copyResize(cropped, width: 1200, interpolation: img.Interpolation.cubic);
      }
      cropped = img.adjustColor(cropped, contrast: 1.4, brightness: 1.1);
      cropped = img.convolution(cropped, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

      final Uint8List processedBytes = Uint8List.fromList(img.encodePng(cropped));

      if (!_isCapturingBack) {
        setState(() {
          _frontImage = processedBytes;
          _isCapturingBack = true;
          _isCapturing = false;
        });
        _cameraController.start();
      } else {
        setState(() {
          _backImage = processedBytes;
          showResults = true;
          _isCapturing = false;
        });
        _processFullIne(_frontImage!, _backImage!);
      }
    } catch (e) {
      setState(() {
        _apiError = 'Error al capturar: $e';
        showResults = true;
        _isCapturing = false;
      });
    }
  }

  Future<void> _processFullIne(Uint8List frontBytes, Uint8List backBytes) async {
    setState(() {
      _isProcessing = true;
      _apiData = null;
      _backApiData = null;
      _apiError = null;
    });

    try {
      // Frente (API)
      final String textoFrente = await _ocrService.extraerTexto(frontBytes);
      
      if (textoFrente.isNotEmpty) {
        debugPrint('🚀 Enviando a API NER: $textoFrente');
        final response = await http.post(
          Uri.parse('https://ocrexamen.softuex.com/ine-ner'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: json.encode({'texto': textoFrente}),
        ).timeout(const Duration(seconds: 12));

        debugPrint('📡 Status API: ${response.statusCode}');
        debugPrint('📄 Body API: ${response.body}');

        if (response.statusCode == 200) {
          final Map<String, dynamic> decoded = json.decode(response.body);
          setState(() {
            _apiData = decoded['results'] ?? decoded;
          });
        } else {
          throw Exception('Servidor respondió con status: ${response.statusCode}');
        }
      }

      // Reverso (Local)
      final backData = await _ocrService.extraerDatosPosterior(backBytes);
      setState(() {
        _backApiData = backData;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _apiError = 'Error de procesamiento: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _saveFinalData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final front = _apiData ?? {};
    final back = _backApiData ?? {};

    Map<String, dynamic> record = {
      'timestamp': DateTime.now().toIso8601String(),
      'NOMBRES': back['NOMBRES_MRZ'] ?? front['NOMBRE'] ?? front['nombre'] ?? 'N/D',
      'PATERNO': back['PATERNO_MRZ'] ?? front['PATERNO'] ?? front['paterno'] ?? 'N/D',
      'MATERNO': back['MATERNO_MRZ'] ?? front['MATERNO'] ?? front['materno'] ?? 'N/D',
      'CURP': front['CURP'] ?? front['curp'] ?? 'N/D',
      'CLAVE': front['CLAVE'] ?? front['clave'] ?? 'N/D',
      'SEXO': back['SEXO'] ?? 'N/D',
      'NACIMIENTO': back['NACIMIENTO'] ?? 'N/D',
      'SECCION': back['SECCION'] ?? 'N/D',
      'VIGENCIA': back['VIGENCIA'] ?? 'N/D',
      'DOMICILIO': front['DOMICILIO'] ?? front['domicilio'] ?? 'N/D',
    };

    String? existingData = prefs.getString('saved_ines');
    List<dynamic> records = [];
    if (existingData != null) {
      records = json.decode(existingData);
    }
    
    records.insert(0, record);
    
    if (records.length > 3) {
      records = records.sublist(0, 3);
    }
    
    await prefs.setString('saved_ines', json.encode(records));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: showResults ? _buildResultsView() : _buildCameraView(),
    );
  }

  Widget _buildCameraView() {
    return LayoutBuilder(builder: (context, constraints) {
      final double screenW = constraints.maxWidth;
      final double screenH = constraints.maxHeight;
      final double frameW = screenW * 0.88;
      final double frameH = frameW / 1.586;

      return Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              key: _scannerKey,
              child: MobileScanner(controller: _cameraController),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanOverlayPainter(frameW: frameW, frameH: frameH, screenW: screenW, screenH: screenH),
            ),
          ),
          Center(
            child: SizedBox(
              key: _frameKey,
              width: frameW,
              height: frameH,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (_, __) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Stack(children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE11D48), width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    ..._buildCorners(frameW, frameH),
                  ]),
                ),
              ),
            ),
          ),
          Center(child: _ScanLine(frameW: frameW, frameH: frameH)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _iconBtn(Icons.close_rounded, onTap: () => Navigator.pop(context)),
                  const Text('Escanear INE', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  _iconBtn(_torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, onTap: _toggleTorch, active: _torchOn),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: screenH * 0.24,
            left: 40, right: 40,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE11D48).withOpacity(0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_isCapturingBack ? Icons.flip_to_back_rounded : Icons.crop_original_rounded, color: const Color(0xFFE11D48)),
                  const SizedBox(height: 8),
                  Text(
                    _isCapturingBack ? 'PASO 2: Escanea el REVERSO' : 'PASO 1: Escanea el FRENTE',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _iconBtn(Icons.flip_camera_ios_rounded, onTap: _switchCamera, size: 52),
                    GestureDetector(
                      onTap: _onCapture,
                      child: Container(
                        width: 76, height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFE11D48),
                          boxShadow: [BoxShadow(color: const Color(0xFFE11D48).withOpacity(0.5), blurRadius: 32)],
                        ),
                        child: _isCapturing 
                          ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
                          : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 34),
                      ),
                    ),
                    const SizedBox(width: 52, height: 52),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _buildResultsView() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0F172A), Color(0xFF111827)],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      showResults = false;
                      _frontImage = null;
                      _backImage = null;
                      _isCapturingBack = false;
                      _apiData = null;
                      _apiError = null;
                    }),
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
                  ),
                  const Text('Resultados del Escaneo', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_frontImage != null) _imagePreview('FRENTE', _frontImage!),
                  const SizedBox(width: 12),
                  if (_backImage != null) _imagePreview('REVERSO', _backImage!),
                ],
              ),
              const SizedBox(height: 32),
              _buildApiSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePreview(String label, Uint8List bytes) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, fit: BoxFit.cover, height: 100),
          ),
        ],
      ),
    );
  }

  Widget _buildApiSection() {
    if (_isProcessing) {
      return const Column(
        children: [
          CircularProgressIndicator(color: Color(0xFFE11D48)),
          SizedBox(height: 20),
          Text('Analizando documentos...', style: TextStyle(color: Colors.white70)),
        ],
      );
    }
    if (_apiError != null) {
      return Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 48),
          const SizedBox(height: 12),
          Text(_apiError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          ElevatedButton(onPressed: () => _processFullIne(_frontImage!, _backImage!), child: const Text('Reintentar')),
        ],
      );
    }
    return Column(
      children: [
        const Text('DATOS EXTRAÍDOS', 
          style: TextStyle(color: Color(0xFFE11D48), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        _buildUnifiedDataCard(),
        const SizedBox(height: 48),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () async {
              await _saveFinalData();
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('CONFIRMAR Y FINALIZAR', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            showResults = false;
            _frontImage = null;
            _backImage = null;
            _isCapturingBack = false;
            _apiData = null;
            _apiError = null;
          }),
          child: const Text('Volver a escanear', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildUnifiedDataCard() {
    final front = _apiData ?? {};
    final back = _backApiData ?? {};

    return _card(children: [
      _field('Nombre(s)', back['NOMBRES_MRZ'] ?? 'N/D'),
      _field('Apellido Paterno', back['PATERNO_MRZ'] ?? 'N/D'),
      _field('Apellido Materno', back['MATERNO_MRZ'] ?? 'N/D'),
      _field('CURP', front['CURP'] ?? front['curp'] ?? 'N/D'),
      _field('Clave de Elector', front['CLAVE'] ?? front['clave'] ?? 'N/D'),
      _field('Sexo', back['SEXO'] ?? 'N/D'),
      _field('Nacimiento', back['NACIMIENTO'] ?? 'N/D'),
      _field('Sección', back['SECCION'] ?? 'N/D'),
      _field('Vigencia', back['VIGENCIA'] ?? 'N/D'),
      _field('Domicilio', front['DOMICILIO'] ?? front['domicilio'] ?? 'N/D', last: true),
    ]);
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _field(String label, String value, {bool last = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.black45, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold)),
        if (!last) ...[
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _iconBtn(IconData icon, {required VoidCallback onTap, double size = 44, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFFE11D48) : Colors.black.withOpacity(0.4),
          border: Border.all(color: Colors.white24, width: 1.5),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }

  List<Widget> _buildCorners(double w, double h) {
    const c = Color(0xFFE11D48);
    const sz = 26.0;
    const th = 4.0;
    return [
      _corner(top: 0, left: 0, tl: true, sz: sz, th: th, c: c),
      _corner(top: 0, right: 0, tr: true, sz: sz, th: th, c: c),
      _corner(bottom: 0, left: 0, bl: true, sz: sz, th: th, c: c),
      _corner(bottom: 0, right: 0, br: true, sz: sz, th: th, c: c),
    ];
  }

  Widget _corner({double? top, double? bottom, double? left, double? right, bool tl = false, bool tr = false, bool bl = false, bool br = false, required double sz, required double th, required Color c}) {
    return Positioned(
      top: top, bottom: bottom, left: left, right: right,
      child: Container(
        width: sz, height: sz,
        decoration: BoxDecoration(
          border: Border(
            top: (tl || tr) ? BorderSide(color: c, width: th) : BorderSide.none,
            bottom: (bl || br) ? BorderSide(color: c, width: th) : BorderSide.none,
            left: (tl || bl) ? BorderSide(color: c, width: th) : BorderSide.none,
            right: (tr || br) ? BorderSide(color: c, width: th) : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: tl ? const Radius.circular(8) : Radius.zero,
            topRight: tr ? const Radius.circular(8) : Radius.zero,
            bottomLeft: bl ? const Radius.circular(8) : Radius.zero,
            bottomRight: br ? const Radius.circular(8) : Radius.zero,
          ),
        ),
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final double frameW, frameH, screenW, screenH;
  const _ScanOverlayPainter({required this.frameW, required this.frameH, required this.screenW, required this.screenH});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.7);
    final left = (screenW - frameW) / 2;
    final top = (screenH - frameH) / 2;
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Rect.fromLTWH(0, 0, screenW, screenH)), Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, top, frameW, frameH), const Radius.circular(16)))),
      paint,
    );
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ScanLine extends StatefulWidget {
  final double frameW, frameH;
  const _ScanLine({required this.frameW, required this.frameH});
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0, end: 1).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final topLimit = (MediaQuery.of(context).size.height - widget.frameH) / 2;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Positioned(
          top: topLimit + (widget.frameH * _anim.value),
          left: (MediaQuery.of(context).size.width - widget.frameW) / 2,
          child: Container(
            width: widget.frameW, height: 2,
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: const Color(0xFFE11D48).withOpacity(0.4), blurRadius: 10, spreadRadius: 1)],
              gradient: const LinearGradient(colors: [Colors.transparent, Color(0xFFE11D48), Colors.transparent]),
            ),
          ),
        );
      },
    );
  }
}
