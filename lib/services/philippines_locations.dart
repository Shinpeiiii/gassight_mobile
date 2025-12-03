import 'dart:convert';
import 'package:http/http.dart' as http;

class PhilippinesLocations {
  // Using PSGC API (Philippine Standard Geographic Code)
  static const String _apiBaseUrl = "https://psgc.gitlab.io/api";

  /// ==================================================
  /// GET ALL PROVINCES
  /// ==================================================
  static Future<List<String>> getProvinces() async {
    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/provinces/'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        
        final provinces = data
            .map((item) => item['name'] as String)
            .toList();
        
        provinces.sort(); // Sort alphabetically
        return provinces;
      }

      // Fallback to common provinces if API fails
      return _getFallbackProvinces();
    } catch (e) {
      print('Error fetching provinces: $e');
      return _getFallbackProvinces();
    }
  }

  /// ==================================================
  /// GET MUNICIPALITIES BY PROVINCE
  /// ==================================================
  static Future<List<String>> getMunicipalities(String province) async {
    try {
      // First, get all provinces to find the code
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/provinces/'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> provinces = jsonDecode(response.body);
        
        // Find the province code
        final provinceData = provinces.firstWhere(
          (p) => p['name'] == province,
          orElse: () => null,
        );

        if (provinceData != null) {
          final provinceCode = provinceData['code'];
          
          // Fetch municipalities for this province
          final munResponse = await http.get(
            Uri.parse('$_apiBaseUrl/provinces/$provinceCode/cities-municipalities/'),
          ).timeout(const Duration(seconds: 10));

          if (munResponse.statusCode == 200) {
            final List<dynamic> data = jsonDecode(munResponse.body);
            
            final municipalities = data
                .map((item) => item['name'] as String)
                .toList();
            
            municipalities.sort();
            return municipalities;
          }
        }
      }

      // Fallback
      return _getFallbackMunicipalities(province);
    } catch (e) {
      print('Error fetching municipalities: $e');
      return _getFallbackMunicipalities(province);
    }
  }

  /// ==================================================
  /// GET BARANGAYS BY PROVINCE AND MUNICIPALITY
  /// ==================================================
  static Future<List<String>> getBarangays(
    String province,
    String municipality,
  ) async {
    try {
      // Get province code
      final provinceResponse = await http.get(
        Uri.parse('$_apiBaseUrl/provinces/'),
      ).timeout(const Duration(seconds: 10));

      if (provinceResponse.statusCode == 200) {
        final List<dynamic> provinces = jsonDecode(provinceResponse.body);
        
        final provinceData = provinces.firstWhere(
          (p) => p['name'] == province,
          orElse: () => null,
        );

        if (provinceData != null) {
          final provinceCode = provinceData['code'];
          
          // Get municipality code
          final munResponse = await http.get(
            Uri.parse('$_apiBaseUrl/provinces/$provinceCode/cities-municipalities/'),
          ).timeout(const Duration(seconds: 10));

          if (munResponse.statusCode == 200) {
            final List<dynamic> municipalities = jsonDecode(munResponse.body);
            
            final municipalityData = municipalities.firstWhere(
              (m) => m['name'] == municipality,
              orElse: () => null,
            );

            if (municipalityData != null) {
              final municipalityCode = municipalityData['code'];
              
              // Fetch barangays
              final brgyResponse = await http.get(
                Uri.parse('$_apiBaseUrl/cities-municipalities/$municipalityCode/barangays/'),
              ).timeout(const Duration(seconds: 10));

              if (brgyResponse.statusCode == 200) {
                final List<dynamic> data = jsonDecode(brgyResponse.body);
                
                final barangays = data
                    .map((item) => item['name'] as String)
                    .toList();
                
                barangays.sort();
                return barangays;
              }
            }
          }
        }
      }

      // Fallback
      return _getFallbackBarangays();
    } catch (e) {
      print('Error fetching barangays: $e');
      return _getFallbackBarangays();
    }
  }

  /// ==================================================
  /// FALLBACK DATA (IN CASE API IS DOWN)
  /// ==================================================
  
  static List<String> _getFallbackProvinces() {
    return [
      'Abra',
      'Agusan del Norte',
      'Agusan del Sur',
      'Aklan',
      'Albay',
      'Antique',
      'Apayao',
      'Aurora',
      'Basilan',
      'Bataan',
      'Batanes',
      'Batangas',
      'Benguet',
      'Biliran',
      'Bohol',
      'Bukidnon',
      'Bulacan',
      'Cagayan',
      'Camarines Norte',
      'Camarines Sur',
      'Camiguin',
      'Capiz',
      'Catanduanes',
      'Cavite',
      'Cebu',
      'Cotabato',
      'Davao de Oro',
      'Davao del Norte',
      'Davao del Sur',
      'Davao Occidental',
      'Davao Oriental',
      'Dinagat Islands',
      'Eastern Samar',
      'Guimaras',
      'Ifugao',
      'Ilocos Norte',
      'Ilocos Sur',
      'Iloilo',
      'Isabela',
      'Kalinga',
      'La Union',
      'Laguna',
      'Lanao del Norte',
      'Lanao del Sur',
      'Leyte',
      'Maguindanao',
      'Marinduque',
      'Masbate',
      'Metro Manila',
      'Misamis Occidental',
      'Misamis Oriental',
      'Mountain Province',
      'Negros Occidental',
      'Negros Oriental',
      'Northern Samar',
      'Nueva Ecija',
      'Nueva Vizcaya',
      'Occidental Mindoro',
      'Oriental Mindoro',
      'Palawan',
      'Pampanga',
      'Pangasinan',
      'Quezon',
      'Quirino',
      'Rizal',
      'Romblon',
      'Samar',
      'Sarangani',
      'Siquijor',
      'Sorsogon',
      'South Cotabato',
      'Southern Leyte',
      'Sultan Kudarat',
      'Sulu',
      'Surigao del Norte',
      'Surigao del Sur',
      'Tarlac',
      'Tawi-Tawi',
      'Zambales',
      'Zamboanga del Norte',
      'Zamboanga del Sur',
      'Zamboanga Sibugay',
    ];
  }

  static List<String> _getFallbackMunicipalities(String province) {
    // Sample municipalities for common provinces
    final Map<String, List<String>> provinceMunicipalities = {
      'Benguet': [
        'Baguio City',
        'La Trinidad',
        'Itogon',
        'Sablan',
        'Tuba',
        'Tublay',
        'Atok',
        'Bakun',
        'Bokod',
        'Buguias',
        'Kabayan',
        'Kapangan',
        'Kibungan',
        'Mankayan',
      ],
      'Laguna': [
        'Alaminos',
        'Bay',
        'Biñan City',
        'Cabuyao City',
        'Calamba City',
        'Calauan',
        'Cavinti',
        'Famy',
        'Kalayaan',
        'Liliw',
        'Los Baños',
        'Luisiana',
        'Lumban',
        'Mabitac',
        'Magdalena',
        'Majayjay',
        'Nagcarlan',
        'Paete',
        'Pagsanjan',
        'Pakil',
        'Pangil',
        'Pila',
        'Rizal',
        'San Pablo City',
        'San Pedro City',
        'Santa Cruz',
        'Santa Maria',
        'Santa Rosa City',
        'Siniloan',
        'Victoria',
      ],
      'Cebu': [
        'Alcantara',
        'Alcoy',
        'Alegria',
        'Aloguinsan',
        'Argao',
        'Asturias',
        'Badian',
        'Balamban',
        'Bantayan',
        'Barili',
        'Bogo City',
        'Boljoon',
        'Borbon',
        'Carcar City',
        'Carmen',
        'Catmon',
        'Cebu City',
        'Compostela',
        'Consolacion',
        'Cordova',
        'Daanbantayan',
        'Dalaguete',
        'Danao City',
        'Dumanjug',
        'Ginatilan',
        'Lapu-Lapu City',
        'Liloan',
        'Madridejos',
        'Malabuyoc',
        'Mandaue City',
        'Medellin',
        'Minglanilla',
        'Moalboal',
        'Naga City',
        'Oslob',
        'Pilar',
        'Pinamungajan',
        'Poro',
        'Ronda',
        'Samboan',
        'San Fernando',
        'San Francisco',
        'San Remigio',
        'Santa Fe',
        'Santander',
        'Sibonga',
        'Sogod',
        'Tabogon',
        'Tabuelan',
        'Talisay City',
        'Toledo City',
        'Tuburan',
        'Tudela',
      ],
    };

    return provinceMunicipalities[province] ?? ['Please select a valid province'];
  }

  static List<String> _getFallbackBarangays() {
    return [
      'Barangay 1 (Poblacion)',
      'Barangay 2 (Poblacion)',
      'Barangay 3 (Poblacion)',
      'Barangay 4',
      'Barangay 5',
      'Barangay 6',
      'Barangay 7',
      'Barangay 8',
      'Please select municipality to load barangays',
    ];
  }
}