import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/philippines_locations.dart';
import 'login_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();

  String? _selectedProvince;
  String? _selectedMunicipality;
  String? _selectedBarangay;

  List<String> _provinces = [];
  List<String> _municipalities = [];
  List<String> _barangays = [];

  bool _loading = false;
  bool _loadingLocations = true;

  @override
  void initState() {
    super.initState();
    _loadProvinces();
  }

  Future<void> _loadProvinces() async {
    setState(() => _loadingLocations = true);
    
    final provinces = await PhilippinesLocations.getProvinces();
    
    if (!mounted) return;
    
    setState(() {
      _provinces = provinces;
      _loadingLocations = false;
    });
  }

  Future<void> _onProvinceChanged(String? province) async {
    if (province == null) return;

    setState(() {
      _selectedProvince = province;
      _selectedMunicipality = null;
      _selectedBarangay = null;
      _municipalities = [];
      _barangays = [];
      _loadingLocations = true;
    });

    final municipalities = await PhilippinesLocations.getMunicipalities(province);

    if (!mounted) return;

    setState(() {
      _municipalities = municipalities;
      _loadingLocations = false;
    });
  }

  Future<void> _onMunicipalityChanged(String? municipality) async {
    if (municipality == null || _selectedProvince == null) return;

    setState(() {
      _selectedMunicipality = municipality;
      _selectedBarangay = null;
      _barangays = [];
      _loadingLocations = true;
    });

    final barangays = await PhilippinesLocations.getBarangays(
      _selectedProvince!,
      municipality,
    );

    if (!mounted) return;

    setState(() {
      _barangays = barangays;
      _loadingLocations = false;
    });
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedProvince == null) {
      _showError("Please select a province");
      return;
    }
    if (_selectedMunicipality == null) {
      _showError("Please select a municipality");
      return;
    }
    if (_selectedBarangay == null) {
      _showError("Please select a barangay");
      return;
    }

    setState(() => _loading = true);

    final res = await AuthService.signup(
      _username.text.trim(),
      _password.text.trim(),
      _fullName.text.trim(),
      _email.text.trim(),
      _phone.text.trim(),
      _selectedProvince!,
      _selectedMunicipality!,
      _selectedBarangay!,
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (res["ok"]) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Account created successfully!")),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      _showError(res['error'] ?? "Signup failed");
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("❌ $message"),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FA),
      appBar: AppBar(
        title: const Text("Create Account"),
        backgroundColor: const Color(0xFF2C7A2C),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              const Text(
                "Join GASsight",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7A2C),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Create an account to start reporting infestations",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),

              // Account Information
              _sectionTitle("Account Information", Icons.person),
              const SizedBox(height: 12),
              _field("Username", _username, icon: Icons.account_circle),
              _field("Password", _password, isPassword: true, icon: Icons.lock),
              
              const SizedBox(height: 20),

              // Personal Information
              _sectionTitle("Personal Information", Icons.badge),
              const SizedBox(height: 12),
              _field("Full Name", _fullName, icon: Icons.person_outline),
              _field("Email", _email, icon: Icons.email),
              _field("Phone Number", _phone, icon: Icons.phone),

              const SizedBox(height: 20),

              // Location Information
              _sectionTitle("Location Information", Icons.location_on),
              const SizedBox(height: 12),

              // Province Dropdown
              _locationDropdown(
                label: "Province",
                value: _selectedProvince,
                items: _provinces,
                onChanged: _onProvinceChanged,
                icon: Icons.map,
              ),

              // Municipality Dropdown
              _locationDropdown(
                label: "Municipality / City",
                value: _selectedMunicipality,
                items: _municipalities,
                onChanged: _onMunicipalityChanged,
                icon: Icons.location_city,
                enabled: _selectedProvince != null,
              ),

              // Barangay Dropdown
              _locationDropdown(
                label: "Barangay",
                value: _selectedBarangay,
                items: _barangays,
                onChanged: (value) => setState(() => _selectedBarangay = value),
                icon: Icons.home,
                enabled: _selectedMunicipality != null,
              ),

              const SizedBox(height: 30),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _loading ? null : _signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C7A2C),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle),
                            SizedBox(width: 8),
                            Text(
                              "Create Account",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 16),

              // Back to Login
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Already have an account? Login"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF2C7A2C), size: 22),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C7A2C),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool isPassword = false,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextFormField(
          controller: controller,
          obscureText: isPassword,
          validator: (v) =>
              v == null || v.trim().isEmpty ? "Required field" : null,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon != null
                ? Icon(icon, color: const Color(0xFF2C7A2C))
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _locationDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: const Color(0xFF2C7A2C)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: enabled ? Colors.white : Colors.grey.shade100,
          ),
          items: items.isEmpty
              ? null
              : items
                  .map((item) => DropdownMenuItem(
                        value: item,
                        child: Text(
                          item,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ))
                  .toList(),
          onChanged: enabled ? onChanged : null,
          validator: (v) => v == null ? "Please select $label" : null,
          isExpanded: true,
          hint: Text(
            enabled
                ? "Select $label"
                : "Please select ${label.toLowerCase() == 'municipality / city' ? 'province' : label.toLowerCase() == 'barangay' ? 'municipality' : 'previous'} first",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }
}