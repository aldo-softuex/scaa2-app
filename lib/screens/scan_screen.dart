import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image/image.dart' as img;

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _cameraController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  // Keys para capturar la pantalla y localizar el marco
  final GlobalKey _scannerKey = GlobalKey();
  final GlobalKey _frameKey = GlobalKey();

  bool showResults = false;
  bool _torchOn = false;
  bool _isCapturing = false;
  bool _isSending = false;
  Uint8List? _croppedImage;
  Map<String, dynamic>? _apiData;
  String? _apiError;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation =
        Tween<double>(begin: 0.97, end: 1.03).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleTorch() async {
    await _cameraController.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _switchCamera() async {
    await _cameraController.switchCamera();
  }

  /// Captura la pantalla completa y recorta solo el área del marco
  Future<void> _onCapture() async {
    if (_isCapturing) return;
    setState(() => _isCapturing = true);

    try {
      // 1. Forzamos un pixelRatio alto para obtener más detalle de la textura de la cámara
      final double pixelRatio = MediaQuery.of(context).devicePixelRatio.clamp(3.0, 4.5);

      // 2. Pequeña pausa para asegurar que el frame esté renderizado
      await Future.delayed(const Duration(milliseconds: 80));

      // 3. Capturamos SOLO el feed de cámara (sin overlays rojos)
      final RenderRepaintBoundary boundary =
          _scannerKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final ui.Image fullImage =
          await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData =
          await fullImage.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List fullBytes = byteData!.buffer.asUint8List();

      // 3. Obtenemos la posición y tamaño del marco en pantalla
      final RenderBox frameBox =
          _frameKey.currentContext!.findRenderObject()! as RenderBox;
      final Offset frameOffset = frameBox.localToGlobal(Offset.zero);
      final Size frameSize = frameBox.size;

      // 4. Recortamos la imagen al área del marco (ajustando por pixelRatio)
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

      // ── MEJORA DE CALIDAD (Filtros Digitales v4) ──────────────────
      
      // 1. Upscaling inteligente (Redimensionar a 1200px de ancho)
      if (cropped.width < 1200) {
        cropped = img.copyResize(cropped, width: 1200, interpolation: img.Interpolation.cubic);
      }

      // 2. Ajuste de Brillo y Contraste (v4 usa adjustColor)
      // contrast: 1.4 -> 140, brightness: 1.1 -> 0.1 de incremento aproximado
      cropped = img.adjustColor(cropped, contrast: 1.4, brightness: 1.1);

      // 3. Sharpen (Afilado) - Usando una matriz de convolución para resaltar bordes
      // Matriz estándar de sharpen: [0, -1, 0, -1, 5, -1, 0, -1, 0]
      cropped = img.convolution(cropped, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);
      
      // ──────────────────────────────────────────────────────────────

      final Uint8List processedBytes =
          Uint8List.fromList(img.encodePng(cropped));

      // Mostramos la pantalla de resultados y lanzamos el envío a la API
      setState(() {
        _croppedImage = processedBytes;
        showResults = true;
        _isCapturing = false;
      });

      // Enviamos automáticamente a la API
      _sendToApi(processedBytes);
    } catch (e) {
      setState(() {
        _croppedImage = null;
        _apiError = 'Error al procesar la imagen: $e';
        showResults = true;
        _isCapturing = false;
      });
    }
  }

  /// Envía la imagen recortada a la API de OCR como multipart/form-data
  Future<void> _sendToApi(Uint8List imageBytes) async {
    setState(() {
      _isSending = true;
      _apiData = null;
      _apiError = null;
    });

    try {
      final uri = Uri.parse('https://ocrexamen.softuex.com/extraer-archivo');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            imageBytes,
            filename: 'credencial.png',
            contentType: MediaType('image', 'png'),
          ),
        );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        setState(() {
          // El backend dice que devuelve 'results'
          _apiData = body['results'] ?? body;
          _isSending = false;
        });
      } else {
        setState(() {
          _apiError = 'Error del servidor (${response.statusCode}):\n${response.body}';
          _isSending = false;
        });
      }
    } catch (e) {
      setState(() {
        _apiError = 'Error de conexión:\n$e';
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: showResults ? _buildResultsView() : _buildCameraView(),
    );
  }

  // ─────────────────────────── VISTA DE CÁMARA ──────────────────────────────
  Widget _buildCameraView() {
    return LayoutBuilder(builder: (context, constraints) {
      final double screenW = constraints.maxWidth;
      final double screenH = constraints.maxHeight;

      // Marco proporcional a una credencial INE real (85.6 × 54 mm → ratio ≈ 1.586)
      final double frameW = screenW * 0.88;
      final double frameH = frameW / 1.586;

      return Stack(
          children: [
            // ── Cámara en vivo (SOLO esto se captura para el recorte) ─
            Positioned.fill(
              child: RepaintBoundary(
                key: _scannerKey,
                child: MobileScanner(controller: _cameraController),
              ),
            ),

            // ── Overlay oscuro (FUERA del RepaintBoundary) ──────────
            Positioned.fill(
              child: CustomPaint(
                painter: _ScanOverlayPainter(
                  frameW: frameW,
                  frameH: frameH,
                  screenW: screenW,
                  screenH: screenH,
                ),
              ),
            ),

            // ── Marco: _frameKey en el SizedBox estático (sin escala)
            //    para que localToGlobal devuelva coordenadas exactas ─
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
                      // Borde completo
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: const Color(0xFFE11D48), width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      // Esquinas LED rojas
                      ..._buildCorners(frameW, frameH),
                    ]),
                  ),
                ),
              ),
            ),

            // ── Línea de escaneo animada (FUERA del RepaintBoundary) ─
            Center(
              child: _ScanLine(frameW: frameW, frameH: frameH),
            ),

            // ── Barra superior ──────────────────────────────────────
            SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _iconBtn(Icons.close_rounded,
                        onTap: () => Navigator.pop(context)),
                    const Text('Escanear INE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    _iconBtn(
                      _torchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onTap: _toggleTorch,
                      active: _torchOn,
                    ),
                  ],
                ),
              ),
            ),

            // ── Etiqueta de instrucción ─────────────────────────────
            Positioned(
              bottom: screenH * 0.24,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Text(
                    'Alinea la INE dentro del marco',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),

            // ── Controles inferiores ────────────────────────────────
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 44),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Cambiar cámara
                      _iconBtn(Icons.flip_camera_ios_rounded,
                          onTap: _switchCamera, size: 52),

                      // Shutter
                      GestureDetector(
                        onTap: _onCapture,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: _isCapturing ? 68 : 76,
                          height: _isCapturing ? 68 : 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFE11D48),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFFE11D48).withOpacity(0.55),
                                blurRadius: 32,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: _isCapturing
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2.5),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text('OPTIMIZANDO', 
                                      style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold))
                                  ],
                                )
                              : const Icon(Icons.camera_alt_rounded,
                                  color: Colors.white, size: 34),
                        ),
                      ),

                      // Espacio espejo
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

  // ─────────────────────────── VISTA DE RESULTADOS ──────────────────────────
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
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              // Encabezado
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      showResults = false;
                      _croppedImage = null;
                      _apiData = null;
                      _apiError = null;
                    }),
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white),
                  ),
                  const Text('Captura de Credencial',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 20),

              // ── Preview del recorte ─────────────────────────────
              if (_croppedImage != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Vista previa del recorte',
                        style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1)),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.memory(
                        _croppedImage!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),

              // ── Sección de datos de la API ──────────────────────
              _buildApiSection(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sección dinámica basada en el estado de la API ────────────────
  Widget _buildApiSection() {
    if (_isSending) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        width: double.infinity,
        child: const Column(
          children: [
            CircularProgressIndicator(color: Color(0xFFE11D48)),
            SizedBox(height: 20),
            Text(
              'Extrayendo datos con IA...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_apiError != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFFE11D48).withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE11D48).withOpacity(0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFE11D48), size: 40),
            const SizedBox(height: 12),
            Text(
              _apiError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _sendToApi(_croppedImage!),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE11D48)),
              child: const Text('Reintentar', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (_apiData != null) {
      return Column(
        children: [
          // Tarjeta de datos reales
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 40,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field('Nombre Completo', _apiData!['nombre'] ?? _apiData!['NOMBRE'] ?? 'No detectado'),
                _field('Clave Elector', _apiData!['clave_elector'] ?? _apiData!['CLAVE'] ?? 'No detectado'),
                _field('CURP', _apiData!['curp'] ?? _apiData!['CURP'] ?? 'No detectado'),
                _field('Fecha Nacimiento', _apiData!['fecha_nacimiento'] ?? _apiData!['FECHA'] ?? 'No detectado'),
                _field('Sección', _apiData!['seccion'] ?? _apiData!['SECCION'] ?? 'No detectado', last: true),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // Botón Confirmar
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Confirmar y Guardar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              showResults = false;
              _croppedImage = null;
              _apiData = null;
              _apiError = null;
            }),
            child: const Text('Volver a escanear', style: TextStyle(color: Color(0xFF9CA3AF))),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  // ─────────────────────────── HELPERS ──────────────────────────────────────
  Widget _field(String label, String value, {bool last = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9CA3AF),
                letterSpacing: 1.2)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827))),
        if (!last) const Divider(height: 24, color: Color(0xFFF3F4F6)),
      ],
    );
  }

  Widget _iconBtn(IconData icon,
      {required VoidCallback onTap, double size = 44, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active
              ? const Color(0xFFE11D48).withOpacity(0.85)
              : Colors.black.withOpacity(0.45),
          border: Border.all(
            color: active
                ? const Color(0xFFE11D48)
                : Colors.white.withOpacity(0.25),
            width: 1.5,
          ),
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

  Widget _corner({
    double? top,
    double? bottom,
    double? left,
    double? right,
    bool tl = false,
    bool tr = false,
    bool bl = false,
    bool br = false,
    required double sz,
    required double th,
    required Color c,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          border: Border(
            top: (tl || tr) ? BorderSide(color: c, width: th) : BorderSide.none,
            bottom:
                (bl || br) ? BorderSide(color: c, width: th) : BorderSide.none,
            left:
                (tl || bl) ? BorderSide(color: c, width: th) : BorderSide.none,
            right:
                (tr || br) ? BorderSide(color: c, width: th) : BorderSide.none,
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

// ──────────────── OVERLAY CUSTOM PAINTER ────────────────────────────────────
class _ScanOverlayPainter extends CustomPainter {
  final double frameW, frameH, screenW, screenH;
  const _ScanOverlayPainter({
    required this.frameW,
    required this.frameH,
    required this.screenW,
    required this.screenH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.6);
    final left = (screenW - frameW) / 2;
    final top = (screenH - frameH) / 2;
    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, frameW, frameH),
      const Radius.circular(12),
    );
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(frameRect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter old) =>
      old.frameW != frameW || old.frameH != frameH;
}

// ──────────────── LÍNEA DE ESCANEO ANIMADA ──────────────────────────────────
class _ScanLine extends StatefulWidget {
  final double frameW, frameH;
  const _ScanLine({required this.frameW, required this.frameH});
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.frameW,
      height: widget.frameH,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Stack(
          children: [
            Positioned(
              top: _anim.value * (widget.frameH - 3),
              left: 0,
              right: 0,
              child: Container(
                height: 2.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFFE11D48).withOpacity(0.9),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
