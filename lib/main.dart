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
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

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
      ).timeout(const Duration(seconds: 10));

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
                    icon: _loading ? const SizedBox.shrink() : const Icon(Icons.login),
                    label: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text("Sign in with Google"),
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

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late String userName;
  File? localImage;
  String? remoteImageUrl;
  bool _isSaving = false;
  bool isJogging = false;
  int _currentIndex = 0;
  late PageController _pageController;
  late IO.Socket socket;

  // Optimized joggers list with ValueNotifier
  final ValueNotifier<List<JoggerData>> _activeJoggersNotifier = ValueNotifier([]);
  final MapController _mapController = MapController();

  // Optimized Tracking State
  LatLng? _myCurrentPos;
  StreamSubscription<Position>? _positionStream;

  // Stats with ValueNotifiers for granular updates
  final ValueNotifier<double> _totalDistance = ValueNotifier(0.0);
  final ValueNotifier<double> _avgSpeed = ValueNotifier(0.0);
  final ValueNotifier<double> _calories = ValueNotifier(0.0);

  DateTime? _startTime;
  LatLng? _lastRecordedPos;
  DateTime? _lastUpdateTime;

  // Batch socket updates
  Timer? _socketBatchTimer;
  LatLng? _pendingSocketUpdate;

  static final LatLngBounds groundBounds = LatLngBounds(
    const LatLng(14.337061, 78.536599),
    const LatLng(14.337592, 78.539344),
  );

  @override
  void initState() {
    super.initState();
    userName = widget.name;
    _pageController = PageController(initialPage: _currentIndex);
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }
    _initSocket();
  }

  void _initSocket() {
    socket = IO.io(AppConfig.socketUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .setReconnectionDelay(2000)
        .setReconnectionDelayMax(10000)
        .build());

    socket.connect();

    // Debounced socket handler to prevent excessive rebuilds
    socket.on("active_joggers", (data) {
      if (!mounted) return;

      compute(_parseJoggers, {'data': data, 'userName': userName}).then((result) {
        if (!mounted) return;

        _activeJoggersNotifier.value = result['joggers'];

        if (result['myPos'] != null) {
          final newPos = result['myPos'] as LatLng;
          if (_myCurrentPos == null) {
            setState(() => _myCurrentPos = newPos);
          } else {
            // Smooth interpolation instead of animation timer
            setState(() => _myCurrentPos = newPos);
          }
        }
      });
    });
  }

  static Map<String, dynamic> _parseJoggers(Map<String, dynamic> params) {
    final data = params['data'] as List;
    final userName = params['userName'] as String;

    final joggers = data.map((j) => JoggerData(
      name: j['name'],
      lat: j['lat'],
      lng: j['lng'],
    )).toList();

    final me = data.firstWhere((j) => j['name'] == userName, orElse: () => null);
    LatLng? myPos;
    if (me != null) {
      myPos = LatLng(me['lat'], me['lng']);
    }

    return {'joggers': joggers, 'myPos': myPos};
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _socketBatchTimer?.cancel();
    socket.dispose();
    _pageController.dispose();
    _activeJoggersNotifier.dispose();
    _totalDistance.dispose();
    _avgSpeed.dispose();
    _calories.dispose();
    super.dispose();
  }

  void _updateMovement(Position pos) {
    final now = DateTime.now();
    final newPos = LatLng(pos.latitude, pos.longitude);

    // Filter: Accept realistic GPS accuracy for outdoor walking
    //if (pos.accuracy > 100) return;

    if (_lastRecordedPos == null) {
      _lastRecordedPos = newPos;
      _lastUpdateTime = now;
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastRecordedPos!.latitude, _lastRecordedPos!.longitude,
      newPos.latitude, newPos.longitude,
    );

    // Filter: Ignore GPS jitter (< 1 meter)
    if (distance < 1.0) {
      _lastUpdateTime = now;
      return;
    }

    // Filter: Speed check using milliseconds for precision
    final milliseconds = now.difference(_lastUpdateTime!).inMilliseconds;
    if (milliseconds > 0) {
      final speedKmh = (distance / (milliseconds / 1000)) * 3.6;
      // Reject unrealistic speeds (human running max ~20 km/h)
      if (speedKmh > 20) {
        _lastUpdateTime = now;
        return;
      }
    }

    // Update stats efficiently with ValueNotifiers
    _totalDistance.value += distance;
    _lastRecordedPos = newPos;
    _lastUpdateTime = now;
    _updateStats();
  }

  void _updateStats() {
    if (_startTime == null) return;
    final seconds = DateTime.now().difference(_startTime!).inSeconds;
    if (seconds > 5) {
      _avgSpeed.value = (_totalDistance.value / seconds) * 3.6;
    }
    _calories.value = (_totalDistance.value / 1000) * 70 * 1.036;
  }

  void startJog() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    setState(() {
      isJogging = true;
      _startTime = DateTime.now();
      _lastRecordedPos = null;
    });

    _totalDistance.value = 0;
    _avgSpeed.value = 0;
    _calories.value = 0;

    final current = await Geolocator.getCurrentPosition();
    socket.emit("start_jog", {"name": userName, "lat": current.latitude, "lng": current.longitude});

    // Optimized position stream with batched socket updates
    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: Duration(seconds: 1), // Limit update frequency
        foregroundNotificationConfig: ForegroundNotificationConfig(
          notificationText: "Tracking your campus activity",
          notificationTitle: "Jogging Session Active",
          enableWifiLock: true,
        ),
      ),
    ).listen((Position position) {
      final newPos = LatLng(position.latitude, position.longitude);

      // Move map camera smoothly
      _mapController.move(newPos, _mapController.camera.zoom);

      // Update distance & calories
      _updateMovement(position);

      // Update position
      if (_myCurrentPos == null || mounted) {
        setState(() => _myCurrentPos = newPos);
      }

      // Batch socket updates (send every 500ms max)
      _pendingSocketUpdate = newPos;
      _socketBatchTimer?.cancel();
      _socketBatchTimer = Timer(const Duration(milliseconds: 500), () {
        if (_pendingSocketUpdate != null) {
          socket.emit("update_location", {
            "lat": _pendingSocketUpdate!.latitude,
            "lng": _pendingSocketUpdate!.longitude,
          });
          _pendingSocketUpdate = null;
        }
      });
    });
  }

  void stopJog() {
    setState(() => isJogging = false);
    _positionStream?.cancel();
    _socketBatchTimer?.cancel();
    socket.emit("stop_jog");
  }

  Widget _statCard(String title, ValueNotifier<double> valueNotifier, String Function(double) formatter, IconData icon, Color color) {
    return ValueListenableBuilder<double>(
      valueListenable: valueNotifier,
      builder: (context, value, child) {
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
              Text(formatter(value), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  Widget homeContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(child: _statCard("Distance", _totalDistance, (v) => "${(v / 1000).toStringAsFixed(2)} km", Icons.route, Colors.green)),
              Expanded(child: _statCard("Avg Speed", _avgSpeed, (v) => "${v.toStringAsFixed(1)} km/h", Icons.speed, Colors.blue)),
              Expanded(child: _statCard("Calories", _calories, (v) => "${v.toStringAsFixed(0)} kcal", Icons.local_fire_department, Colors.orange)),
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
                onPressed: isJogging ? stopJog : _showStartJogDialog,
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
        Expanded(child: _groundView()),
      ],
    );
  }

  Widget _groundView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: RepaintBoundary(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(bounds: groundBounds, padding: const EdgeInsets.fromLTRB(60, 30, 60, 30)),
              initialRotation: 90,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: 'com.example.campusconnect',
                tileProvider: NetworkTileProvider(),
              ),
              ValueListenableBuilder<List<JoggerData>>(
                valueListenable: _activeJoggersNotifier,
                builder: (context, joggers, child) {
                  return MarkerLayer(
                    markers: [
                      ...joggers.where((j) => j.name != userName).map((j) => Marker(
                        width: 36, height: 36,
                        point: LatLng(j.lat, j.lng),
                        child: const Icon(Icons.directions_run, color: Colors.red, size: 28),
                      )),
                      if (_myCurrentPos != null)
                        Marker(
                          width: 40, height: 40,
                          point: _myCurrentPos!,
                          child: const Icon(Icons.directions_run, color: Colors.blue, size: 32),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showStartJogDialog() {
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

  void _openProfileSheet() {
    final controller = TextEditingController(text: userName);
    File? tempImage = localImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(left: 24, right: 24, top: 24, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 512);
                  if (picked != null) setSheetState(() => tempImage = File(picked.path));
                },
                child: CircleAvatar(
                  radius: 55,
                  backgroundImage: tempImage != null ? FileImage(tempImage!) : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
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
                    try {
                      var request = http.MultipartRequest("POST", Uri.parse(AppConfig.updateProfileUrl));
                      request.fields['email'] = widget.email;
                      request.fields['profile_name'] = controller.text;
                      if (tempImage != null) request.files.add(await http.MultipartFile.fromPath('profile_image', tempImage!.path));
                      var response = await request.send();
                      if (mounted && response.statusCode == 200) {
                        setState(() { userName = controller.text; localImage = tempImage; });
                        Navigator.pop(context);
                      }
                    } finally {
                      if (mounted) setSheetState(() => _isSaving = false);
                    }
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        title: GestureDetector(
          onTap: _openProfileSheet,
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: localImage != null ? FileImage(localImage!) : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
                child: localImage == null && remoteImageUrl == null ? const Icon(Icons.person) : null,
              ),
              const SizedBox(width: 12),
              Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: () async {
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

// Optimized data model
class JoggerData {
  final String name;
  final double lat;
  final double lng;

  JoggerData({required this.name, required this.lat, required this.lng});
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