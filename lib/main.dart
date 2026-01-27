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
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:isolate';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:math' as math;

void main() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'jogger_tracking',
      channelName: 'Jogging Tracker',
      channelDescription: 'Tracks your jogging activity',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: const ForegroundTaskOptions(
      interval: 5000,
      isOnceEvent: false,
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

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
      home: const SplashDecider(),
    );
  }
}

class SplashDecider extends StatefulWidget {
  const SplashDecider({super.key});

  @override
  State<SplashDecider> createState() => _SplashDeciderState();
}

class _SplashDeciderState extends State<SplashDecider> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool("is_logged_in") ?? false;

    if (!mounted) return;

    if (!loggedIn) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }

    final email = prefs.getString("email")!;
    final profileDone = prefs.getBool("profile_done_$email") ?? false;

    if (!profileDone) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailsPage(
            userEmail: email,
            userId: prefs.getInt("user_id")!,
            userName: prefs.getString("name")!,
            profileImageUrl: prefs.getString("profile_image"),
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomePage(
            userId: prefs.getInt("user_id")!,
            email: email,
            name: prefs.getString("name")!,
            profileImageUrl: prefs.getString("profile_image"),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
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
        final prefs = await SharedPreferences.getInstance();

        await prefs.setBool("is_logged_in", true);
        await prefs.setInt("user_id", data["user_id"]);
        await prefs.setString("email", data["email"]);
        await prefs.setString("name", data["name"]);
        await prefs.setString("profile_image", data["profile_image"] ?? "");

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

/* ========================= ENHANCED VOICE SYSTEM ========================= */

enum VoicePersona {
  girlfriend,
  boyfriend,
}

/// 🎤 ULTRA-REALISTIC VOICE WITH NATURAL CONVERSATION FLOW
class UltraRealisticVoice {
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _fallbackTts = FlutterTts();
  final VoicePersona persona;
  bool _useElevenLabs = true;
  bool _isSpeaking = false;

  // 🔥 Conversational context tracking
  final List<String> _conversationHistory = [];
  int _motivationCount = 0;

  UltraRealisticVoice(this.persona);

  bool get isSpeaking => _isSpeaking;

  Future<void> initialize() async {
    await _fallbackTts.setLanguage("en-US");
    await _fallbackTts.setVolume(1.0);

    if (persona == VoicePersona.girlfriend) {
      await _fallbackTts.setPitch(1.2);
      await _fallbackTts.setSpeechRate(0.42);
    } else {
      await _fallbackTts.setPitch(0.8);
      await _fallbackTts.setSpeechRate(0.48);
    }

    // Listen for completion
    _player.onPlayerComplete.listen((_) {
      _isSpeaking = false;
    });
  }

  /// 🎯 Smart speak with natural conversation flow
  Future<void> speak(String text, {VoiceContext context = VoiceContext.motivation}) async {
    if (_isSpeaking) {
      await stop(); // Interrupt if already speaking
    }

    _isSpeaking = true;

    // Add conversational variety based on context
    final enhancedText = _enhanceWithContext(text, context);
    _conversationHistory.add(enhancedText);
    if (_conversationHistory.length > 5) {
      _conversationHistory.removeAt(0);
    }

    if (_useElevenLabs && AppConfig.elevenLabsApiKey.isNotEmpty) {
      final success = await _speakWithElevenLabs(enhancedText);
      if (!success) {
        debugPrint("ElevenLabs unavailable, using device TTS");
        _useElevenLabs = false;
        await _speakWithDeviceTTS(enhancedText);
      }
    } else {
      await _speakWithDeviceTTS(enhancedText);
    }
  }

  /// 🎨 Add natural conversation elements
  String _enhanceWithContext(String text, VoiceContext context) {
    _motivationCount++;

    // Add natural fillers and variations
    final intros = persona == VoicePersona.girlfriend
        ? ['Hey babe', 'Listen hun', 'You know what', 'Sweetie', 'Hey you']
        : ['Listen up', 'Yo', 'Check this out', 'Real talk', 'Hey man'];

    final connectors = ['…', '... ', ' - '];

    // Only add intro sometimes (feels more natural)
    if (context == VoiceContext.motivation && _motivationCount % 2 == 0) {
      final intro = intros[math.Random().nextInt(intros.length)];
      final connector = connectors[math.Random().nextInt(connectors.length)];
      return '$intro$connector$text';
    }

    return text;
  }

  Future<bool> _speakWithElevenLabs(String text) async {
    // More expressive voice models for natural conversation
    final voiceId = persona == VoicePersona.girlfriend
        ? "21m00Tcm4TlvDq8ikWAM" // Rachel - warm, expressive
        : "TxGEqnHWrfWFTfGW9XjX"; // Josh - deep, confident

    try {
      debugPrint("🎤 Speaking: $text");

      final response = await http.post(
        Uri.parse("https://api.elevenlabs.io/v1/text-to-speech/$voiceId/stream"),
        headers: {
          "Accept": "audio/mpeg",
          "xi-api-key": AppConfig.elevenLabsApiKey,
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "text": text,
          "model_id": "eleven_turbo_v2_5",
          "voice_settings": {
            "stability": persona == VoicePersona.girlfriend ? 0.25 : 0.35,
            "similarity_boost": 0.85,
            "style": persona == VoicePersona.girlfriend ? 0.85 : 0.70,
            "use_speaker_boost": true,
          },
          "optimize_streaming_latency": 3,
        }),
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.mp3');
        await file.writeAsBytes(response.bodyBytes);

        await _player.stop();
        await _player.play(DeviceFileSource(file.path));

        // Cleanup after playback
        _player.onPlayerComplete.listen((_) {
          file.delete().catchError((e) => debugPrint("Cleanup: $e"));
        });

        return true;
      } else {
        debugPrint("❌ ElevenLabs error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ ElevenLabs exception: $e");
    }
    return false;
  }

  Future<void> _speakWithDeviceTTS(String text) async {
    await _fallbackTts.stop();
    await _fallbackTts.speak(text);

    // Mark as not speaking after estimated duration
    final wordCount = text.split(' ').length;
    final estimatedDuration = Duration(milliseconds: wordCount * 400);
    Future.delayed(estimatedDuration, () => _isSpeaking = false);
  }

  Future<void> stop() async {
    _isSpeaking = false;
    await _player.stop();
    await _fallbackTts.stop();
  }

  void dispose() {
    _player.dispose();
    _fallbackTts.stop();
  }
}

enum VoiceContext {
  motivation,
  milestone,
  warning,
  encouragement,
  celebration,
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
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  @override
  bool get wantKeepAlive => true;

  late UltraRealisticVoice _voice;

  // ✅ FIX #6: Context-aware voice timing instead of single cooldown
  Map<VoiceContext, DateTime?> _lastSpokenByContext = {
    VoiceContext.motivation: null,
    VoiceContext.milestone: null,
    VoiceContext.warning: null,
    VoiceContext.encouragement: null,
    VoiceContext.celebration: null,
  };

  late VoicePersona _voicePersona;

  // ✅ FIX #5: Track milestone boundaries correctly
  double _lastDistanceSpoken = 0.0;
  double _lastSpeedSpoken = 0.0;
  int _milestoneCount = 0;

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
  final ValueNotifier<List<JoggerData>> _activeJoggersNotifier = ValueNotifier([]);
  final ValueNotifier<bool> _isInsideGround = ValueNotifier(false);
  final ValueNotifier<double> _bearingToGround = ValueNotifier(0.0);
  final ValueNotifier<double> _totalDistance = ValueNotifier(0.0);
  final ValueNotifier<double> _avgSpeed = ValueNotifier(0.0);
  final ValueNotifier<double> _calories = ValueNotifier(0.0);
  final ValueNotifier<double> _todayKm = ValueNotifier(0.0);
  final ValueNotifier<int> _streak = ValueNotifier(0);

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

  // ✅ FIX #4: Add tracking for last socket broadcast
  DateTime? _lastSocketBroadcast;

  Timer? _notificationUpdateTimer;
  Timer? _aiMotivationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userName = widget.name;
    _pageController = PageController(initialPage: _currentIndex);
    _initializeProfileImage();
    _initSocket();
    _requestPermissions();
    _startLiveTracking();
    _loadUserWeight();
    _fetchStreak();
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _loadVoicePersona();

    try {
      await _voice.stop();
      _voice.dispose();
    } catch (_) {}

    _voice = UltraRealisticVoice(_voicePersona);
    await _voice.initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint("App state: $state");
  }

  Future<void> _requestPermissions() async {
    final locationStatus = await Permission.location.request();

    if (locationStatus.isGranted) {
      if (Platform.isAndroid) {
        final bgLocationStatus = await Permission.locationAlways.request();
        if (!bgLocationStatus.isGranted) {
          _showPermissionDialog();
        }
      }
    }

    if (Platform.isAndroid) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  Future<void> _fetchStreak() async {
    try {
      final res = await http.get(
        Uri.parse("${AppConfig.apiBase}/get_streak.php?user_id=${widget.userId}"),
      );

      final data = jsonDecode(res.body);
      _streak.value = data['current_streak'] ?? 0;
      _todayKm.value = (data['today_km'] ?? 0).toDouble();
    } catch (_) {}
  }

  Future<void> _loadVoicePersona() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString("voice_persona_${widget.email}");
    _voicePersona = value == "boyfriend" ? VoicePersona.boyfriend : VoicePersona.girlfriend;
  }

  Future<void> _saveVoicePersona(VoicePersona persona) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("voice_persona_${widget.email}", persona.name);
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Background Location"),
        content: const Text(
          "For accurate tracking when the screen is off, please grant 'Allow all the time' location permission in Settings.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text("Open Settings"),
          ),
        ],
      ),
    );
  }

  void _initializeProfileImage() {
    if (widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty) {
      _remoteImageUrl = "${AppConfig.baseImageUrl}/${widget.profileImageUrl}";
    }
  }

  void _initSocket() {
    _socket = IO.io(
      AppConfig.socketUrl,
      IO.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build(),
    );
    _socket.connect();

    _socket.on("active_joggers", (data) {
      if (!mounted) return;
      compute(_parseJoggers, {'data': data, 'userId': widget.userId}).then((result) {
        if (!mounted) return;
        _activeJoggersNotifier.value = result['joggers'];
      });
    });
  }

  static Map<String, dynamic> _parseJoggers(Map<String, dynamic> params) {
    final List data = params['data'];
    final int myId = params['userId'];

    final joggers = data
        .where((j) => j['user_id'] != myId)
        .map((j) => JoggerData(
      name: j['name'],
      lat: j['lat'],
      lng: j['lng'],
      profileImage: j['profile_image'],
    ))
        .toList();

    return {'joggers': joggers};
  }

  /// 🎤 Enhanced speech with context awareness
  Future<void> speakWithContext(String text, VoiceContext context) async {
    if (_voice.isSpeaking) {
      await _voice.stop();
    }
    await _voice.speak(text, context: context);
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

    _isInsideGround.value = _isPointInPolygon(newPos, _groundPolygonPoints);

    if (!_isInsideGround.value) {
      double targetBearing = Geolocator.bearingBetween(
        newPos.latitude,
        newPos.longitude,
        _groundCenter.latitude,
        _groundCenter.longitude,
      );
      _bearingToGround.value = _bearingToGround.value + (targetBearing - _bearingToGround.value) * 0.2;
    }

    if (_isJogging) {
      _updateMovement(position);
      _broadcastLocation(newPos);
      _checkMilestones();
    }
  }

  // ✅ FIX #1: CORRECTED DISTANCE AND SPEED CALCULATION
  void _updateMovement(Position pos) {
    final now = DateTime.now();
    final newPos = LatLng(pos.latitude, pos.longitude);

    // Reject low accuracy readings
    if (pos.accuracy > _maxGpsAccuracy) {
      debugPrint("⚠️ GPS accuracy too low: ${pos.accuracy}m");
      return;
    }

    // Initialize on first reading
    if (_lastRecordedPos == null || _lastUpdateTime == null) {
      _lastRecordedPos = newPos;
      _lastUpdateTime = now;
      debugPrint("📍 First position recorded");
      return;
    }

    // Calculate distance between last position and current position
    final distance = Geolocator.distanceBetween(
      _lastRecordedPos!.latitude,
      _lastRecordedPos!.longitude,
      newPos.latitude,
      newPos.longitude,
    );

    // Filter out GPS jitter (movements less than minimum threshold)
    if (distance < _minDistanceMeters) {
      debugPrint("⚠️ Movement too small: ${distance.toStringAsFixed(2)}m");
      return;
    }

    // ✅ CRITICAL FIX: Calculate time difference BEFORE updating _lastUpdateTime
    final durationSeconds = now.difference(_lastUpdateTime!).inSeconds;

    // Ensure we have positive duration
    if (durationSeconds <= 0) {
      debugPrint("⚠️ Invalid time duration: $durationSeconds seconds");
      return;
    }

    // Calculate instantaneous speed: speed (m/s) = distance (m) / time (s)
    // Convert to km/h: multiply by 3.6
    final speedKmh = (distance / durationSeconds) * 3.6;

    // Validate speed is physically realistic for jogging/running
    if (speedKmh >= 0.5 && speedKmh < _maxSpeedKmh) {
      // ✅ VALID MOVEMENT - Update all tracking variables

      // Add to total distance
      _totalDistance.value += distance;
      _todayKm.value = _totalDistance.value / 1000;

      // ✅ CRITICAL: Update position and time TOGETHER and IMMEDIATELY
      _lastRecordedPos = newPos;
      _lastUpdateTime = now;

      // Calculate segment calories based on instantaneous speed
      final met = _getMET(speedKmh);
      final segmentHours = durationSeconds / 3600.0;
      final segmentCalories = met * _userWeightKg * segmentHours;
      _calories.value += segmentCalories;

      // Update average speed for the entire session
      _updateAverageSpeed();

      debugPrint("✅ Valid movement: ${distance.toStringAsFixed(2)}m in ${durationSeconds}s = ${speedKmh.toStringAsFixed(1)} km/h");
    } else {
      // Invalid speed - likely GPS error
      debugPrint("⚠️ Speed rejected: ${speedKmh.toStringAsFixed(1)} km/h (distance: ${distance.toStringAsFixed(2)}m, duration: ${durationSeconds}s)");

      // ✅ FIX: Even if speed is invalid, update time to prevent accumulation errors
      // But DON'T update position or add distance
      _lastUpdateTime = now;
    }
  }

  // ✅ FIX #2: CORRECTED AVERAGE SPEED CALCULATION
  void _updateAverageSpeed() {
    if (_startTime == null) return;

    // Calculate total session duration in seconds
    final totalSeconds = DateTime.now().difference(_startTime!).inSeconds;

    if (totalSeconds >= 1) {
      // Average speed = total distance / total time
      // Convert from m/s to km/h by multiplying by 3.6
      _avgSpeed.value = (_totalDistance.value / totalSeconds) * 3.6;
    }
  }

  // ✅ FIX #4: CORRECTED SOCKET BROADCASTING WITH PROPER BATCHING
  void _broadcastLocation(LatLng pos) {
    final now = DateTime.now();

    // Always update to latest position
    _pendingSocketUpdate = pos;

    // Check if enough time has passed since last broadcast
    if (_lastSocketBroadcast != null &&
        now.difference(_lastSocketBroadcast!).inSeconds < _socketBatchSeconds) {
      // Timer is already running, just keep the latest position
      return;
    }

    // Cancel any existing timer
    _socketBatchTimer?.cancel();

    // Set up new broadcast timer
    _socketBatchTimer = Timer(Duration(seconds: _socketBatchSeconds), () {
      if (_pendingSocketUpdate != null && _socket.connected) {
        _socket.emit("update_location", {
          "user_id": widget.userId,
          "lat": _pendingSocketUpdate!.latitude,
          "lng": _pendingSocketUpdate!.longitude,
          "speed": _avgSpeed.value,
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        });
        _lastSocketBroadcast = DateTime.now();
        _pendingSocketUpdate = null;
        debugPrint("📡 Location broadcast: ${_pendingSocketUpdate!.latitude}, ${_pendingSocketUpdate!.longitude}");
      }
    });
  }

  // ✅ FIX #5: CORRECTED MILESTONE DETECTION
  void _checkMilestones() {
    final distKm = _totalDistance.value / 1000;
    final speed = _avgSpeed.value;

    // Distance milestones - trigger every 0.5 km
    final currentMilestone = (distKm / 0.5).floor() * 0.5;
    final lastMilestone = (_lastDistanceSpoken / 0.5).floor() * 0.5;

    if (currentMilestone > lastMilestone && currentMilestone > 0) {
      _lastDistanceSpoken = currentMilestone;
      _speakMilestone(
          "You've hit ${currentMilestone.toStringAsFixed(1)} kilometers!",
          VoiceContext.milestone
      );
      debugPrint("🏆 Milestone reached: ${currentMilestone}km");
    }

    // Speed encouragement - only when crossing 8.0 km/h threshold
    if (speed > 8.0 && _lastSpeedSpoken <= 8.0) {
      _lastSpeedSpoken = speed;
      _speakMilestone(
          "Damn, ${speed.toStringAsFixed(1)} km/h! You're flying!",
          VoiceContext.encouragement
      );
    } else if (speed > 8.0) {
      _lastSpeedSpoken = speed; // Update silently
    }

    // Low speed warning - only when dropping below 4.0 km/h threshold
    if (speed < 4.0 && _lastSpeedSpoken >= 4.0) {
      _lastSpeedSpoken = speed;
      _speakMilestone(
          "Hey, pick up the pace a bit!",
          VoiceContext.warning
      );
    } else if (speed < 4.0) {
      _lastSpeedSpoken = speed; // Update silently
    }
  }

  // ✅ FIX #6: CONTEXT-AWARE VOICE COOLDOWNS
  bool _canSpeak(VoiceContext context) {
    final lastSpoken = _lastSpokenByContext[context];

    if (lastSpoken == null) return true;

    // Different cooldowns for different contexts
    final cooldownSeconds = switch (context) {
      VoiceContext.milestone => 10,      // Quick response to achievements
      VoiceContext.warning => 30,        // Don't nag too much
      VoiceContext.encouragement => 20,  // Moderate frequency
      VoiceContext.motivation => 40,     // Background motivation
      VoiceContext.celebration => 0,     // Always allow
    };

    return DateTime.now().difference(lastSpoken).inSeconds > cooldownSeconds;
  }

  Future<void> _speakMilestone(String text, VoiceContext context) async {
    if (!_canSpeak(context)) {
      debugPrint("🔇 Speech blocked by cooldown: $context");
      return;
    }

    _lastSpokenByContext[context] = DateTime.now();
    _milestoneCount++;
    await speakWithContext(text, context);
  }

  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
    } else {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Campus Connect - Jogging',
        notificationText: 'Tracking your run...',
        callback: startCallback,
      );
    }

    _notificationUpdateTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => _updateNotification(),
    );
  }

  void _updateNotification() {
    if (!_isJogging) return;

    final distKm = (_totalDistance.value / 1000).toStringAsFixed(2);
    final speed = _avgSpeed.value.toStringAsFixed(1);
    final cals = _calories.value.toStringAsFixed(0);

    FlutterForegroundTask.updateService(
      notificationTitle: 'Campus Connect - Jogging 🏃',
      notificationText: '$distKm km • $speed km/h • $cals cal',
    );
  }

  Future<void> _stopForegroundService() async {
    _notificationUpdateTimer?.cancel();
    await FlutterForegroundTask.stopService();
  }

  void _startJog() async {
    if (_myCurrentPos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Waiting for GPS location...")),
      );
      return;
    }

    await WakelockPlus.enable();
    await _startForegroundService();

    setState(() {
      _isJogging = true;
      _startTime = DateTime.now();
      _lastRecordedPos = _myCurrentPos;
      _lastUpdateTime = DateTime.now();

      // Reset all tracking variables
      _totalDistance.value = 0;
      _avgSpeed.value = 0;
      _calories.value = 0;
      _lastDistanceSpoken = 0.0;
      _lastSpeedSpoken = 0.0;
      _milestoneCount = 0;

      // Reset voice cooldowns
      _lastSpokenByContext = {
        VoiceContext.motivation: null,
        VoiceContext.milestone: null,
        VoiceContext.warning: null,
        VoiceContext.encouragement: null,
        VoiceContext.celebration: null,
      };
    });

    _socket.emit("start_jog", {
      "user_id": widget.userId,
      "name": _userName,
      "lat": _myCurrentPos!.latitude,
      "lng": _myCurrentPos!.longitude,
      "profile_image": _remoteImageUrl,
    });

    // 🎤 Welcome message
    Future.delayed(const Duration(seconds: 2), () {
      speakWithContext("Let's do this! I'm right here with you.", VoiceContext.encouragement);
    });

    // 🎤 Dynamic AI motivation
    _aiMotivationTimer = Timer.periodic(
      const Duration(seconds: 50),
          (_) => _speakAiMotivation(),
    );

    debugPrint("🏃 Jog started at ${_startTime}");
  }

  void _stopJog() async {
    debugPrint("🛑 Stopping jog...");

    setState(() => _isJogging = false);

    await WakelockPlus.disable();
    await _stopForegroundService();

    // 🎤 Celebration
    final distKm = (_totalDistance.value / 1000).toStringAsFixed(2);
    final totalMinutes = DateTime.now().difference(_startTime!).inMinutes;
    speakWithContext(
      "Amazing work! You crushed $distKm kilometers in $totalMinutes minutes!",
      VoiceContext.celebration,
    );

    try {
      if (_startTime == null) {
        debugPrint("⚠️ No start time - session not saved");
        return;
      }

      final durationSeconds = DateTime.now().difference(_startTime!).inSeconds;

      debugPrint("💾 Saving session: ${(_totalDistance.value / 1000).toStringAsFixed(2)}km, ${durationSeconds}s, ${_calories.value.round()}cal");

      final res = await http.post(
        Uri.parse("${AppConfig.apiBase}/save_session.php"),
        body: {
          "user_id": widget.userId.toString(),
          "distance": (_totalDistance.value / 1000).toString(),
          "duration": durationSeconds.toString(),
          "calories": _calories.value.round().toString(),
          "avg_speed": _avgSpeed.value.toString(),
        },
      ).timeout(const Duration(seconds: 10));

      if (res.body.isEmpty) {
        throw Exception("Empty response from server");
      }

      final data = jsonDecode(res.body);

      if (mounted && data['status'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Session saved successfully!"),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        debugPrint("✅ Session saved successfully");
      } else {
        throw Exception("Server returned error: ${data['message']}");
      }
    } catch (e) {
      debugPrint("❌ SAVE SESSION ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to save session: $e"),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    _socket.emit("stop_jog", {"user_id": widget.userId});

    // Reset session variables
    _lastRecordedPos = null;
    _lastUpdateTime = null;
    _startTime = null;
    _lastSocketBroadcast = null;

    _fetchStreak();
    _aiMotivationTimer?.cancel();
  }

  double _getMET(double speedKmh) {
    // MET (Metabolic Equivalent of Task) values for different speeds
    if (speedKmh < 6) return 4.3;      // Slow jogging
    if (speedKmh < 7.5) return 6.0;    // Light jogging
    if (speedKmh < 9) return 7.0;      // Moderate jogging
    if (speedKmh < 11) return 9.8;     // Running
    return 11.5;                        // Fast running
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
                      : (_remoteImageUrl != null ? NetworkImage(_remoteImageUrl!) : null),
                  child: tempImage == null && _remoteImageUrl == null ? const Icon(Icons.camera_alt) : null,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: "Full Name"),
              ),
              const SizedBox(height: 16),
              const Text(
                "Motivational Voice",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChoiceChip(
                    label: const Text("Girlfriend 💕"),
                    selected: _voicePersona == VoicePersona.girlfriend,
                    onSelected: (_) async {
                      await _saveVoicePersona(VoicePersona.girlfriend);
                      setSheetState(() {
                        _voicePersona = VoicePersona.girlfriend;
                      });
                      await _initVoice();
                    },
                  ),
                  ChoiceChip(
                    label: const Text("Boyfriend 💪"),
                    selected: _voicePersona == VoicePersona.boyfriend,
                    onSelected: (_) async {
                      await _saveVoicePersona(VoicePersona.boyfriend);
                      setSheetState(() {
                        _voicePersona = VoicePersona.boyfriend;
                      });
                      await _initVoice();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : () => _saveProfile(context, controller.text, tempImage, setSheetState),
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

  Future<String?> _fetchAiMotivation() async {
    try {
      final res = await http.post(
        Uri.parse("${AppConfig.socketUrl}/motivation"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "distance": (_totalDistance.value / 1000).toStringAsFixed(2),
          "speed": _avgSpeed.value.toStringAsFixed(1),
          "calories": _calories.value.toStringAsFixed(0),
          "others": _activeJoggersNotifier.value.length,
        }),
      );

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      return data["text"];
    } catch (e) {
      debugPrint("AI ERROR: $e");
      return null;
    }
  }

  Future<void> _speakAiMotivation() async {
    if (!_isJogging || !_canSpeak(VoiceContext.motivation)) return;

    final text = await _fetchAiMotivation();
    if (text == null || text.isEmpty) return;

    _lastSpokenByContext[VoiceContext.motivation] = DateTime.now();
    await speakWithContext(text, VoiceContext.motivation);
  }

  /* ========================= UI COMPONENTS ========================= */

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
            _buildStreakCard(),
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
                      onPressed: (isInside || _isJogging) ? (_isJogging ? _stopJog : _startJog) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isJogging ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isJogging ? "STOP SESSION" : (isInside ? "START JOGGING" : "LOCKED: ENTER GROUND"),
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
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            image: j.profileImage != null
                                ? DecorationImage(
                              image: NetworkImage(j.profileImage!),
                              fit: BoxFit.cover,
                            )
                                : null,
                            color: Colors.blueAccent,
                          ),
                          child: j.profileImage == null ? const Icon(Icons.person, color: Colors.white, size: 22) : null,
                        ),
                      ),
                    ),
                    if (_myCurrentPos != null)
                      Marker(
                        point: _myCurrentPos!,
                        width: 60,
                        height: 60,
                        child: _buildUserLocationPointer(),
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

  Widget _buildStreakCard() {
    return ValueListenableBuilder2<double, int>(
      _todayKm,
      _streak,
      builder: (context, km, streak, _) {
        final progress = (km / 0.6).clamp(0.0, 1.0);
        final remaining = (0.6 - km).clamp(0.0, 0.6);

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Text(
                    "$streak-day streak",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.white.withOpacity(0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                km >= 0.6
                    ? "🔥 Streak saved for today!"
                    : "Walk ${(remaining * 1000).toInt()}m more to keep streak",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUserLocationPointer() {
    return Stack(
      alignment: Alignment.center,
      children: [
        TweenAnimationBuilder(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(seconds: 2),
          builder: (context, double value, child) {
            return Container(
              width: 20 + (40 * value),
              height: 20 + (40 * value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withOpacity(1 - value),
              ),
            );
          },
        ),
        Transform.rotate(
          angle: _bearingToGround.value * (3.14159 / 180),
          child: const Icon(Icons.navigation, color: Colors.blue, size: 28),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue, width: 2.5),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStream?.cancel();
    _socketBatchTimer?.cancel();
    _notificationUpdateTimer?.cancel();
    _socket.dispose();
    _pageController.dispose();
    _activeJoggersNotifier.dispose();
    _isInsideGround.dispose();
    _bearingToGround.dispose();
    _totalDistance.dispose();
    _avgSpeed.dispose();
    _calories.dispose();
    WakelockPlus.disable();
    FlutterForegroundTask.stopService();
    _aiMotivationTimer?.cancel();
    _voice.dispose();
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
                    : (_remoteImageUrl != null ? NetworkImage(_remoteImageUrl!) : null),
                child: (_localImage == null && _remoteImageUrl == null) ? const Icon(Icons.person) : null,
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
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
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

// Foreground task callback
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(JoggerTaskHandler());
}

class JoggerTaskHandler extends TaskHandler {
  @override
  void onStart(DateTime timestamp, SendPort? sendPort) {}

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    FlutterForegroundTask.updateService(
      notificationText: 'Tracking jogging session...',
    );
  }

  @override
  void onDestroy(DateTime timestamp, SendPort? sendPort) {}
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
  final String? profileImage;

  JoggerData({
    required this.name,
    required this.lat,
    required this.lng,
    this.profileImage,
  });
}

/* ========================= STATS PAGE ========================= */

class StatsPage extends StatefulWidget {
  final int userId;

  const StatsPage({super.key, required this.userId});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with AutomaticKeepAliveClientMixin {
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
        Uri.parse("${AppConfig.apiBase}/user_weekly_stats.php?user_id=${widget.userId}"),
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
              getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
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
    final maxDistance = _distances.isEmpty ? 4.0 : (_distances.reduce((a, b) => a > b ? a : b) * 1.2).ceilToDouble();

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
class AllStatsPage extends StatefulWidget {
  const AllStatsPage({super.key});

  @override
  State<AllStatsPage> createState() => _AllStatsPageState();
}

class _AllStatsPageState extends State<AllStatsPage> with SingleTickerProviderStateMixin {
  late Future<Map<String, dynamic>> _globalStatsFuture;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _globalStatsFuture = _fetchGlobalStats();
    _tabController = TabController(length: 3, vsync: this);
  }

  Future<Map<String, dynamic>> _fetchGlobalStats() async {
    final res = await http.get(
      Uri.parse("${AppConfig.apiBase}/get_global_stats.php"),
    ).timeout(const Duration(seconds: 10));
    return jsonDecode(res.body);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _globalStatsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!['status'] != 'success') {
            return const Center(child: Text("Failed to load global stats"));
          }

          final data = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _globalStatsFuture = _fetchGlobalStats();
              });
            },
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(
                    data['total_km_today']?.toDouble() ?? 0.0,
                    data['active_users_today']?.toInt() ?? 0,
                  ),
                ),
                SliverAppBar(
                  pinned: true,
                  backgroundColor: const Color(0xFFF8F9FE),
                  automaticallyImplyLeading: false,
                  elevation: 0,
                  toolbarHeight: 0,
                  bottom: TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.blueAccent,
                    labelColor: Colors.blueAccent,
                    unselectedLabelColor: Colors.grey,
                    tabs: const [
                      Tab(text: "Today"),
                      Tab(text: "Streaks"),
                      Tab(text: "Weekly"),
                    ],
                  ),
                ),
                SliverFillRemaining(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildLeaderboardList(data['today_leaderboard'], "km"),
                      _buildLeaderboardList(data['top_streaks'], "days"),
                      _buildLeaderboardList(data['weekly_leaderboard'], "km"),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(double totalKm, int activeUsers) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF4158D0), Color(0xFFC850C0)]),
        boxShadow: [BoxShadow(color: Colors.purple.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _headerStat("Total Distance", "$totalKm", "KM"),
          Container(width: 1, height: 40, color: Colors.white24),
          _headerStat("Active Now", "$activeUsers", "RUNNERS"),
        ],
      ),
    );
  }

  Widget _headerStat(String label, String value, String unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            Text(unit, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ],
    );
  }

  Widget _buildLeaderboardList(List list, String unit) {
    if (list.isEmpty) return const Center(child: Text("No records yet"));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final val = item['distance_km'] ?? item['streak'] ?? item['total_km'] ?? 0;
        final isTopThree = index < 3;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
          ),
          child: ListTile(
            leading: _buildRankBadge(index + 1),
            title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: index == 0 ? const Text("🏆 Current Leader", style: TextStyle(color: Colors.orange, fontSize: 11)) : null,
            trailing: Text("$val $unit",
                style: TextStyle(fontWeight: FontWeight.bold, color: isTopThree ? Colors.blueAccent : Colors.black87, fontSize: 16)),
          ),
        );
      },
    );
  }

  Widget _buildRankBadge(int rank) {
    if (rank == 1) return const CircleAvatar(backgroundColor: Color(0xFFFFD700), child: Icon(Icons.star, color: Colors.white));
    if (rank == 2) return const CircleAvatar(backgroundColor: Color(0xFFC0C0C0), child: Icon(Icons.looks_two, color: Colors.white));
    if (rank == 3) return const CircleAvatar(backgroundColor: Color(0xFFCD7F32), child: Icon(Icons.looks_3, color: Colors.white));
    return CircleAvatar(
      backgroundColor: Colors.grey.shade100,
      child: Text("$rank", style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}