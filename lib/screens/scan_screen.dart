import 'package:flutter/material.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool isScanning = false;
  bool showResults = false;

  void startScan() {
    setState(() {
      isScanning = true;
    });

    // Simulando el escaneo y extracción de datos de la INE
    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        isScanning = false;
        showResults = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111827), // Dark for camera feel
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white),
        ),
        title: const Text('Escanear INE', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!showResults) ...[
                // Scan Frame with design from image
                Container(
                  width: double.infinity,
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    border: Border.all(color: const Color(0xFFE11D48), width: 2),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          isScanning ? 'Extrayendo...' : 'Alinea la INE dentro del marco',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      ),
                      if (isScanning)
                        const CircularProgressIndicator(color: Color(0xFFE11D48)),
                    ],
                  ),
                ),
                const SizedBox(height: 64),
                // Shutter Button
                InkWell(
                  onTap: isScanning ? null : startScan,
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE11D48),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE11D48).withOpacity(0.4),
                          blurRadius: 30,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 36),
                  ),
                ),
              ] else ...[
                // Results Screen (Extracted Data)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          'Datos Extraídos',
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF374151)),
                        ),
                      ),
                      const SizedBox(height: 32),
                      _buildExtractedField('Nombre', 'JUAN RAMON PEREZ LOMELI'),
                      _buildExtractedField('Clave', 'PRLMJN85041214M200'),
                      _buildExtractedField('CURP', 'PELJ850412HMCRRR05'),
                      const SizedBox(height: 48),
                      // Action Button like image
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE11D48),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: const Text('Confirmar y Enviar',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExtractedField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF6B7280)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF374151)),
            ),
          ),
        ],
      ),
    );
  }
}
