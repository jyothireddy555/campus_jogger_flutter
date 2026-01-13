import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const MyApp());
}

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
          const SnackBar(content: Text("Authentication failed")),
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
          gradient: LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
        ),
        child: Center(
          child: Card(
            elevation: 15,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.bolt_rounded, size: 70, color: Colors.blueAccent),
                  const Text("Campus Connect", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : () => signIn(context),
                    icon: _loading ? const SizedBox.shrink() : Image.asset("assets/google.png", height: 24),
                    label: _loading ? const CircularProgressIndicator() : const Text("Sign in with Google"),
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
  bool isJogging = false;
  int _currentIndex = 0;
  late PageController _pageController;
  late IO.Socket socket;
  List<dynamic> activeJoggers = [];
  final MapController _mapController = MapController();


  // Ground Center Coordinates (Update these to your specific campus ground)
  final LatLngBounds groundBounds = LatLngBounds(
    LatLng(14.337061, 78.536599), // South-West corner
    LatLng(14.337592, 78.539344), // North-East corner
  );


  @override
  void initState() {
    super.initState();
    userName = widget.name;
    _pageController = PageController(initialPage: _currentIndex);
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }

    socket = IO.io(AppConfig.socketUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build());

    socket.connect();
    socket.on("active_joggers", (data) {
      if (mounted) setState(() => activeJoggers = data);
    });
  }

  @override
  void dispose() {
    socket.off("active_joggers");
    socket.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /* ---------------- UI HELPERS ---------------- */

  Widget statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget homeContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(child: statCard("Early Bird", "Rahul", Icons.wb_sunny, Colors.orange)),
              const SizedBox(width: 10),
              Expanded(child: statCard("Top Run", "8.4 km", Icons.whatshot, Colors.redAccent)),
              const SizedBox(width: 10),
              Expanded(child: statCard("Personal", "2.1 km", Icons.person, Colors.blueAccent)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.radar, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              const Text("LIVE TRACK", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const Spacer(),
              ElevatedButton(
                onPressed: isJogging ? stopJog : showStartJogDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isJogging ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(isJogging ? "STOP" : "START"),
              ),
            ],
          ),
        ),
        Expanded(child: groundView()),
      ],
    );
  }

  Widget groundView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCameraFit: CameraFit.bounds(
              bounds: groundBounds,
              padding: const EdgeInsets.fromLTRB(60, 30, 60, 30),
            ),

            // 🔥 ROTATE MAP
            initialRotation: 90, // degrees
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.example.campusconnect',
            ),

            MarkerLayer(
              markers: activeJoggers.map((j) {
                return Marker(
                  width: 36,
                  height: 36,
                  point: LatLng(j['lat'], j['lng']),
                  child: const Icon(
                    Icons.directions_run,
                    color: Colors.red,
                    size: 28,
                  ),
                );
              }).toList(),
            ),
          ],
        )
      ),
    );
  }



  /* ---------------- LOGIC ---------------- */

  void showStartJogDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Start Session"),
        content: const Text("Join the ground? Your location will be shared live."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Later")),
          ElevatedButton(onPressed: () { Navigator.pop(context); startJog(); }, child: const Text("Start")),
        ],
      ),
    );
  }

  void startJog() {
    setState(() => isJogging = true);
    socket.emit("start_jog", {
      "name": userName,
      "avatar": remoteImageUrl ?? "",
      "lat": 0.0002, "lng": 0.0003, // Tiny realistic offsets
    });
  }

  void stopJog() {
    setState(() => isJogging = false);
    socket.emit("stop_jog");
  }

  void openProfileSheet() {
    final controller = TextEditingController(text: userName);
    File? tempImage = localImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (picked != null) setSheetState(() => tempImage = File(picked.path));
                },
                child: CircleAvatar(
                  radius: 55,
                  backgroundImage: tempImage != null ? FileImage(tempImage!)
                      : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
                  child: tempImage == null && remoteImageUrl == null ? const Icon(Icons.camera_alt) : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(controller: controller, decoration: const InputDecoration(labelText: "Full Name")),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : () async {
                    setSheetState(() => _isSaving = true);
                    var request = http.MultipartRequest("POST", Uri.parse(AppConfig.updateProfileUrl));
                    request.fields['email'] = widget.email;
                    request.fields['profile_name'] = controller.text;
                    if (tempImage != null) {
                      request.files.add(await http.MultipartFile.fromPath('profile_image', tempImage!.path));
                    }
                    var response = await request.send();
                    if (mounted && response.statusCode == 200) {
                      setState(() { userName = controller.text; localImage = tempImage; });
                      Navigator.pop(context);
                    }
                    if (mounted) setSheetState(() => _isSaving = false);
                  },
                  child: const Text("Save"),
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
        backgroundColor: Colors.white,
        title: GestureDetector(
          onTap: openProfileSheet,
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: localImage != null ? FileImage(localImage!)
                    : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
                child: localImage == null && remoteImageUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            onPressed: () async {
              await _googleSignIn.signOut();
              if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: [homeContent(), const StatsPage(), const AllStatsPage()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => _pageController.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Stats"),
          BottomNavigationBarItem(icon: Icon(Icons.public), label: "Global"),
        ],
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("My Stats"));
}

class AllStatsPage extends StatelessWidget {
  const AllStatsPage({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text("Leaderboard"));
}