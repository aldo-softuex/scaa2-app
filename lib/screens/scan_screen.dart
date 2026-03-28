import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../services/ner_scanner_service.dart';
import '../services/ocr_service.dart';
import '../utils/address_parser.dart';
import 'package:geolocator/geolocator.dart';

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
  bool _showFrontPreview = false;
  ui.Image? _frozenCameraFrame;

  Map<String, dynamic>? _apiData;
  Map<String, String>? _backApiData;
  String? _apiError;
  Uint8List? _faceImage;

  final OCRService _ocrService = OCRService();
  final NERScannerService _nerService = NERScannerService();
  final FaceDetector _faceDetector = FaceDetector(options: FaceDetectorOptions());

  final Map<String, TextEditingController> _controllers = {
    'TELEFONO': TextEditingController(),
    'NOMBRES': TextEditingController(),
    'PATERNO': TextEditingController(),
    'MATERNO': TextEditingController(),
    'CURP': TextEditingController(),
    'CLAVE': TextEditingController(),
    'SEXO': TextEditingController(),
    'NACIMIENTO': TextEditingController(),
    'SECCION': TextEditingController(),
    'VIGENCIA': TextEditingController(),
    'DOMICILIO': TextEditingController(),
    'MUNICIPIO': TextEditingController(),
    'COLONIA': TextEditingController(),
    'CODIGO_POSTAL': TextEditingController(),
    'CALLE': TextEditingController(),
    'NUMERO': TextEditingController(),
  };

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
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _pulseController.dispose();
    _ocrService.dispose();
    _faceDetector.close();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
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

      if (mounted) {
        setState(() => _frozenCameraFrame = fullImage);
        // Permitir que el UI dibuje el frame congelado instantáneamente antes del procesamiento pesado
        await Future.delayed(const Duration(milliseconds: 50));
      }

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
          _showFrontPreview = true;
          _isCapturing = false;
          _faceImage = null;
          _frozenCameraFrame = null;
        });
      } else {
        setState(() {
          _backImage = processedBytes;
          showResults = true;
          _isCapturing = false;
          _frozenCameraFrame = null;
        });
        _processFullIne(_frontImage!, _backImage!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiError = 'Error al capturar: $e';
          showResults = true;
          _isCapturing = false;
          _frozenCameraFrame = null;
        });
      }
    }
  }

  Future<void> _processFullIne(Uint8List frontBytes, Uint8List backBytes) async {
    setState(() {
      _isProcessing = true;
      _apiData = null;
      _backApiData = null;
      _apiError = null;
      _faceImage = null;
    });

    try {
      // Detección de rostro
      await _detectFace(frontBytes);

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

        final front = _apiData ?? {};
        final back = _backApiData ?? {};

        _controllers['NOMBRES']?.text = back['NOMBRES_MRZ'] ?? front['NOMBRE'] ?? front['nombre'] ?? '';
        _controllers['PATERNO']?.text = back['PATERNO_MRZ'] ?? front['PATERNO'] ?? front['paterno'] ?? '';
        _controllers['MATERNO']?.text = back['MATERNO_MRZ'] ?? front['MATERNO'] ?? front['materno'] ?? '';
        _controllers['CURP']?.text = front['CURP'] ?? front['curp'] ?? '';
        _controllers['CLAVE']?.text = front['CLAVE'] ?? front['clave'] ?? '';
        _controllers['SEXO']?.text = back['SEXO'] ?? '';
        _controllers['NACIMIENTO']?.text = back['NACIMIENTO'] ?? '';
        _controllers['SECCION']?.text = back['SECCION'] ?? '';
        _controllers['VIGENCIA']?.text = back['VIGENCIA'] ?? '';
        _controllers['DOMICILIO']?.text = front['DOMICILIO'] ?? front['domicilio'] ?? '';
        _controllers['MUNICIPIO']?.text = front['MUNICIPIO'] ?? front['municipio'] ?? '';

        final domicilioStr = _controllers['DOMICILIO']?.text;
        final coloniaVal = AddressParser.extraerColoniaDeDomicilio(domicilioStr);
        final cpVal = AddressParser.extraerCodigoPostal(domicilioStr);
        final calleVal = AddressParser.extraerCalleDeDomicilio(domicilioStr, coloniaVal);
        final numVal = AddressParser.extraerNumeroDeCalle(calleVal);

        _controllers['COLONIA']?.text = coloniaVal;
        _controllers['CODIGO_POSTAL']?.text = cpVal;
        _controllers['CALLE']?.text = calleVal;
        _controllers['NUMERO']?.text = numVal;
      });
    } catch (e) {
      setState(() {
        _apiError = 'Error de procesamiento: $e';
        _isProcessing = false;
      });
    }
  }

  Future<void> _detectFace(Uint8List imageBytes) async {
    File? tempFile;
    try {
      final dir = await getTemporaryDirectory();
      tempFile = File('${dir.path}/face_detect_tmp.jpg');
      await tempFile.writeAsBytes(imageBytes);

      final InputImage inputImage = InputImage.fromFilePath(tempFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);
      debugPrint('🔍 Rostros detectados: ${faces.length}');
      if (faces.isEmpty) return;

      final Face largest = faces.reduce((a, b) =>
          (a.boundingBox.width * a.boundingBox.height) >=
                  (b.boundingBox.width * b.boundingBox.height)
              ? a
              : b);

      final img.Image? decoded = img.decodeImage(imageBytes);
      if (decoded == null) return;

      final Rect box = largest.boundingBox;
      final int x = box.left.round().clamp(0, decoded.width - 1);
      final int y = box.top.round().clamp(0, decoded.height - 1);
      final int w = box.width.round().clamp(1, decoded.width - x);
      final int h = box.height.round().clamp(1, decoded.height - y);
      final img.Image cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
      setState(() => _faceImage = Uint8List.fromList(img.encodePng(cropped)));
    } catch (e) {
      debugPrint('❌ Error detectando rostro: $e');
    } finally {
      await tempFile?.delete();
    }
  }

  Future<http.Response?> _sendDataToApi() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('auth_token');
      debugPrint('TOKEN DE AUTORIZACIÓN: $token');

      // Obtener coordenadas de forma silenciosa
      String coords = "";
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 3),
        );
        coords = "${position.latitude},${position.longitude}";
      } catch (e) {
        debugPrint('Error obteniendo coordenadas (silencioso): $e');
      }

      String vigenciaFull = _controllers['VIGENCIA']?.text ?? "";
      String vigenciaAnio = vigenciaFull.contains('/') 
          ? vigenciaFull.split('/').last 
          : (vigenciaFull.length > 4 ? vigenciaFull.substring(vigenciaFull.length - 4) : vigenciaFull);

      final Map<String, dynamic> body = {
        "archivo_procesado": _controllers['TELEFONO']?.text ?? "",
        "coordenadas": coords,
        "SEXO": _controllers['SEXO']?.text ?? "",
        "PATERNO": _controllers['PATERNO']?.text ?? "",
        "MATERNO": _controllers['MATERNO']?.text ?? "",
        "NOMBRE": _controllers['NOMBRES']?.text ?? "",
        "DOMICILIO": _controllers['DOMICILIO']?.text ?? "",
        "MUNICIPIO": _controllers['MUNICIPIO']?.text ?? "",
        "NACIMIENTO": _controllers['NACIMIENTO']?.text ?? "",
        "SECCION": _controllers['SECCION']?.text ?? "",
        "VIGENCIA": vigenciaAnio,
        "CURP": _controllers['CURP']?.text ?? "",
        "CLAVE": _controllers['CLAVE']?.text ?? "",
        "COLONIA": _controllers['COLONIA']?.text ?? "",
        "CODIGO_POSTAL": _controllers['CODIGO_POSTAL']?.text ?? "",
        "CALLE": _controllers['CALLE']?.text ?? "",
        "NUMERO": _controllers['NUMERO']?.text ?? "",
        "imagenb64": _frontImage != null ? base64Encode(_frontImage!) : "",
        "imagen_face": _faceImage != null ? base64Encode(_faceImage!) : "",
        "ine_trasera": _backImage != null ? base64Encode(_backImage!) : "",
      };

      final String reqBody = json.encode(body);
      
      final Map<String, dynamic> logBody = Map.from(body);
      if (logBody['imagenb64'].toString().length > 30) logBody['imagenb64'] = '[BASE64_FRENTE_AQUI]';
      if (logBody['imagen_face'].toString().length > 30) logBody['imagen_face'] = '[BASE64_ROSTRO_AQUI]';
      if (logBody['ine_trasera'].toString().length > 30) logBody['ine_trasera'] = '[BASE64_REVERSO_AQUI]';
      
      debugPrint('Enviando petición a la API con BODY: ${json.encode(logBody)}');

      final response = await http.post(
        Uri.parse('https://scaa.olgasosa.mx/api/v1/seccion/crear/dev'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${token ?? ""}',
        },
        body: reqBody,
      ).timeout(const Duration(seconds: 15));

      debugPrint('Status POST final: ${response.statusCode}');
      debugPrint('Body POST final: ${response.body}');
      return response;
    } catch (e) {
      debugPrint('Error en POST final: $e');
      return null;
    }
  }

  Future<void> _saveFinalData() async {
    final prefs = await SharedPreferences.getInstance();
    
    Map<String, dynamic> record = {
      'timestamp': DateTime.now().toIso8601String(),
      'TELEFONO': _controllers['TELEFONO']!.text.isNotEmpty ? _controllers['TELEFONO']!.text : 'N/D',
      'NOMBRES': _controllers['NOMBRES']!.text.isNotEmpty ? _controllers['NOMBRES']!.text : 'N/D',
      'PATERNO': _controllers['PATERNO']!.text.isNotEmpty ? _controllers['PATERNO']!.text : 'N/D',
      'MATERNO': _controllers['MATERNO']!.text.isNotEmpty ? _controllers['MATERNO']!.text : 'N/D',
      'CURP': _controllers['CURP']!.text.isNotEmpty ? _controllers['CURP']!.text : 'N/D',
      'CLAVE': _controllers['CLAVE']!.text.isNotEmpty ? _controllers['CLAVE']!.text : 'N/D',
      'SEXO': _controllers['SEXO']!.text.isNotEmpty ? _controllers['SEXO']!.text : 'N/D',
      'NACIMIENTO': _controllers['NACIMIENTO']!.text.isNotEmpty ? _controllers['NACIMIENTO']!.text : 'N/D',
      'SECCION': _controllers['SECCION']!.text.isNotEmpty ? _controllers['SECCION']!.text : 'N/D',
      'VIGENCIA': _controllers['VIGENCIA']!.text.isNotEmpty ? _controllers['VIGENCIA']!.text : 'N/D',
      'DOMICILIO': _controllers['DOMICILIO']!.text.isNotEmpty ? _controllers['DOMICILIO']!.text : 'N/D',
      'MUNICIPIO': _controllers['MUNICIPIO']!.text.isNotEmpty ? _controllers['MUNICIPIO']!.text : 'N/D',
      'COLONIA': _controllers['COLONIA']!.text.isNotEmpty ? _controllers['COLONIA']!.text : 'N/D',
      'CODIGO_POSTAL': _controllers['CODIGO_POSTAL']!.text.isNotEmpty ? _controllers['CODIGO_POSTAL']!.text : 'N/D',
      'CALLE': _controllers['CALLE']!.text.isNotEmpty ? _controllers['CALLE']!.text : 'N/D',
      'NUMERO': _controllers['NUMERO']!.text.isNotEmpty ? _controllers['NUMERO']!.text : 'N/D',
      // Imágenes en base64
      'imagenb64': _frontImage != null ? base64Encode(_frontImage!) : '',
      'imagen_face': _faceImage != null ? base64Encode(_faceImage!) : '',
      'ine_trasera': _backImage != null ? base64Encode(_backImage!) : '',
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
    if (showResults) return Scaffold(backgroundColor: Colors.black, body: _buildResultsView());
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildCameraView(),
          if (_showFrontPreview)
            Positioned.fill(child: _buildFrontPreview()),
        ],
      ),
    );
  }

  Widget _buildFrontPreview() {
    return Stack(
      children: [
        Container(color: Colors.black),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withOpacity(0.6),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.memory(
                _frontImage!,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 24, left: 24, right: 20,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48).withOpacity(0.95),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.white, size: 28),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Verifica la legibilidad',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: 32, left: 24, right: 24,
              bottom: MediaQuery.of(context).padding.bottom + 24,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '¿Los datos son legibles y sin brillo?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _frontImage = null;
                            _showFrontPreview = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Color(0xFFE11D48), width: 2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Reintentar', style: TextStyle(color: Color(0xFFE11D48), fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isCapturingBack = true;
                            _showFrontPreview = false;
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE11D48),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('Continuar al\nREVERSO', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 14, height: 1.2, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
          if (_frozenCameraFrame != null)
            Positioned.fill(
              child: RawImage(
                image: _frozenCameraFrame,
                fit: BoxFit.fill,
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
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 24,
                left: 24,
                right: 20,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFE11D48).withOpacity(0.95), // Color primario
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10)],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.white, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _isCapturingBack 
                          ? 'Mantén la posición para\ncapturar el REVERSO.'
                          : 'Mantén la posición para\ncapturar el FRENTE.',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black26),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: (screenH + frameH) / 2 + 24,
            left: 0, right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isCapturing) ...[
                  const SizedBox(
                    width: 28, height: 28,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  ),
                  const SizedBox(height: 12),
                  const Text('Capturando...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
                ] else ...[
                  const Icon(Icons.center_focus_weak_rounded, color: Colors.white54, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    _isCapturingBack ? 'Alinea el REVERSO de tu credencial' : 'Alinea el FRENTE de tu credencial',
                    style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _iconBtn(
                      _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded, 
                      onTap: _toggleTorch, 
                      active: _torchOn,
                      size: 56,
                    ),
                    GestureDetector(
                      onTap: _onCapture,
                      child: Container(
                        width: 76, height: 76,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isCapturing ? Colors.white54 : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    _iconBtn(
                      Icons.flip_camera_ios_rounded, 
                      onTap: _switchCamera, 
                      size: 56,
                    ),
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
                      _faceImage = null;
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
              if (_faceImage != null) ...[  
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ROSTRO DETECTADO', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_faceImage!, height: 100, fit: BoxFit.cover),
                ),
              ],
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
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator(color: Color(0xFFE11D48))),
              );
              final response = await _sendDataToApi();
              await _saveFinalData();
              if (!mounted) return;
              
              Navigator.pop(context); // Cierra el modal de carga

              bool isSuccess = response != null && (response.statusCode == 200 || response.statusCode == 201);

              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                isDismissible: isSuccess,
                enableDrag: isSuccess,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (context) {
                  return Container(
                    padding: EdgeInsets.only(
                      left: 24, 
                      right: 24, 
                      top: 20, 
                      bottom: MediaQuery.of(context).padding.bottom + 24,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(height: 24),
                        Text(isSuccess ? '¡Registro Guardado!' : 'Error al Guardar', 
                             style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isSuccess ? Colors.black87 : const Color(0xFFE11D48))),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: (isSuccess ? const Color(0xFFE11D48) : Colors.black).withOpacity(0.3), blurRadius: 20, spreadRadius: 5)
                            ],
                          ),
                          child: Icon(isSuccess ? Icons.check_rounded : Icons.close_rounded, color: const Color(0xFFE11D48), size: 60),
                        ),
                        const SizedBox(height: 20),
                        Text(isSuccess 
                             ? 'Tu información se ha guardado correctamente.'
                             : 'No se pudo guardar la información en el servidor.', 
                             textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.black87)),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context); // Cierra bottom sheet
                              if (isSuccess) Navigator.pop(context); // Regresa a home solo si fue exitoso
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE11D48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(isSuccess ? 'Entendido' : 'Cerrar', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
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
            _faceImage = null;
          }),
          child: const Text('Volver a escanear', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _buildUnifiedDataCard() {
    return _card(children: [
      _numericField('Teléfono de Contacto', _controllers['TELEFONO']!, maxLength: 10, isHighlight: true),
      _textField('Nombre(s)', _controllers['NOMBRES']!),
      _textField('Apellido Paterno', _controllers['PATERNO']!),
      _textField('Apellido Materno', _controllers['MATERNO']!),
      _textField('CURP', _controllers['CURP']!),
      _textField('Clave de Elector', _controllers['CLAVE']!),
      _sexoDropdown(),
      _dateField('Nacimiento', _controllers['NACIMIENTO']!),
      _numericField('Sección', _controllers['SECCION']!, maxLength: 4),
      _dateField('Vigencia', _controllers['VIGENCIA']!),
      _textField('Domicilio', _controllers['DOMICILIO']!, maxLines: 3),
      _textField('Municipio', _controllers['MUNICIPIO']!),
      _textField('Colonia', _controllers['COLONIA']!),
      _numericField('Código Postal', _controllers['CODIGO_POSTAL']!, maxLength: 5),
      _textField('Calle', _controllers['CALLE']!),
      _numericField('Número', _controllers['NUMERO']!, last: true),
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

  // ─── Campo de texto libre ───────────────────────────────────────────────────
  Widget _textField(String label, TextEditingController controller, {bool last = false, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.black45, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF3F4F6))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE11D48), width: 1.5)),
            suffixIconConstraints: BoxConstraints(minWidth: 20, minHeight: 20),
            suffixIcon: Icon(Icons.edit_rounded, color: Colors.black26, size: 16),
          ),
        ),
        if (!last) const SizedBox(height: 16),
      ],
    );
  }

  // ─── Campo numérico con longitud máxima ────────────────────────────────────
  Widget _numericField(String label, TextEditingController controller, {bool last = false, int? maxLength, bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(), style: TextStyle(color: isHighlight ? const Color(0xFFE11D48) : Colors.black45, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
            if (isHighlight) ...[
              const SizedBox(width: 4),
              const Icon(Icons.star_rounded, color: Color(0xFFE11D48), size: 10),
            ],
          ],
        ),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.phone, // Formato telefónico
          maxLength: maxLength,
          style: TextStyle(color: const Color(0xFF1F2937), fontSize: 16, fontWeight: isHighlight ? FontWeight.w900 : FontWeight.bold),
          decoration: InputDecoration(
            isDense: true,
            counterText: maxLength != null ? '' : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: isHighlight ? const Color(0xFFE11D48).withOpacity(0.2) : const Color(0xFFF3F4F6))),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE11D48), width: 1.5)),
            suffixIconConstraints: const BoxConstraints(minWidth: 20, minHeight: 20),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (maxLength != null)
                  Text('$maxLength díg.', style: const TextStyle(color: Colors.black26, fontSize: 10)),
                const SizedBox(width: 4),
                Icon(isHighlight ? Icons.phone_android_rounded : Icons.tag_rounded, color: isHighlight ? const Color(0xFFE11D48) : Colors.black26, size: 16),
              ],
            ),
          ),
        ),
        if (!last) const SizedBox(height: 16),
      ],
    );
  }

  // ─── Selector de fecha ─────────────────────────────────────────────────────
  Widget _dateField(String label, TextEditingController controller, {bool last = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.black45, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        TextFormField(
          controller: controller,
          readOnly: true,
          style: const TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'DD/MM/AAAA',
            hintStyle: TextStyle(color: Colors.black26, fontSize: 14),
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF3F4F6))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE11D48), width: 1.5)),
            suffixIconConstraints: BoxConstraints(minWidth: 20, minHeight: 20),
            suffixIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFFE11D48), size: 18),
          ),
          onTap: () async {
            // Intentar parsear la fecha actual del campo
            DateTime? initial;
            final parts = controller.text.split('/');
            if (parts.length == 3) {
              try {
                initial = DateTime(
                  int.parse(parts[2]),
                  int.parse(parts[1]),
                  int.parse(parts[0]),
                );
              } catch (_) {}
            }
            final DateTime? picked = await showDatePicker(
              context: context,
              initialDate: initial ?? DateTime(1990),
              firstDate: DateTime(1900),
              lastDate: DateTime(2100),
              locale: const Locale('es', 'MX'),
              builder: (context, child) {
                return Theme(
                  data: ThemeData.light().copyWith(
                    colorScheme: const ColorScheme.light(
                      primary: Color(0xFFE11D48),
                      onPrimary: Colors.white,
                      surface: Colors.white,
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFFE11D48)),
                    ),
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              final day = picked.day.toString().padLeft(2, '0');
              final month = picked.month.toString().padLeft(2, '0');
              final year = picked.year.toString();
              controller.text = '$day/$month/$year';
            }
          },
        ),
        if (!last) const SizedBox(height: 16),
      ],
    );
  }

  // ─── Dropdown SEXO (H / M) ─────────────────────────────────────────────────
  Widget _sexoDropdown({bool last = false}) {
    final validValues = ['H', 'M'];
    final currentVal = _controllers['SEXO']!.text;
    final dropdownVal = validValues.contains(currentVal) ? currentVal : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SEXO', style: TextStyle(color: Colors.black45, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
        DropdownButtonFormField<String>(
          value: dropdownVal,
          isExpanded: true,
          dropdownColor: Colors.white,
          icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFFE11D48)),
          style: const TextStyle(color: Color(0xFF1F2937), fontSize: 16, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 8),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF3F4F6))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFE11D48), width: 1.5)),
          ),
          items: const [
            DropdownMenuItem(
              value: 'H', 
              child: Text('H – Hombre', style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold))
            ),
            DropdownMenuItem(
              value: 'M', 
              child: Text('M – Mujer', style: TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold))
            ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _controllers['SEXO']!.text = val);
          },
        ),
        if (!last) const SizedBox(height: 16),
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
