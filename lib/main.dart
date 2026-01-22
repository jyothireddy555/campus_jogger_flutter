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

  // UI and Logic State
  late String userName;
  File? localImage;
  String? remoteImageUrl;
  bool _isSaving = false;
  bool isJogging = false;
  int _currentIndex = 0;
  late PageController _pageController;
  late IO.Socket socket;

  // Notifiers for High Performance UI
  final ValueNotifier<List<JoggerData>> _activeJoggersNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isInsideGround = ValueNotifier(false);
  final ValueNotifier<double> _bearingToGround = ValueNotifier(0.0);
  final ValueNotifier<double> _totalDistance = ValueNotifier(0.0);
  final ValueNotifier<double> _avgSpeed = ValueNotifier(0.0);
  final ValueNotifier<double> _calories = ValueNotifier(0.0);

  // Map and Tracking
  final MapController _mapController = MapController();
  LatLng? _myCurrentPos;
  StreamSubscription<Position>? _positionStream;

  // Ground Configuration
  //static const LatLng groundCenter = LatLng(14.337488449262446, 78.53780234296367); // Center of your bounds
  // 1. The 4 corners of your trapezium
  static const List<LatLng> groundPolygonPoints = [
    LatLng(14.337558643627412, 78.53617772777397),
    LatLng(14.337096080275323, 78.53620723207409),
    LatLng(14.33692716645528, 78.53940978968112),
    LatLng(14.337646998317902, 78.53944465839942),
  ];

  // 2. The center point for the navigation arrow to point to
  static const LatLng groundCenter = LatLng(14.337488449262446, 78.53780234296367);

  // Math/Stat tracking
  DateTime? _startTime;
  LatLng? _lastRecordedPos;
  DateTime? _lastUpdateTime;
  Timer? _socketBatchTimer;
  LatLng? _pendingSocketUpdate;

  @override
  void initState() {
    super.initState();
    userName = widget.name;
    _pageController = PageController(initialPage: _currentIndex);
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }
    _initSocket();
    _startLiveTracking(); // Start locating user immediately
  }

  void _initSocket() {
    socket = IO.io(AppConfig.socketUrl, IO.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .build());
    socket.connect();

    socket.on("active_joggers", (data) {
      if (!mounted) return;
      compute(_parseJoggers, {'data': data, 'userName': userName}).then((result) {
        if (!mounted) return;
        _activeJoggersNotifier.value = result['joggers'];
      });
    });
  }

  static Map<String, dynamic> _parseJoggers(Map<String, dynamic> params) {
    final data = params['data'] as List;
    final joggers = data.map((j) => JoggerData(name: j['name'], lat: j['lat'], lng: j['lng'])).toList();
    return {'joggers': joggers};
  }

  // CORE TRACKING LOGIC (Always running)
  void _startLiveTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
        forceLocationManager: true, // Crucial for Mock GPS
        intervalDuration: Duration(seconds: 1),
      ),
    ).listen((Position position) {
      final newPos = LatLng(position.latitude, position.longitude);

      if (mounted) {
        setState(() => _myCurrentPos = newPos);

        // 1. Move camera to follow user
        _mapController.move(newPos, _mapController.camera.zoom);

        // 2. Geofencing check
        // New check using the polygon math instead of a simple box
        _isInsideGround.value = _isPointInPolygon(newPos, groundPolygonPoints);

        // 3. Directional Math (Arrow pointing to ground)
        if (!_isInsideGround.value) {
          _bearingToGround.value = Geolocator.bearingBetween(
            newPos.latitude, newPos.longitude,
            groundCenter.latitude, groundCenter.longitude,
          );
        }

        // 4. If currently in a session, update distance/stats
        if (isJogging) {
          _updateMovement(position);
          _broadcastLocation(newPos);
        }
      }
    });
  }

  void _updateMovement(Position pos) {
    final now = DateTime.now();
    final newPos = LatLng(pos.latitude, pos.longitude);
    if (pos.accuracy > 100) return;

    if (_lastRecordedPos == null) {
      _lastRecordedPos = newPos;
      _lastUpdateTime = now;
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastRecordedPos!.latitude, _lastRecordedPos!.longitude,
      newPos.latitude, newPos.longitude,
    );

    if (distance < 0.8) return;

    final duration = now.difference(_lastUpdateTime!).inMilliseconds;
    if (duration > 0) {
      final speedKmh = (distance / (duration / 1000)) * 3.6;
      if (speedKmh < 30) {
        _totalDistance.value += distance;
        _lastRecordedPos = newPos;
        _lastUpdateTime = now;
        _updateStats();
      }
    }
  }

  void _updateStats() {
    if (_startTime == null) return;
    final seconds = DateTime.now().difference(_startTime!).inSeconds;
    if (seconds > 2) _avgSpeed.value = (_totalDistance.value / seconds) * 3.6;
    _calories.value = (_totalDistance.value / 1000) * 70;
  }

  void _broadcastLocation(LatLng pos) {
    _pendingSocketUpdate = pos;
    _socketBatchTimer?.cancel();
    _socketBatchTimer = Timer(const Duration(seconds: 1), () {
      if (_pendingSocketUpdate != null) {
        socket.emit("update_location", {
          "lat": _pendingSocketUpdate!.latitude,
          "lng": _pendingSocketUpdate!.longitude,
        });
        _pendingSocketUpdate = null;
      }
    });
  }

  void startJog() {
    setState(() {
      isJogging = true;
      _startTime = DateTime.now();
      _totalDistance.value = 0;
      _avgSpeed.value = 0;
      _calories.value = 0;
    });
    socket.emit("start_jog", {"name": userName, "lat": _myCurrentPos!.latitude, "lng": _myCurrentPos!.longitude});
  }

  void stopJog() {
    setState(() => isJogging = false);
    socket.emit("stop_jog");
  }

  // UI COMPONENTS
  Widget _buildGuidanceArrow() {
    return ValueListenableBuilder2<bool, double>(
      _isInsideGround,
      _bearingToGround,
      builder: (context, isInside, bearing, _) {
        if (isInside || isJogging) return const SizedBox.shrink();

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.8), borderRadius: BorderRadius.circular(20)),
                child: const Text("Ground is this way! 🏃", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              Transform.rotate(
                angle: (bearing * (3.14159 / 180)),
                child: const Icon(Icons.navigation, size: 60, color: Colors.blueAccent),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String title, ValueNotifier<double> valueNotifier, String Function(double) formatter, IconData icon, Color color) {
    return ValueListenableBuilder<double>(
      valueListenable: valueNotifier,
      builder: (context, value, child) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: color.withOpacity(0.1), blurRadius: 10)],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
              Text(formatter(value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget homeContent() {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(child: _statCard("Distance", _totalDistance, (v) => "${(v / 1000).toStringAsFixed(2)} km", Icons.route, Colors.green)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard("Speed", _avgSpeed, (v) => "${v.toStringAsFixed(1)} km/h", Icons.speed, Colors.blue)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard("Calories", _calories, (v) => "${v.toStringAsFixed(0)}", Icons.local_fire_department, Colors.orange)),
                ],
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _isInsideGround,
              builder: (context, isInside, _) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (isInside || isJogging) ? (isJogging ? stopJog : startJog) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isJogging ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(isJogging ? "STOP SESSION" : (isInside ? "START JOGGING" : "LOCKED: ENTER GROUND")),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Expanded(child: _groundView()),
          ],
        ),
        _buildGuidanceArrow(),
      ],
    );
  }

  Widget _groundView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: groundCenter,
            initialZoom: 17,
            interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.example.campusconnect',
            ),
            PolygonLayer(
              polygons: [
                Polygon(
                  points: groundPolygonPoints,
                  color: Colors.blue.withOpacity(0.2),
                  borderColor: Colors.blueAccent,
                  borderStrokeWidth: 3,
                  isFilled: true,
                ),
              ],
            ),
            ValueListenableBuilder<List<JoggerData>>(
              valueListenable: _activeJoggersNotifier,
              builder: (context, joggers, _) {
                return MarkerLayer(
                  markers: [
                    ...joggers.map((j) => Marker(
                      point: LatLng(j.lat, j.lng),
                      child: const Icon(Icons.directions_run, color: Colors.red, size: 28),
                    )),
                    if (_myCurrentPos != null)
                      Marker(
                        point: _myCurrentPos!,
                        child: const Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    var counter = 0;
    var i = 0;
    var xinters = 0.0;
    var p1 = polygon[0];
    var n = polygon.length;

    for (i = 1; i <= n; i++) {
      var p2 = polygon[i % n];
      if (point.latitude > (p1.latitude < p2.latitude ? p1.latitude : p2.latitude)) {
        if (point.latitude <= (p1.latitude > p2.latitude ? p1.latitude : p2.latitude)) {
          if (point.longitude <= (p1.longitude > p2.longitude ? p1.longitude : p2.longitude)) {
            if (p1.latitude != p2.latitude) {
              xinters = (point.latitude - p1.latitude) * (p2.longitude - p1.longitude) / (p2.latitude - p1.latitude) + p1.longitude;
              if (p1.longitude == p2.longitude || point.longitude <= xinters) {
                counter++;
              }
            }
          }
        }
      }
      p1 = p2;
    }
    return counter % 2 != 0;
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _socketBatchTimer?.cancel();
    socket.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // Standard Profile/Appbar Build Methods
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: localImage != null ? FileImage(localImage!) : (remoteImageUrl != null ? NetworkImage(remoteImageUrl!) : null),
              child: (localImage == null && remoteImageUrl == null) ? const Icon(Icons.person) : null,
            ),
            const SizedBox(width: 10),
            Text(userName, style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              await _googleSignIn.signOut();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage()));
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
        onTap: (i) => _pageController.jumpToPage(i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Stats"),
          BottomNavigationBarItem(icon: Icon(Icons.leaderboard), label: "Global"),
        ],
      ),
    );
  }
}

// MULTI-LISTENABLE HELPER
class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext context, A a, B b, Widget? child) builder;
  const ValueListenableBuilder2(this.first, this.second, {required this.builder, super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<A>(
    valueListenable: first,
    builder: (context, a, _) => ValueListenableBuilder<B>(
      valueListenable: second,
      builder: (context, b, _) => builder(context, a, b, null),
    ),
  );
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