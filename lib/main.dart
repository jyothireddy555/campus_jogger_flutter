import 'package:campus_jogger_flutter/user_details_page.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:fl_chart/fl_chart.dart';

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

  Future<void> _signIn(BuildContext context) async {
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
            builder: (_) => UserDetailsPage(
              userEmail: data["email"],
              userId: data["user_id"],
              userName: data["name"],
              profileImageUrl: data["profile_image"],
            ),
          ),
        );
      } else {
        throw Exception("Backend login failed");
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
          gradient: LinearGradient(
            colors: [Color(0xFF6A11CB), Color(0xFF2575FC)],
          ),
        ),
        child: Center(
          child: Card(
            elevation: 15,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bolt_rounded,
                    size: 70,
                    color: Colors.blueAccent,
                  ),
                  const Text(
                    "Campus Connect",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: _loading ? null : () => _signIn(context),
                    icon: _loading
                        ? const SizedBox.shrink()
                        : const Icon(Icons.login),
                    label: _loading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Text("Sign in with Google"),
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
  final int userId;

  const HomePage({
    super.key,
    required this.name,
    required this.email,
    this.profileImageUrl,
    required this.userId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Configuration
  static const double _defaultUserWeight = 60.0;
  static const int _maxSpeedKmh = 30;
  static const double _minDistanceMeters = 0.8;
  static const int _maxGpsAccuracy = 100;
  static const int _socketBatchSeconds = 1;

  // Ground Configuration
  static const List<LatLng> _groundPolygonPoints = [
    LatLng(14.337558643627412, 78.53617772777397),
    LatLng(14.337096080275323, 78.53620723207409),
    LatLng(14.33692716645528, 78.53940978968112),
    LatLng(14.337646998317902, 78.53944465839942),
  ];
  static const LatLng _groundCenter = LatLng(14.337488449262446, 78.53780234296367);

  // User State
  late String _userName;
  double _userWeightKg = _defaultUserWeight;
  File? _localImage;
  String? _remoteImageUrl;
  bool _isSaving = false;

  // Tracking State
  bool _isJogging = false;
  int _currentIndex = 0;
  late PageController _pageController;
  late IO.Socket _socket;

  // Notifiers
  final ValueNotifier<List<JoggerData>> _activeJoggersNotifier =
  ValueNotifier([]);
  final ValueNotifier<bool> _isInsideGround = ValueNotifier(false);
  final ValueNotifier<double> _bearingToGround = ValueNotifier(0.0);
  final ValueNotifier<double> _totalDistance = ValueNotifier(0.0);
  final ValueNotifier<double> _avgSpeed = ValueNotifier(0.0);
  final ValueNotifier<double> _calories = ValueNotifier(0.0);

  // Map and Location
  final MapController _mapController = MapController();
  LatLng? _myCurrentPos;
  StreamSubscription<Position>? _positionStream;

  // Session Tracking
  DateTime? _startTime;
  LatLng? _lastRecordedPos;
  DateTime? _lastUpdateTime;
  Timer? _socketBatchTimer;
  LatLng? _pendingSocketUpdate;

  @override
  void initState() {
    super.initState();
    _userName = widget.name;
    _pageController = PageController(initialPage: _currentIndex);
    _initializeProfileImage();
    _initSocket();
    _startLiveTracking();
    _loadUserWeight();
  }

  void _initializeProfileImage() {
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      _remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }
  }

  void _initSocket() {
    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );
    _socket.connect();

    _socket.on("active_joggers", (data) {
      if (!mounted) return;
      compute(_parseJoggers, {'data': data, 'userName': _userName})
          .then((result) {
        if (!mounted) return;
        _activeJoggersNotifier.value = result['joggers'];
      });
    });
  }

  static Map<String, dynamic> _parseJoggers(Map<String, dynamic> params) {
    final data = params['data'] as List;
    final joggers = data
        .map((j) => JoggerData(
      name: j['name'],
      lat: j['lat'],
      lng: j['lng'],
    ))
        .toList();
    return {'joggers': joggers};
  }

  Future<void> _loadUserWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userWeightKg = prefs.getDouble("weight_${widget.email}") ?? _defaultUserWeight;
    });
  }

  void _startLiveTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    _positionStream = Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
        forceLocationManager: true,
        intervalDuration: Duration(seconds: 2),
      ),
    ).listen(_onPositionUpdate);
  }

  void _onPositionUpdate(Position position) {
    final newPos = LatLng(position.latitude, position.longitude);

    if (!mounted) return;

    setState(() => _myCurrentPos = newPos);
    _mapController.move(newPos, _mapController.camera.zoom);

    // Geofencing check
    _isInsideGround.value = _isPointInPolygon(newPos, _groundPolygonPoints);

    // Navigation arrow
    if (!_isInsideGround.value) {
      _bearingToGround.value = Geolocator.bearingBetween(
        newPos.latitude,
        newPos.longitude,
        _groundCenter.latitude,
        _groundCenter.longitude,
      );
    }

    // Update session stats if jogging
    if (_isJogging) {
      _updateMovement(position);
      _broadcastLocation(newPos);
    }
  }

  void _updateMovement(Position pos) {
    final now = DateTime.now();
    final newPos = LatLng(pos.latitude, pos.longitude);

    if (pos.accuracy > _maxGpsAccuracy) return;

    if (_lastRecordedPos == null) {
      _lastRecordedPos = newPos;
      _lastUpdateTime = now;
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastRecordedPos!.latitude,
      _lastRecordedPos!.longitude,
      newPos.latitude,
      newPos.longitude,
    );

    if (distance < _minDistanceMeters) return;

    final duration = now.difference(_lastUpdateTime!).inMilliseconds;
    if (duration > 0) {
      final speedKmh = (distance / (duration / 1000)) * 3.6;
      if (speedKmh < _maxSpeedKmh) {
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
    if (seconds >= 1) {
      _avgSpeed.value = (_totalDistance.value / seconds) * 3.6;
    }

    final met = _getMET(_avgSpeed.value);
    final caloriesPerSec = (met * _userWeightKg) / 3600;

    // Calculate calories based on actual time elapsed since last update
    if (_lastUpdateTime != null) {
      final secondsSinceLastUpdate =
          DateTime.now().difference(_lastUpdateTime!).inSeconds;
      _calories.value += caloriesPerSec * secondsSinceLastUpdate;
    }
  }

  void _broadcastLocation(LatLng pos) {
    _pendingSocketUpdate = pos;
    _socketBatchTimer?.cancel();
    _socketBatchTimer = Timer(Duration(seconds: _socketBatchSeconds), () {
      if (_pendingSocketUpdate != null) {
        _socket.emit("update_location", {
          "user_id": widget.userId,
          "lat": _pendingSocketUpdate!.latitude,
          "lng": _pendingSocketUpdate!.longitude,
        });
        _pendingSocketUpdate = null;
      }
    });
  }

  void _startJog() {
    // Safety check: ensure GPS has locked position
    if (_myCurrentPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Waiting for GPS location..."),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isJogging = true;
      _startTime = DateTime.now();
      _lastRecordedPos = _myCurrentPos;
      _lastUpdateTime = DateTime.now();
      _totalDistance.value = 0;
      _avgSpeed.value = 0;
      _calories.value = 0;
    });

    _socket.emit("start_jog", {
      "user_id": widget.userId,
      "name": _userName,
      "lat": _myCurrentPos!.latitude,
      "lng": _myCurrentPos!.longitude,
    });
  }

  void _stopJog() async {
    setState(() => _isJogging = false);

    try {
      if (_startTime == null) return;

      final res = await http.post(
        Uri.parse("${AppConfig.apiBase}/save_session.php"),
        body: {
          "user_id": widget.userId.toString(),
          "distance": (_totalDistance.value / 1000).toString(),
          "duration": DateTime.now().difference(_startTime!).inSeconds.toString(),
          "calories": _calories.value.round().toString(),
          "avg_speed": _avgSpeed.value.toString(),
        },
      ).timeout(const Duration(seconds: 10));

      if (res.body.isEmpty) {
        throw Exception("Empty response from server");
      }

      debugPrint("SAVE SESSION STATUS: ${res.statusCode}");
      debugPrint("SAVE SESSION BODY: ${res.body}");

      final data = jsonDecode(res.body);

      if (mounted && data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Session saved successfully!"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("SAVE SESSION ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to save session"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    _socket.emit("stop_jog", {"user_id": widget.userId});

    // Reset tracking variables
    _lastRecordedPos = null;
    _lastUpdateTime = null;
    _startTime = null;
  }

  double _getMET(double speedKmh) {
    if (speedKmh < 6) return 4.3;
    if (speedKmh < 7.5) return 6.0;
    if (speedKmh < 9) return 7.0;
    if (speedKmh < 11) return 9.8;
    return 11.5;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    var counter = 0;
    var xinters = 0.0;
    var p1 = polygon[0];
    final n = polygon.length;

    for (var i = 1; i <= n; i++) {
      final p2 = polygon[i % n];
      if (point.latitude > (p1.latitude < p2.latitude ? p1.latitude : p2.latitude)) {
        if (point.latitude <= (p1.latitude > p2.latitude ? p1.latitude : p2.latitude)) {
          if (point.longitude <= (p1.longitude > p2.longitude ? p1.longitude : p2.longitude)) {
            if (p1.latitude != p2.latitude) {
              xinters = (point.latitude - p1.latitude) *
                  (p2.longitude - p1.longitude) /
                  (p2.latitude - p1.latitude) +
                  p1.longitude;
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

  /* ========================= PROFILE SHEET ========================= */

  void _openProfileSheet() {
    final controller = TextEditingController(text: _userName);
    File? tempImage = _localImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  final picked = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 70,
                    maxWidth: 512,
                  );
                  if (picked != null) {
                    setSheetState(() => tempImage = File(picked.path));
                  }
                },
                child: CircleAvatar(
                  radius: 55,
                  backgroundImage: tempImage != null
                      ? FileImage(tempImage!)
                      : (_remoteImageUrl != null
                      ? NetworkImage(_remoteImageUrl!)
                      : null),
                  child: tempImage == null && _remoteImageUrl == null
                      ? const Icon(Icons.camera_alt)
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: "Full Name"),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving
                      ? null
                      : () => _saveProfile(context, controller.text, tempImage, setSheetState),
                  child: const Text("Save"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile(
      BuildContext context,
      String newName,
      File? newImage,
      StateSetter setSheetState,
      ) async {
    setSheetState(() => _isSaving = true);

    try {
      final request = http.MultipartRequest(
        "POST",
        Uri.parse(AppConfig.updateProfileUrl),
      );
      request.fields['email'] = widget.email;
      request.fields['profile_name'] = newName;

      if (newImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('profile_image', newImage.path),
        );
      }

      final response = await request.send();
      if (mounted && response.statusCode == 200) {
        setState(() {
          _userName = newName;
          _localImage = newImage;
        });
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setSheetState(() => _isSaving = false);
    }
  }

  /* ========================= UI COMPONENTS ========================= */

  Widget _buildGuidanceArrow() {
    return ValueListenableBuilder2<bool, double>(
      _isInsideGround,
      _bearingToGround,
      builder: (context, isInside, bearing, _) {
        if (isInside || _isJogging) return const SizedBox.shrink();

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  "Ground is this way! 🏃",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Transform.rotate(
                angle: bearing * (3.14159 / 180),
                child: const Icon(
                  Icons.navigation,
                  size: 60,
                  color: Colors.blueAccent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title,
      ValueNotifier<double> valueNotifier,
      String Function(double) formatter,
      IconData icon,
      Color color,
      ) {
    return ValueListenableBuilder<double>(
      valueListenable: valueNotifier,
      builder: (context, value, child) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                title,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Text(
                formatter(value),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomeContent() {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      "Distance",
                      _totalDistance,
                          (v) => "${(v / 1000).toStringAsFixed(2)} km",
                      Icons.route,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      "Speed",
                      _avgSpeed,
                          (v) => "${v.toStringAsFixed(1)} km/h",
                      Icons.speed,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      "Calories",
                      _calories,
                          (v) => v.toStringAsFixed(0),
                      Icons.local_fire_department,
                      Colors.orange,
                    ),
                  ),
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
                      onPressed: (isInside || _isJogging)
                          ? (_isJogging ? _stopJog : _startJog)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isJogging ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isJogging
                            ? "STOP SESSION"
                            : (isInside ? "START JOGGING" : "LOCKED: ENTER GROUND"),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildGroundView()),
          ],
        ),
        _buildGuidanceArrow(),
      ],
    );
  }

  Widget _buildGroundView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _groundCenter,
            initialZoom: 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.example.campusconnect',
            ),
            PolygonLayer(
              polygons: [
                Polygon(
                  points: _groundPolygonPoints,
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
                    ...joggers.map(
                          (j) => Marker(
                        point: LatLng(j.lat, j.lng),
                        child: const Icon(
                          Icons.directions_run,
                          color: Colors.red,
                          size: 28,
                        ),
                      ),
                    ),
                    if (_myCurrentPos != null)
                      Marker(
                        point: _myCurrentPos!,
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.blue,
                          size: 40,
                        ),
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

  @override
  void dispose() {
    _positionStream?.cancel();
    _socketBatchTimer?.cancel();
    _socket.dispose();
    _pageController.dispose();
    _activeJoggersNotifier.dispose();
    _isInsideGround.dispose();
    _bearingToGround.dispose();
    _totalDistance.dispose();
    _avgSpeed.dispose();
    _calories.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: GestureDetector(
          onTap: _openProfileSheet,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: _localImage != null
                    ? FileImage(_localImage!)
                    : (_remoteImageUrl != null
                    ? NetworkImage(_remoteImageUrl!)
                    : null),
                child: (_localImage == null && _remoteImageUrl == null)
                    ? const Icon(Icons.person)
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                _userName,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: () async {
              await _googleSignIn.signOut();
              if (mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginPage()),
                );
              }
            },
          ),
        ],
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        children: [
          _buildHomeContent(),
          StatsPage(userId: widget.userId),
          const AllStatsPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => _pageController.jumpToPage(i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: "Stats"),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: "Global",
          ),
        ],
      ),
    );
  }
}

/* ========================= HELPER WIDGETS ========================= */

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueListenable<A> first;
  final ValueListenable<B> second;
  final Widget Function(BuildContext context, A a, B b, Widget? child) builder;

  const ValueListenableBuilder2(
      this.first,
      this.second, {
        required this.builder,
        super.key,
      });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<A>(
    valueListenable: first,
    builder: (context, a, _) => ValueListenableBuilder<B>(
      valueListenable: second,
      builder: (context, b, _) => builder(context, a, b, null),
    ),
  );
}

/* ========================= DATA MODELS ========================= */

class JoggerData {
  final String name;
  final double lat;
  final double lng;

  JoggerData({
    required this.name,
    required this.lat,
    required this.lng,
  });
}

/* ========================= STATS PAGE ========================= */

class StatsPage extends StatefulWidget {
  final int userId;

  const StatsPage({super.key, required this.userId});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<String> _days = [];
  List<double> _startTimes = [];
  List<double> _distances = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await http.get(
        Uri.parse(
          "${AppConfig.apiBase}/user_weekly_stats.php?user_id=${widget.userId}",
        ),
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _days = List<String>.from(data['days'] ?? []);
          _startTimes = List<double>.from(
            (data['start_times'] ?? []).map((e) => e.toDouble()),
          );
          _distances = List<double>.from(
            (data['distances'] ?? []).map((e) => e.toDouble()),
          );
          _loading = false;
        });
      } else {
        throw Exception("Server returned ${res.statusCode}");
      }
    } catch (e) {
      debugPrint("Error loading stats: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to load statistics";
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadStats,
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (_days.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.show_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "No activity this week",
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Start jogging to see your stats!",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text(
                  "This Week's Activity",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildChartCard(
                "Jog Start Times",
                _buildStartTimeChart(),
                Colors.blue,
                "Track when you prefer to jog",
              ),
              const SizedBox(height: 20),
              _buildChartCard(
                "Weekly Distance (km)",
                _buildDistanceChart(),
                Colors.green,
                "Your running progress throughout the week",
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartCard(
      String title,
      Widget chart,
      Color color,
      String subtitle,
      ) {
    return Container(
      height: 340,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 28, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
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
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  title.contains("Times") ? Icons.access_time : Icons.trending_up,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: chart),
        ],
      ),
    );
  }

  Widget _buildStartTimeChart() {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 2,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        minY: 4,
        maxY: 12,
        titlesData: _buildTitlesData(_days),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              _startTimes.length,
                  (i) => FlSpot(i.toDouble(), _startTimes[i]),
            ),
            isCurved: true,
            color: Colors.blueAccent,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 6,
                    color: Colors.white,
                    strokeWidth: 3,
                    strokeColor: Colors.blueAccent,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.3),
                  Colors.blueAccent.withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceChart() {
    final maxDistance = _distances.isEmpty
        ? 4.0
        : (_distances.reduce((a, b) => a > b ? a : b) * 1.2).ceilToDouble();

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxDistance > 4 ? maxDistance : 4,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 1,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Colors.grey.withOpacity(0.1),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _buildTitlesData(_days),
        barGroups: List.generate(
          _distances.length,
              (i) => BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: _distances[i],
                gradient: const LinearGradient(
                  colors: [Colors.greenAccent, Colors.teal],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
                width: 20,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxDistance,
                  color: Colors.grey.withOpacity(0.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  FlTitlesData _buildTitlesData(List<String> labels) {
    return FlTitlesData(
      topTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, _) {
            final index = value.toInt();
            if (index < 0 || index >= labels.length) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                labels[index],
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (value, _) {
            final hour = value.toInt();
            final minutes = ((value - hour) * 60).toInt();
            return Text(
              "$hour:${minutes.toString().padLeft(2, '0')}",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            );
          },
        ),
      ),
    );
  }
}

/* ========================= LEADERBOARD ========================= */

class AllStatsPage extends StatelessWidget {
  const AllStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.emoji_events, size: 80, color: Colors.amber),
          SizedBox(height: 20),
          Text(
            "Leaderboard",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 12),
          Text(
            "Coming Soon!",
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}