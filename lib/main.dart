import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

// Global instance to ensure sign-in/sign-out consistency
final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email'],
  serverClientId: AppConfig.googleWebClientId,
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginPage(),
    );
  }
}

/* ========================= LOGIN PAGE ========================= */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;

  Future<void> signIn(BuildContext context) async {
    setState(() => _loading = true);

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final auth = await account.authentication;

      if (auth.idToken == null) throw "ID Token is null";

      final res = await http.post(
        Uri.parse(AppConfig.backendUrl),
        body: {"id_token": auth.idToken!},
      );

      final data = jsonDecode(res.body);

      if (data["status"] == "success") {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => HomePage(
              name: data["name"],
              email: data["email"],
              profileImageUrl: data["profile_image"],
            ),
          ),
        );
      } else {
        throw "Backend login failed";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login failed")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
          ),
        ),
        child: Center(
          child: Card(
            elevation: 10,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school, size: 60, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text("Campus Connect", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text("Sign in with your college email", style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: _loading ? const SizedBox.shrink() : Image.asset("assets/google.png", height: 22),
                      label: _loading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
                          : const Text("Sign in with Google", style: TextStyle(fontSize: 16)),
                      onPressed: _loading ? null : () => signIn(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ========================= HOME PAGE ========================= */

class HomePage extends StatefulWidget {
  final String name;
  final String email;
  final String? profileImageUrl;

  const HomePage({super.key, required this.name, required this.email, this.profileImageUrl});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late String userName;
  File? localImage; // To hold newly picked file
  String? remoteImageUrl; // To hold URL from DB
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    userName = widget.name;
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }
  }

  // Helper to decide which image source to use
  ImageProvider? _getImageProvider(File? local, String? remote) {
    if (local != null) return FileImage(local);
    if (remote != null) return NetworkImage(remote);
    return null;
  }

  void openProfileSheet() {
    final controller = TextEditingController(text: userName);
    File? tempPickedImage = localImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  File? picked = await pickImage();
                  if (picked != null) setSheetState(() => tempPickedImage = picked);
                },
                child: CircleAvatar(
                  radius: 50,
                  backgroundImage: tempPickedImage != null
                      ? FileImage(tempPickedImage!)
                      : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
                  child: (tempPickedImage == null && remoteImageUrl == null)
                      ? const Icon(Icons.person, size: 50) : null,
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: "Your Name", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Exit")),
                  ElevatedButton(
                    onPressed: _isSaving ? null : () async {
                      setSheetState(() => _isSaving = true);
                      bool success = await saveProfile(controller.text, tempPickedImage);

                      if (mounted) {
                        if (success) {
                          setState(() {
                            userName = controller.text;
                            localImage = tempPickedImage;
                          });
                          Navigator.pop(context);
                        }
                        setSheetState(() => _isSaving = false);
                      }
                    },
                    child: _isSaving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Save"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<File?> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    return picked != null ? File(picked.path) : null;
  }

  Future<bool> saveProfile(String name, File? image) async {
    try {
      var request = http.MultipartRequest("POST", Uri.parse(AppConfig.updateProfileUrl));
      request.fields['email'] = widget.email;
      request.fields['profile_name'] = name;

      if (image != null) {
        request.files.add(await http.MultipartFile.fromPath('profile_image', image.path));
      }

      var response = await request.send();
      return response.statusCode == 200;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Update failed")));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: GestureDetector(
          onTap: openProfileSheet,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: _getImageProvider(localImage, remoteImageUrl),
                child: (localImage == null && remoteImageUrl == null)
                    ? const Icon(Icons.person, size: 18) : null,
              ),
              const SizedBox(width: 10),
              Text(userName),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _googleSignIn.signOut();
              if (mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Text("Welcome $userName 👋", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ),
    );
  }
}