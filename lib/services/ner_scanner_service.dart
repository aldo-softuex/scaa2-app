import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class NERScannerService {
  Interpreter? _interpreter;
  Map<String, int>? _vocab;
  List<String>? _labels;
  final int _maxLen = 120; // La misma que usamos en Python

  Future<void> loadModel() async {
    try {
      debugPrint("[NER_DEBUG] 🚀 Iniciando carga de modelo...");
      
      // Intentamos cargar el modelo con opciones básicas
      InterpreterOptions options = InterpreterOptions();
      
      // Nota: FlexDelegate no se encuentra en esta versión de la librería.
      // Sin embargo, las dependencias en build.gradle deberían permitir que 
      // el modelo cargue si los OPS están bien vinculados nativamente.
      
      _interpreter = await Interpreter.fromAsset(
        'assets/ine_ner_model.tflite',
        options: options,
      );

      // 2. Carga de Vocabulario y Etiquetas
      String vocabString = await rootBundle.loadString('assets/vocab.json');
      _vocab = Map<String, int>.from(json.decode(vocabString));
      debugPrint("[NER_DEBUG] 📚 Vocabulario cargado");

      String labelsString = await rootBundle.loadString('assets/labels.txt');
      _labels = labelsString.split('\n').where((s) => s.isNotEmpty).toList();
      
      debugPrint("✅ [NER_DEBUG] Modelo y Vocab listos");
    } catch (e) {
      debugPrint("❌ [NER_DEBUG] Error crítico cargando el modelo: $e");
    }
  }

  Map<String, dynamic> extraerDatos(String textoOCR) {
    if (_interpreter == null || _vocab == null) return {};

    // 1. Limpieza básica y tokenización
    List<String> palabras = textoOCR.replaceAll('\n', ' ').split(' ');
    palabras.removeWhere((w) => w.trim().isEmpty);

    // Convertir palabras a IDs (usando <OOV> si no existe)
    List<int> tokens = palabras.map((w) {
      return _vocab![w.toLowerCase()] ?? (_vocab!['<OOV>'] ?? 1);
    }).toList();

    // 2. Padding a 120 (Input: [1, 120] con tipo INT32)
    var input = List.generate(1, (_) => List<int>.filled(_maxLen, 0));
    int oovCount = 0;
    for (int i = 0; i < tokens.length && i < _maxLen; i++) {
      input[0][i] = tokens[i];
      if (tokens[i] == (_vocab!['<OOV>'] ?? 1)) oovCount++;
    }
    debugPrint("[NER_DEBUG] 🔢 Tokens procesados: ${tokens.length}. OOV (desconocidos): $oovCount");

    // 3. Preparar la salida (Output: [1, 120, num_etiquetas])
    // Usamos la dimensión exacta que el modelo define en sus metadatos
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    int numLabels = outputShape[2]; 
    var output = List.generate(1, (_) => 
                 List.generate(_maxLen, (_) => 
                 List<double>.filled(numLabels, 0.0)));
    
    // 4. Ejecutar Inferencia
    try {
      debugPrint("[NER_DEBUG] 🛠️ Ejecutando inferencia TFLite...");
      _interpreter!.run(input, output);
      
      // Verificamos si la salida tiene valores reales
      double totalProb = 0;
      for(var p in output[0][0]) totalProb += p;
      if (totalProb == 0) {
        debugPrint("[NER_DEBUG] ❌ ALERTA: El modelo devolvió ceros absolutos.");
      }
    } catch (e) {
      debugPrint("[NER_DEBUG] ❌ Error en inferencia: $e");
    }

    // 5. Decodificar resultados
    Map<String, dynamic> infoExtraida = {
      "NOMBRE": "", "PATERNO": "", "MATERNO": "", "CURP": "", "CLAVE": ""
    };
    List<Map<String, String>> debugTags = [];

    debugPrint("[NER_DEBUG] 🔎 Decodificando ${palabras.length} palabras...");

    for (int i = 0; i < palabras.length && i < _maxLen; i++) {
      List<double> probabilidades = output[0][i];
      int maxIdx = 0;
      double maxProb = -1.0;

      for (int j = 0; j < probabilidades.length; j++) {
        if (probabilidades[j] > maxProb) {
          maxProb = probabilidades[j];
          maxIdx = j;
        }
      }
      
      // Loggear si encontramos algo con prob > 0.5 que no sea 'O'
      if (maxIdx > 0 && maxProb > 0.3) {
        print("🔍 Token $i ('${palabras[i]}'): Etiqueta probable ${_labels![maxIdx]} (confianza: ${(maxProb*100).toStringAsFixed(1)}%)");
      }

      // PRUEBA DE ÍNDICE: Vamos a probar sin el -1 primero, ya que 'O' es el índice 0 en su labels.txt
      // Si maxIdx es 0, es la etiqueta 'O' según su archivo.
      String tag = "O";
      if (maxIdx < _labels!.length) {
        tag = _labels![maxIdx];
      }
      
      String palabra = palabras[i];
      debugTags.add({"word": palabra, "tag": tag});

      if (tag != "O") {
        print("Encontrado: $palabra -> $tag");
        if (tag.contains('NOMBRE')) infoExtraida["NOMBRE"] = "${infoExtraida["NOMBRE"]} $palabra".trim();
        if (tag.contains('PATERNO')) infoExtraida["PATERNO"] = "${infoExtraida["PATERNO"]} $palabra".trim();
        if (tag.contains('MATERNO')) infoExtraida["MATERNO"] = "${infoExtraida["MATERNO"]} $palabra".trim();
        if (tag.contains('CURP')) infoExtraida["CURP"] = palabra.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
        if (tag.contains('CLAVE')) infoExtraida["CLAVE"] = palabra.toUpperCase();
      }
    }

    // Si después de procesar todo NO encontramos nada sustancial, probamos con el offset -1 por si acaso
    // Solo para el reporte de DebugTags
    bool nadaEncontrado = infoExtraida.values.every((v) => v is String && v.isEmpty);
    if (nadaEncontrado) {
      print("⚠️ No se detectó nada con índice directo. Probando con Offset -1...");
      for (int i = 0; i < debugTags.length; i++) {
        int originalIdx = 0;
        double maxP = -1.0;
        for (int j = 0; j < output[0][i].length; j++) {
          if (output[0][i][j] > maxP) { maxP = output[0][i][j]; originalIdx = j; }
        }
        
        if (originalIdx > 0 && (originalIdx - 1) < _labels!.length) {
          String newTag = _labels![originalIdx - 1];
          if (newTag != "O") {
             debugTags[i]["tag"] = "$newTag (?)"; // Marcamos que es un posible acierto con offset
          }
        }
      }
    }

    infoExtraida["DEBUG_TAGS"] = debugTags;
    return infoExtraida;
  }
}
