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

// Global instance to maintain session consistency across the app
final GoogleSignIn _googleSignIn = GoogleSignIn(
  scopes: ['email'],
  serverClientId: AppConfig.googleWebClientId,
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const LoginPage(),
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
          const SnackBar(content: Text("Authentication failed. Please try again.")),
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
            elevation: 15,
            shadowColor: Colors.black45,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded, size: 70, color: Colors.blueAccent),
                  const SizedBox(height: 16),
                  const Text("Campus Connect",
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  const SizedBox(height: 8),
                  Text("Fitness tracking for students",
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 240,
                    height: 55,
                    child: ElevatedButton.icon(
                      icon: _loading
                          ? const SizedBox.shrink()
                          : Image.asset("assets/google.png", height: 24),
                      label: _loading
                          ? const CircularProgressIndicator(strokeWidth: 3)
                          : const Text("Sign in with Google", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      onPressed: _loading ? null : () => signIn(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
  File? localImage;
  String? remoteImageUrl;
  bool _isSaving = false;
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    userName = widget.name;
    _pageController = PageController(initialPage: _currentIndex);
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ImageProvider? _getImageProvider(File? local, String? remote) {
    if (local != null) return FileImage(local);
    if (remote != null) return NetworkImage(remote);
    return null;
  }

  /* ---------------- HOME PAGE UI COMPONENTS ---------------- */

  Widget homeContent() {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          topDashboard(),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.radar, color: Colors.redAccent, size: 18),
                SizedBox(width: 8),
                Text("LIVE STADIUM TRACK",
                    style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 12)),
                Spacer(),
                CircleAvatar(radius: 4, backgroundColor: Colors.redAccent),
                SizedBox(width: 6),
                Text("LIVE", style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(child: groundView()),
        ],
      ),
    );
  }

  Widget topDashboard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(child: statCard("Early Bird", "Rahul", Icons.wb_sunny_rounded, Colors.orange)),
          const SizedBox(width: 12),
          Expanded(child: statCard("Top Run", "8.4 km", Icons.whatshot_rounded, Colors.redAccent)),
          const SizedBox(width: 12),
          Expanded(child: statCard("Personal", "2.1 km", Icons.person_rounded, Colors.blueAccent)),
        ],
      ),
    );
  }

  Widget statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget groundView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Center(
              child: Container(
                width: 260, height: 480,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withOpacity(0.03), width: 40),
                  borderRadius: BorderRadius.circular(130),
                ),
              ),
            ),
            runnerDot(80, 150, Colors.blueAccent, "https://i.pravatar.cc/150?u=1"),
            runnerDot(200, 300, Colors.orangeAccent, "https://i.pravatar.cc/150?u=2"),
            runnerDot(130, 450, Colors.greenAccent, "https://i.pravatar.cc/150?u=3"),
          ],
        ),
      ),
    );
  }

  Widget runnerDot(double x, double y, Color color, String imageUrl) {
    return Positioned(
      left: x, top: y,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(seconds: 2),
        builder: (context, value, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 25 + (value * 20), height: 25 + (value * 20),
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(1 - value)),
              ),
              CircleAvatar(radius: 12, backgroundColor: color,
                  child: CircleAvatar(radius: 10, backgroundImage: NetworkImage(imageUrl))),
            ],
          );
        },
        onEnd: () => setState(() {}),
      ),
    );
  }

  /* ---------------- PROFILE & NAVIGATION ---------------- */

  void openProfileSheet() {
    final controller = TextEditingController(text: userName);
    File? tempPickedImage = localImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final picker = ImagePicker();
                  final picked = await picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) setSheetState(() => tempPickedImage = File(picked.path));
                },
                child: CircleAvatar(
                  radius: 55,
                  backgroundColor: Colors.blue.shade50,
                  backgroundImage: tempPickedImage != null
                      ? FileImage(tempPickedImage!)
                      : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
                  child: tempPickedImage == null && remoteImageUrl == null
                      ? const Icon(Icons.camera_enhance_rounded, size: 35, color: Colors.blue) : null,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: "Full Name",
                  prefixIcon: const Icon(Icons.person_outline),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 55,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : () async {
                    setSheetState(() => _isSaving = true);
                    var request = http.MultipartRequest("POST", Uri.parse(AppConfig.updateProfileUrl));
                    request.fields['email'] = widget.email;
                    request.fields['profile_name'] = controller.text;
                    if (tempPickedImage != null) {
                      request.files.add(await http.MultipartFile.fromPath('profile_image', tempPickedImage!.path));
                    }
                    var response = await request.send();
                    if (mounted) {
                      if (response.statusCode == 200) {
                        setState(() { userName = controller.text; localImage = tempPickedImage; });
                        Navigator.pop(context);
                      }
                      setSheetState(() => _isSaving = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text("Save Changes"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.white,
        title: GestureDetector(
          onTap: openProfileSheet,
          child: Row(
            children: [
              CircleAvatar(radius: 20, backgroundColor: Colors.blue.shade50,
                  backgroundImage: _getImageProvider(localImage, remoteImageUrl),
                  child: (localImage == null && remoteImageUrl == null) ? const Icon(Icons.person, size: 20) : null),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Hello,", style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  Text(userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              onPressed: () async {
                await _googleSignIn.signOut();
                if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
              }),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: [homeContent(), const StatsPage(), const AllStatsPage()],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: false,
          onTap: (i) => _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded), label: "My Stats"),
            BottomNavigationBarItem(icon: Icon(Icons.leaderboard_rounded), label: "All Stats"),
          ],
        ),
      ),
    );
  }
}

/* ========================= SUB PAGES ========================= */

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("Personal Analytics coming soon..."));
}

class AllStatsPage extends StatelessWidget {
  const AllStatsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("Global Leaderboard coming soon..."));
}