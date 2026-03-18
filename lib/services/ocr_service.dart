import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';

class OCRService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> extraerTexto(Uint8List imageBytes) async {
    try {
      // 1. ML Kit necesita un archivo físico o un path
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/ocr_temp.png').create();
      await file.writeAsBytes(imageBytes);

      // 2. Procesar la imagen
      final inputImage = InputImage.fromFile(file);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // 3. Obtener el texto perfectamente ordenado por coordenadas
      String fullText = getOrderedText(recognizedText);
      
      return fullText;
    } catch (e) {
      print("❌ Error en OCR: $e");
      return "";
    }
  }

  /// Ordena el texto detectado de arriba a abajo y de izquierda a derecha
  String getOrderedText(RecognizedText recognizedText) {
    // 1. Clonamos la lista de bloques para no mutar el original
    List<TextBlock> blocks = List.from(recognizedText.blocks);
    
    // 2. Ordenar bloques por posición vertical (Y)
    blocks.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

    List<String> orderedWords = [];

    for (var block in blocks) {
      // 3. Ordenar líneas por posición horizontal (X) para evitar saltos raros
      List<TextLine> lines = List.from(block.lines);
      lines.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

      for (var line in lines) {
        for (var element in line.elements) {
          // Normalizar palabra
          String word = element.text.trim();
          if (word.isNotEmpty) {
            orderedWords.add(word);
          }
        }
      }
    }

    // Unimos con un solo espacio y limpiamos espacios múltiples
    return orderedWords.join(" ").replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Extrae y parsea los datos de la zona posterior (MRZ)
  Future<Map<String, String>?> extraerDatosPosterior(Uint8List imageBytes) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/ocr_back_temp.png').create();
      await file.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(file);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      return _parseIneMRZ(recognizedText.text);
    } catch (e) {
      debugPrint("❌ Error detectando MRZ: $e");
      return null;
    }
  }

  Map<String, String>? _parseIneMRZ(String text) {
    final lines = text.split('\n').map((l) => l.replaceAll(' ', '').toUpperCase()).toList();
    
    String? line1, line2, line3;

    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('IDMEX')) {
        line1 = lines[i];
        if (i + 1 < lines.length) line2 = lines[i + 1];
        if (i + 2 < lines.length) line3 = lines[i + 2];
        break;
      }
    }

    if (line1 == null || line1.length < 25) return null;

    // Línea 1
    String electorKey = line1.length >= 18 ? line1.substring(5, 18) : '';
    String section = '';
    final markerIndex = line1.indexOf('<<');
    if (markerIndex != -1 && line1.length >= markerIndex + 6) {
      section = line1.substring(markerIndex + 2, markerIndex + 6);
    }

    // Línea 2
    String birthDate = '', sex = '', expirationDate = '';
    if (line2 != null && line2.length >= 14) {
      birthDate = line2.substring(0, 6);
      sex = line2.substring(7, 8);
      expirationDate = line2.substring(8, 14);
    }

    // Línea 3
    String fullName = '';
    if (line3 != null) {
      fullName = line3.replaceAll('<', ' ').trim();
    }

    return {
      'CLAVE_ELECTOR': electorKey,
      'SECCION': section,
      'NOMBRE_MRZ': fullName,
      'NACIMIENTO': _formatDate(birthDate),
      'SEXO': sex == 'M' ? 'Hombre' : (sex == 'F' ? 'Mujer' : sex),
      'VIGENCIA': _formatDate(expirationDate, isExp: true),
      'RAW_MRZ': '$line1\n$line2\n$line3',
    };
  }

  String _formatDate(String raw, {bool isExp = false}) {
    if (raw.length != 6) return raw;
    final year = raw.substring(0, 2);
    final month = raw.substring(2, 4);
    final day = raw.substring(4, 6);
    final fullYear = isExp ? '20$year' : (int.parse(year) > 25 ? '19$year' : '20$year');
    return '$day/$month/$fullYear';
  }

  void dispose() {
    _textRecognizer.close();
  }
}
