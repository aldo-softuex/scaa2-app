class AddressParser {
  
  /// Extrae la colonia de un domicilio mexicano.
  static String extraerColoniaDeDomicilio(String? domicilio) {
    if (domicilio == null || domicilio.isEmpty) {
      return "";
    }
    
    String domicilioUpper = domicilio.toUpperCase();
    
    // Patrones de colonias en orden de prioridad (más específicos primero)
    List<String> patrones = [
      r'U\s+HAB\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                // U HAB NOMBRE 12345
      r'UNIDAD\s+HABITACIONAL\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',    // UNIDAD HABITACIONAL NOMBRE
      r'INFONAVIT\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                // INFONAVIT NOMBRE
      r'CONJ\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // CONJ NOMBRE
      r'CONJUNTO\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                 // CONJUNTO NOMBRE
      r'RESIDENCIAL\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',              // RESIDENCIAL NOMBRE
      r'BARR\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // BARR NOMBRE
      r'BARRIO\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                   // BARRIO NOMBRE
      r'RCHO\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // RCHO NOMBRE
      r'RANCHO\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                   // RANCHO NOMBRE
      r'AMPL\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // AMPL NOMBRE
      r'AMPLIACION\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',               // AMPLIACION NOMBRE
      r'ZONA\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                     // ZONA NOMBRE
      r'NUEVA\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                    // NUEVA NOMBRE
      r'SEC\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                   // SEC NOMBRE
      r'SECCION\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // SECCION NOMBRE
      r'FRACC\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                 // FRACC NOMBRE
      r'FRACCIONAMIENTO\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',          // FRACCIONAMIENTO NOMBRE
      r'EJ\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                    // EJ NOMBRE
      r'EJIDO\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                    // EJIDO NOMBRE
      r'COL\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                   // COL NOMBRE
      r'COLONIA\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // COLONIA NOMBRE
      r'PRIV\.?\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // PRIV NOMBRE
      r'PRIVADA\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                  // PRIVADA NOMBRE
      r'UNIDAD\s+([A-Z0-9\s]+?)(?:\s+\d{5}|$)',                   // UNIDAD NOMBRE
    ];
    
    for (String patron in patrones) {
      RegExp regExp = RegExp(patron);
      Match? match = regExp.firstMatch(domicilioUpper);
      
      if (match != null) {
        String coloniaExtraida = match.group(0)!.trim();
        
        // Limpiar espacios múltiples
        coloniaExtraida = coloniaExtraida.replaceAll(RegExp(r'\s+'), ' ');
        
        // Validar que no sea la SECCION electoral
        if (RegExp(r'SEC(CION)?\s+\d{4}$').hasMatch(coloniaExtraida)) {
          continue;
        }
        
        return coloniaExtraida;
      }
    }
    
    // Si no se encontró con los patrones, buscar código postal y tomar lo anterior
    RegExp regExpCp = RegExp(r'(\d{5})$');
    Match? matchCp = regExpCp.firstMatch(domicilioUpper);
    
    if (matchCp != null) {
      String cp = matchCp.group(1)!;
      String antesCp = domicilioUpper.substring(0, matchCp.start).trim();
      
      List<String> palabras = antesCp.split(RegExp(r'\s+'));
      if (palabras.length >= 2) {
        int startIndex = palabras.length >= 3 ? palabras.length - 3 : 0;
        String posibleColonia = '${palabras.sublist(startIndex).join(' ')} $cp';
        return posibleColonia;
      }
    }
    
    return "";
  }

  /// Extrae el código postal de un domicilio mexicano.
  static String extraerCodigoPostal(String? domicilio) {
    if (domicilio == null || domicilio.isEmpty) {
      return "";
    }
    
    String domicilioLimpio = domicilio.trim();
    
    // ESTRATEGIA 1: Buscar exactamente 5 dígitos al final del domicilio
    RegExp regExpFinal = RegExp(r'(\d{5})$');
    Match? matchFinal = regExpFinal.firstMatch(domicilioLimpio);
    if (matchFinal != null) {
      return matchFinal.group(1)!;
    }
    
    // ESTRATEGIA 2: Buscar 5 dígitos precedidos por espacio
    RegExp regExpEspacio = RegExp(r'\s(\d{5})(?:\s|$)');
    Iterable<Match> matchesEspacio = regExpEspacio.allMatches(domicilioLimpio);
    if (matchesEspacio.isNotEmpty) {
      return matchesEspacio.last.group(1)!;
    }
    
    // ESTRATEGIA 3: Buscar cualquier secuencia de 5 dígitos (fallback)
    RegExp regExpAll = RegExp(r'\b(\d{5})\b');
    Iterable<Match> matchesAll = regExpAll.allMatches(domicilioLimpio);
    if (matchesAll.isNotEmpty) {
      // Filtrar años (que empiecen con 20)
      List<String> cpsValidos = matchesAll
          .map((m) => m.group(1)!)
          .where((cp) => !cp.startsWith('20'))
          .toList();
          
      if (cpsValidos.isNotEmpty) {
        return cpsValidos.last;
      } else {
        return matchesAll.last.group(1)!;
      }
    }
    
    return "";
  }

  /// Extrae la calle de un domicilio mexicano.
  static String extraerCalleDeDomicilio(String? domicilio, String? colonia) {
    if (domicilio == null || domicilio.isEmpty) {
      return "";
    }
    
    // Si no hay colonia, intentar extraer usando el código postal
    if (colonia == null || colonia.isEmpty) {
      RegExp regExpCp = RegExp(r'\s(\d{5})$');
      Match? matchCp = regExpCp.firstMatch(domicilio);
      if (matchCp != null) {
        return domicilio.substring(0, matchCp.start).trim();
      }
      return domicilio.trim();
    }
    
    String coloniaUpper = colonia.toUpperCase();
    String domicilioUpper = domicilio.toUpperCase();
    
    // Buscar la posición donde empieza la colonia en el domicilio
    int posColonia = domicilioUpper.indexOf(coloniaUpper);
    
    if (posColonia != -1) {
      // Extraer todo lo que está ANTES de la colonia
      return domicilio.substring(0, posColonia).trim();
    }
    
    // Si no se encontró la colonia exacta, intentar buscar el prefijo de la colonia
    List<String> prefijos = [
      'U HAB', 'UNIDAD HABITACIONAL', 'INFONAVIT', 'CONJ', 'CONJUNTO',
      'RESIDENCIAL', 'BARR', 'BARRIO', 'RCHO', 'RANCHO', 'AMPL', 'AMPLIACION',
      'ZONA', 'NUEVA', 'SEC', 'SECCION', 'FRACC', 'FRACCIONAMIENTO',
      'EJ', 'EJIDO', 'COL', 'COLONIA', 'PRIV', 'PRIVADA', 'UNIDAD'
    ];
    
    for (String prefijo in prefijos) {
      // Buscar el prefijo con punto opcional y espacio
      RegExp regExpPrefijo = RegExp(r'\b' + RegExp.escape(prefijo) + r'\.?\s');
      Match? match = regExpPrefijo.firstMatch(domicilioUpper);
      if (match != null) {
        // Extraer todo lo que está ANTES del prefijo
        String calle = domicilio.substring(0, match.start).trim();
        if (calle.isNotEmpty) return calle;
      }
    }
    
    // Si no se pudo extraer, buscar el código postal y tomar todo lo anterior
    RegExp regExpCpFallback = RegExp(r'\s(\d{5})$');
    Match? matchCpFallback = regExpCpFallback.firstMatch(domicilio);
    
    if (matchCpFallback != null) {
      String antesCp = domicilio.substring(0, matchCpFallback.start).trim();
      List<String> palabras = antesCp.split(RegExp(r'\s+'));
      
      if (palabras.length > 3) {
        // Tomar las primeras palabras como calle
        String calle = palabras.sublist(0, palabras.length - 3).join(' ').trim();
        if (calle.isNotEmpty) return calle;
      }
    }
    
    return domicilio.trim();
  }

  /// Extrae el número de la calle.
  static String extraerNumeroDeCalle(String? calle) {
    if (calle == null || calle.isEmpty) {
      return "";
    }
    
    String calleUpper = calle.toUpperCase();
    
    // Patrones para "Sin número"
    RegExp regExpSn = RegExp(r'\b(S/N|S\.?\s*N\.?|SIN NUMERO|SN)\b');
    Match? matchSn = regExpSn.firstMatch(calleUpper);
    if (matchSn != null) {
      return matchSn.group(0)!;
    }
    
    // Extraer número al final de la calle (ej. "123", "123-A", "123 A", "INT 4")
    // Se asegura de tomar prefijos opcionales NO. o NUM.
    RegExp regExpNum = RegExp(r'\b(?:NO\.?\s*|NUM\.?\s*|NÚMERO\s*)?(\d+[A-Z]?(\s*[-/]\s*\d+[A-Z]?)?(?:\s+(?:INT|EXT|LOTE|MZ|MANZANA)\.?\s*[A-Z0-9-]+)?)(?=\s*$|$)');
    Match? matchNum = regExpNum.firstMatch(calleUpper);
    if (matchNum != null) {
      return matchNum.group(1)!.trim();
    }
    
    // Fallback: Buscar la última secuencia de dígitos y/o letras que parezca número
    RegExp regExpGenerico = RegExp(r'\b(\d+[A-Z]?)\b');
    Iterable<Match> matches = regExpGenerico.allMatches(calleUpper);
    if (matches.isNotEmpty) {
      return matches.last.group(1)!;
    }
    
    return "";
  }
}
