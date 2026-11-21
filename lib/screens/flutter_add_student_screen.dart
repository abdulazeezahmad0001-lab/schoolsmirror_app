import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class FlutterAddStudentScreen extends StatefulWidget {
  final String? token;

  const FlutterAddStudentScreen({super.key, this.token});

  @override
  State<FlutterAddStudentScreen> createState() => _FlutterAddStudentScreenState();
}

class _FlutterAddStudentScreenState extends State<FlutterAddStudentScreen> {
  final _formKey = GlobalKey<FormState>();

  static const _primary = Color(0xFF4361ee);
  static const _violet = Color(0xFF7c3aed);
  static const _bg = Color(0xFFf0f4ff);
  static const _dark = Color(0xFF0f172a);
  static const _muted = Color(0xFF64748b);
  static const _border = Color(0xFFe2e8f0);
  static const _green = Color(0xFF10b981);

  final _nameController = TextEditingController();
  final _idController = TextEditingController();
  final _passwordController = TextEditingController();
  final _admissionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _parentPhoneController = TextEditingController();

  String _gender = 'Male';
  int? _classId;
  String? _className;

  bool _isLoading = false;
  bool _obscurePassword = true;
  List<dynamic> _classes = [];
  bool _loadingClasses = true;
  String? _tokenError;

  // Image upload
  XFile? _pickedImage;
  Uint8List? _pickedBytes;
  String? _imageError;
  static const int _maxImageBytes = 500 * 1024; // 500 KB

  // Live duplicate checks (like web users.php)
  String? _idStatus; // null | 'checking' | 'ok' | 'exists'
  String? _idMessage;
  String? _admissionStatus;
  String? _admissionMessage;

  Future<String?> _getToken() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) {
      return widget.token!.trim();
    }
    try {
      await ApiClient.loadToken();
      final t = ApiClient.token;
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in [
        'auth_token', 'token', 'api_token', 'access_token', 'accessToken',
        'bearer_token', 'user_token', 'session_token', 'jwt', 'jwt_token',
      ]) {
        final v = prefs.getString(k);
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fetchClasses();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _idController.dispose();
    _passwordController.dispose();
    _admissionController.dispose();
    _phoneController.dispose();
    _parentNameController.dispose();
    _parentPhoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchClasses() async {
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        setState(() {
          _tokenError = 'No session token found. Please log out and log back in.';
          _loadingClasses = false;
        });
        return;
      }
      final res = await http.get(
        Uri.parse(
          'https://schoolsmirror.com/flutter_fetch_classes.php?token=${Uri.encodeComponent(token)}',
        ),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => _classes = data['classes'] ?? []);
      } else {
        setState(() => _tokenError = data['message']?.toString());
      }
    } catch (e) {
      debugPrint('Error loading classes: $e');
    } finally {
      if (mounted) setState(() => _loadingClasses = false);
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _idController.clear();
    _passwordController.clear();
    _admissionController.clear();
    _phoneController.clear();
    _parentNameController.clear();
    _parentPhoneController.clear();
    setState(() {
      _gender = 'Male';
      _classId = null;
      _className = null;
      _obscurePassword = true;
      _idStatus = null;
      _idMessage = null;
      _admissionStatus = null;
      _admissionMessage = null;
      _pickedImage = null;
      _pickedBytes = null;
      _imageError = null;
    });
  }


  // Debounced live validation for ID / admission (mirrors web admin)
  void _onIdChanged(String value) {
    _idStatus = null;
    _idMessage = null;
    setState(() {});
    Future.delayed(const Duration(milliseconds: 450), () {
      if (_idController.text.trim() == value.trim()) {
        _checkField('idnumber', value.trim());
      }
    });
  }

  void _onAdmissionChanged(String value) {
    _admissionStatus = null;
    _admissionMessage = null;
    setState(() {});
    Future.delayed(const Duration(milliseconds: 450), () {
      if (_admissionController.text.trim() == value.trim()) {
        _checkField('admission_number', value.trim());
      }
    });
  }

  Future<void> _checkField(String field, String value) async {
    if (value.isEmpty) {
      setState(() {
        if (field == 'idnumber') {
          _idStatus = null;
          _idMessage = null;
        } else {
          _admissionStatus = null;
          _admissionMessage = null;
        }
      });
      return;
    }

    setState(() {
      if (field == 'idnumber') {
        _idStatus = 'checking';
        _idMessage = 'Checking...';
      } else {
        _admissionStatus = 'checking';
        _admissionMessage = 'Checking...';
      }
    });

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) return;

      final uri = Uri.parse('https://schoolsmirror.com/flutter_check_field.php').replace(
        queryParameters: {
          'token': token,
          'field': field,
          'value': value,
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);

      if (!mounted) return;
      final exists = data['exists'] == true;
      final msg = (data['message'] ?? '').toString();

      setState(() {
        if (field == 'idnumber') {
          _idStatus = exists ? 'exists' : 'ok';
          _idMessage = msg.isEmpty
              ? (exists ? 'ID number already exists' : 'ID number is available')
              : msg;
        } else {
          _admissionStatus = exists ? 'exists' : 'ok';
          _admissionMessage = msg.isEmpty
              ? (exists ? 'Admission number already exists' : 'Admission number is available')
              : msg;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (field == 'idnumber') {
          _idStatus = null;
          _idMessage = null;
        } else {
          _admissionStatus = null;
          _admissionMessage = null;
        }
      });
    }
  }

  Future<void> _showSuccessDialog({
    required String name,
    required String idNumber,
    required String gender,
    required String className,
    String? admission,
    String? phone,
    String? parentName,
    String? parentPhone,
    dynamic userId,
  }) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: _green.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, color: _green, size: 44),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Student Added!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _dark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The student has been registered successfully.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFf8fafc),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      children: [
                        _detailRow(Icons.person_outline, 'Full name', name),
                        _detailRow(Icons.badge_outlined, 'ID number', idNumber),
                        _detailRow(Icons.wc_outlined, 'Gender', gender),
                        _detailRow(Icons.class_outlined, 'Class', className.isEmpty ? '—' : className),
                        if (admission != null && admission.isNotEmpty)
                          _detailRow(Icons.numbers, 'Admission no.', admission),
                        if (phone != null && phone.isNotEmpty)
                          _detailRow(Icons.phone_outlined, 'Phone', phone),
                        if (parentName != null && parentName.isNotEmpty)
                          _detailRow(Icons.family_restroom, 'Parent', parentName),
                        if (parentPhone != null && parentPhone.isNotEmpty)
                          _detailRow(Icons.phone_android, 'Parent phone', parentPhone),
                        if (userId != null)
                          _detailRow(Icons.tag, 'User ID', '$userId'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            Navigator.of(context).pop(true);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _dark,
                            side: const BorderSide(color: _border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Back to Dashboard'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _clearForm();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Add Another'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _muted),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: _dark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _pickImage() async {
    setState(() => _imageError = null);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 1200,
      );
      if (file == null) return;

      final name = file.name.toLowerCase();
      final path = file.path.toLowerCase();
      final okExt = name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg') ||
          path.endsWith('.png');
      if (!okExt) {
        setState(() {
          _imageError = 'Only JPG and PNG images are allowed';
          _pickedImage = null;
          _pickedBytes = null;
        });
        return;
      }

      final bytes = await file.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        setState(() {
          _imageError = 'Image must be under 500 KB (yours is ${(bytes.length / 1024).toStringAsFixed(0)} KB)';
          _pickedImage = null;
          _pickedBytes = null;
        });
        return;
      }

      setState(() {
        _pickedImage = file;
        _pickedBytes = bytes;
        _imageError = null;
      });
    } catch (e) {
      setState(() => _imageError = 'Could not pick image: $e');
    }
  }

  void _removeImage() {
    setState(() {
      _pickedImage = null;
      _pickedBytes = null;
      _imageError = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_idStatus == 'exists') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This ID number already exists. Please use another.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_admissionStatus == 'exists') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This admission number already exists. Please use another.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class'), backgroundColor: Colors.red),
      );
      return;
    }

    final name = _nameController.text.trim();
    final idNumber = _idController.text.trim();
    final gender = _gender;
    final className = _className ??
        (_classes.cast<dynamic>().firstWhere(
              (c) => int.tryParse('${c['class_id']}') == _classId,
              orElse: () => null,
            )?['class_name']?.toString() ??
            '');
    final admission = _admissionController.text.trim();
    final phone = _phoneController.text.trim();
    final parentName = _parentNameController.text.trim();
    final parentPhone = _parentPhoneController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Missing token. Please log out and log back in.');
      }

      final fields = <String, String>{
        'token': token,
        'fullname': name,
        'idnumber': idNumber,
        'gender': gender,
        'password': password,
        'class_id': _classId.toString(),
        'admission_number': admission,
        'phone': phone,
        'parent_name': parentName,
        'parent_phone': parentPhone,
      };

      final endpoints = <Uri>[
        Uri.parse('https://schoolsmirror.com/flutter_add_student.php'),
        Uri.parse('https://schoolsmirror.com/flutter_add_student'),
      ];

      http.Response? response;
      Object? lastError;

      for (final base in endpoints) {
        try {
          final uri = base.replace(queryParameters: {'token': token});
          final request = http.MultipartRequest('POST', uri);
          request.fields.addAll(fields);

          if (_pickedBytes != null && _pickedBytes!.isNotEmpty) {
            final fname = _pickedImage?.name ?? 'photo.jpg';
            final lower = fname.toLowerCase();
            final isPng = lower.endsWith('.png');
            request.files.add(http.MultipartFile.fromBytes(
              'image',
              _pickedBytes!,
              filename: fname,
              contentType: MediaType('image', isPng ? 'png' : 'jpeg'),
            ));
          }

          final client = http.Client();
          try {
            final streamed = await client.send(request).timeout(const Duration(seconds: 40));
            response = await http.Response.fromStream(streamed);
            if (response.statusCode > 0) break;
          } finally {
            client.close();
          }
        } catch (e) {
          lastError = e;
        }
      }

      if (response == null) {
        throw Exception('Failed to reach server: $lastError');
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        throw Exception('Server Error (${response.statusCode}): ${response.body}');
      }

      if (data['success'] == true) {
        if (!mounted) return;
        await _showSuccessDialog(
          name: name,
          idNumber: idNumber,
          gender: gender,
          className: className,
          admission: admission,
          phone: phone,
          parentName: parentName,
          parentPhone: parentPhone,
          userId: data['data']?['user_id'],
        );
      } else {
        throw Exception(data['message'] ?? 'Failed to add student');
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Could not add student'),
          content: Text('$e', style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        title: const Text(
          'Add Student',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _clearForm,
            child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loadingClasses
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  if (_tokenError != null) _errorBanner(_tokenError!),
                  _heroCard(),
                  const SizedBox(height: 16),
                  _photoCard(),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Student details',
                    icon: Icons.school_outlined,
                    children: [
                      _field(
                        controller: _nameController,
                        label: 'Full name',
                        icon: Icons.person_outline,
                        required: true,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _idController,
                        label: 'ID number',
                        icon: Icons.badge_outlined,
                        required: true,
                        onChanged: _onIdChanged,
                      ),
                      _statusLine(_idStatus, _idMessage),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _genderField()),
                          const SizedBox(width: 12),
                          Expanded(child: _classField()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _passwordField(),
                      const SizedBox(height: 12),
                      _field(
                        controller: _admissionController,
                        label: 'Admission no.',
                        icon: Icons.numbers,
                        onChanged: _onAdmissionChanged,
                      ),
                      _statusLine(_admissionStatus, _admissionMessage),
                      const SizedBox(height: 12),
                      _field(
                        controller: _phoneController,
                        label: 'Phone',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _sectionCard(
                    title: 'Parent / Guardian',
                    icon: Icons.family_restroom,
                    children: [
                      _field(
                        controller: _parentNameController,
                        label: 'Parent name',
                        icon: Icons.person_outline,
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        controller: _parentPhoneController,
                        label: 'Parent phone',
                        icon: Icons.phone_android,
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        disabledBackgroundColor: _primary.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_alt_1, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Add Student',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Required fields are marked with *',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_primary, _violet],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person_add_alt_1, color: Colors.white, size: 26),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Register a new student',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Fill in the details below. You can add another student right after.',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _photoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Profile photo', style: TextStyle(fontWeight: FontWeight.w800, color: _dark)),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('JPG or PNG · max 500 KB', style: TextStyle(fontSize: 12, color: _muted)),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _isLoading ? null : _pickImage,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFf8fafc),
                    border: Border.all(color: _primary.withOpacity(0.35), width: 2),
                    image: _pickedBytes != null
                        ? DecorationImage(image: MemoryImage(_pickedBytes!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: _pickedBytes == null
                      ? const Icon(Icons.add_a_photo_outlined, color: _primary, size: 34)
                      : null,
                ),
                if (_pickedBytes != null)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Material(
                      color: _primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _isLoading ? null : _pickImage,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.edit, color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _isLoading ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: Text(_pickedBytes == null ? 'Choose photo' : 'Change photo'),
              ),
              if (_pickedBytes != null)
                TextButton.icon(
                  onPressed: _isLoading ? null : _removeImage,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                  label: const Text('Remove', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
          if (_imageError != null) ...[
            const SizedBox(height: 6),
            Text(_imageError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _primary),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _dark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _statusLine(String? status, String? message) {
    if (status == null || message == null || message.isEmpty) {
      return const SizedBox.shrink();
    }
    Color color;
    IconData icon;
    if (status == 'checking') {
      color = _muted;
      icon = Icons.hourglass_top_rounded;
    } else if (status == 'exists') {
      color = Colors.red.shade600;
      icon = Icons.cancel_outlined;
    } else {
      color = _green;
      icon = Icons.check_circle_outline;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4, bottom: 2),
      child: Row(
        children: [
          if (status == 'checking')
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool required = false,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      decoration: _decoration(
        required ? '$label *' : label,
        icon,
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: _decoration('Password *', Icons.lock_outline).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 20,
            color: _muted,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Required';
        if (v.length < 6) return 'Min 6 characters';
        return null;
      },
    );
  }

  Widget _genderField() {
    return DropdownButtonFormField<String>(
      value: _gender,
      decoration: _decoration('Gender *', Icons.wc_outlined),
      items: const [
        DropdownMenuItem(value: 'Male', child: Text('Male')),
        DropdownMenuItem(value: 'Female', child: Text('Female')),
      ],
      onChanged: (v) => setState(() => _gender = v ?? 'Male'),
    );
  }

  Widget _classField() {
    return DropdownButtonFormField<int>(
      value: _classId,
      isExpanded: true,
      decoration: _decoration('Class *', Icons.class_outlined),
      items: _classes.map((c) {
        final id = int.tryParse('${c['class_id']}');
        return DropdownMenuItem<int>(
          value: id,
          child: Text(
            '${c['class_name'] ?? 'Unknown'}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: (v) {
        String? name;
        for (final c in _classes) {
          if (int.tryParse('${c['class_id']}') == v) {
            name = c['class_name']?.toString();
            break;
          }
        }
        setState(() {
          _classId = v;
          _className = name;
        });
      },
      validator: (v) => v == null ? 'Required' : null,
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20, color: _muted),
      filled: true,
      fillColor: const Color(0xFFf8fafc),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
    );
  }
}
