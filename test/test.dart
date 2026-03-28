import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const RuseMetroApp());
}

// GLOBAL CONSTANTS
const LatLng _startCenter = LatLng(43.840, 25.955);
const double _startZoom = 12.5;

class RuseMetroApp extends StatelessWidget {
  const RuseMetroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ruse Metro Tycoon',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.purple,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MetroMapScreen(),
    );
  }
}

// --- MODELS ---

class MetroStation {
  final String name;
  final LatLng coords;
  final bool isTransfer;
  final int popularity; 
  bool isFavorite; 

  MetroStation(this.name, this.coords, {this.isTransfer = false, this.popularity = 1, this.isFavorite = false});

  @override
  String toString() => name;
}

class MetroLine {
  final String name;
  final Color color;
  final List<MetroStation> stations;
  final double width;

  MetroLine({required this.name, required this.color, required this.stations, this.width = 4.0});
  
  List<LatLng> get routePoints => stations.map((s) => s.coords).toList();
}

// --- AUTOMATIC PHYSICS ---
class RoutePhysics {
  final List<MetroStation> stations;
  double speedMetersPerSecond;
  final double stopDurationSeconds;

  late final List<double> _segmentTravelTimes;
  late final List<double> _arrivalTimesAtStations;
  late final double totalLoopDuration;

  RoutePhysics({
    required this.stations,
    this.speedMetersPerSecond = 120.0, 
    this.stopDurationSeconds = 1.0, 
  }) {
    _calculatePhysics();
  }

  void _calculatePhysics() {
    final Distance distanceCalc = const Distance();
    _segmentTravelTimes = [];
    _arrivalTimesAtStations = [0.0];
    double totalTime = 0;

    for (int i = 0; i < stations.length - 1; i++) {
      double dist = distanceCalc.as(LengthUnit.Meter, stations[i].coords, stations[i+1].coords);
      double travelTime = dist / speedMetersPerSecond;
      _segmentTravelTimes.add(travelTime);
      totalTime += travelTime;
      _arrivalTimesAtStations.add(totalTime);
      totalTime += stopDurationSeconds; 
    }
    totalLoopDuration = totalTime + (stations.length > 1 ? 5.0 : 0);
  }

  LatLng getPositionAt(double elapsedTime) {
    if (stations.isEmpty) { return const LatLng(0, 0); }
    double timeInLoop = elapsedTime % totalLoopDuration;
    double currentTimeTracker = 0.0;

    for (int i = 0; i < _segmentTravelTimes.length; i++) {
      double travelTime = _segmentTravelTimes[i];
      if (timeInLoop <= currentTimeTracker + travelTime) {
        double pct = (timeInLoop - currentTimeTracker) / travelTime;
        LatLng p1 = stations[i].coords;
        LatLng p2 = stations[i+1].coords;
        return LatLng(
          p1.latitude + (p2.latitude - p1.latitude) * pct,
          p1.longitude + (p2.longitude - p1.longitude) * pct,
        );
      }
      currentTimeTracker += travelTime;
      if (timeInLoop <= currentTimeTracker + stopDurationSeconds) { return stations[i+1].coords; }
      currentTimeTracker += stopDurationSeconds;
    }
    return stations.last.coords;
  }

  bool isMovingRight(double elapsedTime) {
    if (stations.isEmpty) { return true; }
    double timeInLoop = elapsedTime % totalLoopDuration;
    double currentTimeTracker = 0.0;
    for (int i = 0; i < _segmentTravelTimes.length; i++) {
      double travelTime = _segmentTravelTimes[i];
      if (timeInLoop <= currentTimeTracker + travelTime) {
        return stations[i+1].coords.longitude > stations[i].coords.longitude;
      }
      currentTimeTracker += travelTime + stopDurationSeconds;
    }
    return true;
  }

  int? getSecondsToStation(MetroStation targetStation, double currentElapsedTime) {
    int index = stations.indexOf(targetStation);
    if (index == -1) { return null; }
    double timeInLoop = currentElapsedTime % totalLoopDuration;
    double arrivalTime = _arrivalTimesAtStations[index];
    double diff = arrivalTime - timeInLoop;
    if (diff < 0) { diff += totalLoopDuration; }
    return diff.toInt();
  }
}

// --- MANUAL PHYSICS (LINE 5) ---
class ManualPhysics {
  final List<MetroStation> stations;
  double currentProgress = 0.0; 
  double totalDistance = 0.0;

  ManualPhysics({required this.stations}) {
    final Distance distanceCalc = const Distance();
    for (int i = 0; i < stations.length - 1; i++) {
      totalDistance += distanceCalc.as(LengthUnit.Meter, stations[i].coords, stations[i+1].coords);
    }
  }

  void update(double speedFactor) {
    double step = (speedFactor * 200.0) / totalDistance; 
    currentProgress += step;
    if (currentProgress >= 1.0) { currentProgress = 0.0; }
  }

  LatLng getCurrentPosition() {
    if (stations.isEmpty) { return const LatLng(0,0); }
    double targetDist = currentProgress * totalDistance;
    double coveredDist = 0.0;
    final Distance distanceCalc = const Distance();

    for (int i = 0; i < stations.length - 1; i++) {
      double segmentDist = distanceCalc.as(LengthUnit.Meter, stations[i].coords, stations[i+1].coords);
      if (coveredDist + segmentDist >= targetDist) {
        double pct = (targetDist - coveredDist) / segmentDist;
        LatLng p1 = stations[i].coords;
        LatLng p2 = stations[i+1].coords;
        return LatLng(
          p1.latitude + (p2.latitude - p1.latitude) * pct,
          p1.longitude + (p2.longitude - p1.longitude) * pct,
        );
      }
      coveredDist += segmentDist;
    }
    return stations.last.coords;
  }

  MetroStation? getNearestStation(LatLng currentPos) {
    final Distance distanceCalc = const Distance();
    for (var station in stations) {
      if (distanceCalc.as(LengthUnit.Meter, currentPos, station.coords) < 150) {
        return station;
      }
    }
    return null;
  }
}

// --- SCREEN ---

class MetroMapScreen extends StatefulWidget {
  const MetroMapScreen({super.key});

  @override
  State<MetroMapScreen> createState() => _MetroMapScreenState();
}

class _MetroMapScreenState extends State<MetroMapScreen> with SingleTickerProviderStateMixin {
  
  final MapController _mapController = MapController();
  late AnimationController _animController;
  
  // LINE TIMES
  double _timeL1 = 0.0, _timeL2 = 0.0, _timeL3 = 0.0, _timeL4 = 0.0;
  
  // LINE 5 (SIMULATOR)
  double _driverSpeed = 0.0; 
  late ManualPhysics _physL5;
  String _l5Status = "Stationary";

  // TYCOON
  double _money = 100.0; 
  final double _ticketPrice = 1.60;
  Timer? _moneyTimer;
  double _totalDistanceKm = 0.0; 
  final double _currentTrainSpeed = 120.0; 

  // QUESTS
  String? _activeQuest;
  MetroStation? _questTargetStation;
  Timer? _questTimer;

  // CHAOS & HISTORY
  final List<String> _searchHistory = []; 
  String? _brokenTrainId; 
  int _repairTaps = 0; 
  bool _isTurboMode = false; 
  String? _followedTrainId;

  late final MetroLine line1, line2, line3, line4, line5;
  late final RoutePhysics phys1F, phys1R, phys2F, phys2R, phys3F, phys3R, phys4F, phys4R;

  late List<MetroStation> uniqueStations;
  late List<MetroLine> allLines;
  Map<String, dynamic> trains = {};

  // UI
  MetroStation? _routeStart;
  MetroStation? _routeEnd;
  String _routeResult = "";
  MetroLine? _selectedLine;

  @override
  void initState() {
    super.initState();
    _initData();

    _animController = AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
    _animController.addListener(_updateSimulation);

    // Passive Income
    _moneyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (!_isLineBroken(1)) { _money += 0.50; }
        if (!_isLineBroken(2)) { _money += 0.50; }
        if (!_isLineBroken(3)) { _money += 0.50; }
        if (!_isLineBroken(4)) { _money += 0.50; }
        
        // Stats update
        double speedKm = (_currentTrainSpeed / 1000.0) * (_isTurboMode ? 3 : 1);
        if (_brokenTrainId == null) { _totalDistanceKm += speedKm; }
      });
    });

    // Quest Generator
    _questTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (_activeQuest == null) {
        _generateNewQuest();
      }
    });
  }

  void _initData() {
    final l1Stations = [MetroStation("Mall Ruse", LatLng(43.852889, 25.990556), popularity: 5), MetroStation("Olimpa", LatLng(43.850361, 25.979806)), MetroStation("Roundabout", LatLng(43.845944, 25.960194), isTransfer: true), MetroStation("Druzhba 2", LatLng(43.830379, 25.956580))];
    final l2Stations = [MetroStation("Druzhba 3", LatLng(43.826017, 25.972753)), MetroStation("Railway Station", LatLng(43.833812, 25.956084)), MetroStation("Roundabout", LatLng(43.845944, 25.960194), isTransfer: true), MetroStation("Youth Park", LatLng(43.859534, 25.966257))];
    final l3Stations = [MetroStation("Roundabout", LatLng(43.845944, 25.960194), isTransfer: true), MetroStation("Center", LatLng(43.848521, 25.953637)), MetroStation("Quay", LatLng(43.853004, 25.950266)), MetroStation("Danube Bridge", LatLng(43.877057, 26.015669))];
    final l4Stations = [MetroStation("Basarbovo", LatLng(43.774162, 25.951139)), MetroStation("Metro Store", LatLng(43.814856, 25.927688)), MetroStation("Druzhba 2", LatLng(43.830379, 25.956580))];

    // LINE 5 (PLAYER)
    final l5Stations = [
      MetroStation("West Zone", LatLng(43.829, 25.920), popularity: 2),
      MetroStation("Port", LatLng(43.848, 25.935), popularity: 4),
      MetroStation("Center", LatLng(43.848521, 25.953637), isTransfer: true, popularity: 5),
      MetroStation("University", LatLng(43.855, 25.970), popularity: 5),
      MetroStation("Lipnik", LatLng(43.865, 26.000), popularity: 3),
    ];

    line1 = MetroLine(name: "Line 1", color: Colors.redAccent, stations: l1Stations, width: 6.0);
    line2 = MetroLine(name: "Line 2", color: Colors.blueAccent, stations: l2Stations, width: 6.0);
    line3 = MetroLine(name: "Line 3", color: Colors.green, stations: l3Stations, width: 4.0);
    line4 = MetroLine(name: "Line 4", color: Colors.orange, stations: l4Stations, width: 5.0);
    line5 = MetroLine(name: "Line 5 (PLAYER)", color: Colors.purpleAccent, stations: l5Stations, width: 8.0);

    phys1F = RoutePhysics(stations: l1Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys1R = RoutePhysics(stations: l1Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);
    phys2F = RoutePhysics(stations: l2Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys2R = RoutePhysics(stations: l2Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);
    phys3F = RoutePhysics(stations: l3Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys3R = RoutePhysics(stations: l3Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);
    phys4F = RoutePhysics(stations: l4Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys4R = RoutePhysics(stations: l4Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);
    
    _physL5 = ManualPhysics(stations: l5Stations);

    uniqueStations = {...l1Stations, ...l2Stations, ...l3Stations, ...l4Stations, ...l5Stations}.toList();
    allLines = [line1, line2, line3, line4, line5];
  }

  bool _isLineBroken(int lineNum) {
    if (_brokenTrainId == null) { return false; }
    return _brokenTrainId!.startsWith("L$lineNum");
  }

  void _generateNewQuest() {
    final target = line5.stations[math.Random().nextInt(line5.stations.length)];
    setState(() {
      _questTargetStation = target;
      _activeQuest = "👵 Grandma Ginka is waiting at: ${target.name}! Drive there fast!";
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_activeQuest!), backgroundColor: Colors.purple, duration: const Duration(seconds: 5)));
  }

  void _checkQuestCompletion(LatLng pos) {
    if (_activeQuest != null && _questTargetStation != null) {
      if (_driverSpeed < 0.1 && _physL5.getNearestStation(pos) == _questTargetStation) {
        setState(() {
          _money += 150.0; 
          _activeQuest = null;
          _questTargetStation = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ SUCCESS! Grandma Ginka is happy! (+150 lv.)"), backgroundColor: Colors.green, duration: Duration(seconds: 3)));
      }
    }
  }

  void _updateSimulation() {
    double delta = 0.02; 
    if (_isTurboMode) { delta *= 3; }

    setState(() {
      if (!_isLineBroken(1)) { _timeL1 += delta; }
      if (!_isLineBroken(2)) { _timeL2 += delta; }
      if (!_isLineBroken(3)) { _timeL3 += delta; }
      if (!_isLineBroken(4)) { _timeL4 += delta; }

      _updateTrain("L1_Fwd", phys1F, _timeL1, line1);
      _updateTrain("L1_Rev", phys1R, _timeL1, line1);
      _updateTrain("L2_Fwd", phys2F, _timeL2, line2);
      _updateTrain("L2_Rev", phys2R, _timeL2, line2);
      _updateTrain("L3_Fwd", phys3F, _timeL3, line3);
      _updateTrain("L3_Rev", phys3R, _timeL3, line3);
      _updateTrain("L4_Fwd", phys4F, _timeL4, line4);
      _updateTrain("L4_Rev", phys4R, _timeL4, line4);

      // PLAYER TRAIN
      if (_driverSpeed > 0) {
        _physL5.update(_driverSpeed * delta * 0.5); 
        _l5Status = "Moving (${(_driverSpeed * 100).toInt()} km/h)";
      } else {
        _l5Status = "Stopped";
      }
      
      LatLng l5Pos = _physL5.getCurrentPosition();
      trains["L5_Player"] = {
        'pos': l5Pos,
        'isRight': true, 
        'color': Colors.purpleAccent,
        'lineObj': line5,
        'lineName': "L5"
      };

      _checkQuestCompletion(l5Pos);

      if (_followedTrainId != null && trains.containsKey(_followedTrainId)) {
        _mapController.move(trains[_followedTrainId]['pos'], _mapController.camera.zoom);
      }
    });
  }

  void _updateTrain(String id, RoutePhysics phys, double t, MetroLine line) {
    trains[id] = {
      'pos': phys.getPositionAt(t),
      'isRight': phys.isMovingRight(t),
      'color': line.color,
      'lineObj': line, 
      'lineName': id.split('_')[0],
    };
  }

  void _triggerChaos() {
    List<String> keys = trains.keys.where((k) => k != "L5_Player").toList(); 
    if (keys.isEmpty) { return; }
    String target = keys[math.Random().nextInt(keys.length)];
    setState(() {
      _brokenTrainId = target;
      _repairTaps = 0; 
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🚨 FAILURE on Line ${target.split('_')[0]}!"), backgroundColor: Colors.red));
  }

  void _repairTrain() {
    if (_brokenTrainId == null) { return; }
    setState(() => _repairTaps++);
    if (_repairTaps >= 5) {
      setState(() { _brokenTrainId = null; _money += 50.0; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Repaired!"), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🔧 Repair: ${_repairTaps * 20}%"), duration: const Duration(milliseconds: 500)));
    }
  }

  void _calculateRoute() {
    if (_routeStart == null || _routeEnd == null) {
      setState(() => _routeResult = "Please select stations.");
      return;
    }
    if (_routeStart == _routeEnd) {
      setState(() => _routeResult = "You are already here!");
      return;
    }

    String routeString = "${_routeStart!.name} -> ${_routeEnd!.name}";
    if (!_searchHistory.contains(routeString)) {
      setState(() {
        _searchHistory.insert(0, routeString);
        if (_searchHistory.length > 5) {
          _searchHistory.removeLast();
        }
      });
    }

    int timeEstimate = 0;
    String routeDetails = "";

    for (var line in allLines) {
      if (line.stations.contains(_routeStart) && line.stations.contains(_routeEnd)) {
        int dist = (line.stations.indexOf(_routeStart!) - line.stations.indexOf(_routeEnd!)).abs();
        timeEstimate = dist * 2 + 2; 
        routeDetails = "✅ Direct connection with ${line.name}.";
        break;
      }
    }

    if (routeDetails.isEmpty) {
       timeEstimate = 15;
       routeDetails = "🔄 Route with transfer.";
    }

    setState(() => _routeResult = "$routeDetails\n💵 Price: ${_ticketPrice.toStringAsFixed(2)} lv.\n⏱️ Time: ~$timeEstimate min.");
  }

  void _showFavoritesList() {
    Navigator.pop(context); 
    
    final favs = uniqueStations.where((s) => s.isFavorite).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("❤️ Favorite Stations", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (favs.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text("No favorites yet. Add them from the map!", style: TextStyle(color: Colors.white54)))
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: favs.length,
                    itemBuilder: (ctx, index) {
                      final station = favs[index];
                      return ListTile(
                        leading: const Icon(Icons.place, color: Colors.pinkAccent),
                        title: Text(station.name, style: const TextStyle(color: Colors.white)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _mapController.move(station.coords, 16.0);
                        },
                      );
                    }
                  ),
                )
            ],
          ),
        );
      }
    );
  }

  void _showRoutePlanner() {
    setState(() {
      _routeResult = "";
      _routeStart = null;
      _routeEnd = null;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(maxHeight: 600),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("🗺️ Route Planner", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 20),
                      if (_searchHistory.isNotEmpty) ...[
                        const Text("🕒 Recent:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ..._searchHistory.map((s) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(s, style: const TextStyle(color: Colors.white70)))),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 10),
                      ],
                      const Text("From:", style: TextStyle(color: Colors.white70)),
                      Autocomplete<MetroStation>(
                        optionsBuilder: (v) => v.text == '' ? uniqueStations : uniqueStations.where((s) => s.name.toLowerCase().contains(v.text.toLowerCase())),
                        displayStringForOption: (s) => s.name,
                        onSelected: (s) => _routeStart = s,
                        fieldViewBuilder: (ctx, controller, focusNode, onEditingComplete) {
                          return TextField(
                            controller: controller, focusNode: focusNode, onEditingComplete: onEditingComplete,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(hintText: "Start Station", filled: true, fillColor: Colors.black26, border: OutlineInputBorder()),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text("To:", style: TextStyle(color: Colors.white70)),
                      Autocomplete<MetroStation>(
                        optionsBuilder: (v) => v.text == '' ? uniqueStations : uniqueStations.where((s) => s.name.toLowerCase().contains(v.text.toLowerCase())),
                        displayStringForOption: (s) => s.name,
                        onSelected: (s) => _routeEnd = s,
                        fieldViewBuilder: (ctx, controller, focusNode, onEditingComplete) {
                          return TextField(
                            controller: controller, focusNode: focusNode, onEditingComplete: onEditingComplete,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(hintText: "End Station", filled: true, fillColor: Colors.black26, border: OutlineInputBorder()),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () { _calculateRoute(); setModalState(() {}); },
                          icon: const Icon(Icons.search),
                          label: const Text("Find Route"),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_routeResult.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                          child: Text(_routeResult, style: const TextStyle(color: Colors.white, fontSize: 16)),
                        )
                    ],
                  ),
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showTicketingScreen() {
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text("🎟️ Tickets", style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_2, size: 80, color: Colors.white),
              const SizedBox(height: 10),
              const Text("Ruse Metro Pass", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_money >= 1.60) {
                    setState(() => _money -= 1.60);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Ticket purchased!"), backgroundColor: Colors.green));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Not enough money!"), backgroundColor: Colors.red));
                  }
                }, 
                child: const Text("Buy Ticket (1.60 lv.)")
              )
            ],
          ),
        ),
      )
    );
  }

  void _showStationInfo(MetroStation station) {
    int passengers = (station.popularity * 15) + math.Random().nextInt(20);
    if (passengers > 100) { passengers = 100; } 

    List<Widget> arrivalInfos = [];

    void checkArrival(String lineName, Color color, RoutePhysics phys, String direction, double currentLineTime) {
      int? seconds = phys.getSecondsToStation(station, currentLineTime);
      if (seconds != null) {
        String timeStr = seconds < 60 ? "< 1 min" : "${(seconds / 60).round()} min";
        arrivalInfos.add(ListTile(leading: Icon(Icons.train, color: color), title: Text("$lineName ($direction)"), trailing: Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), dense: true));
      }
    }

    checkArrival("Line 1", Colors.redAccent, phys1F, "Fwd", _timeL1);
    checkArrival("Line 1", Colors.redAccent, phys1R, "Rev", _timeL1);
    checkArrival("Line 2", Colors.blueAccent, phys2F, "Fwd", _timeL2);
    checkArrival("Line 2", Colors.blueAccent, phys2R, "Rev", _timeL2);
    checkArrival("Line 3", Colors.green, phys3F, "Fwd", _timeL3);
    checkArrival("Line 3", Colors.green, phys3R, "Rev", _timeL3);
    checkArrival("Line 4", Colors.orange, phys4F, "Fwd", _timeL4);
    checkArrival("Line 4", Colors.orange, phys4R, "Rev", _timeL4);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(station.name, style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold))),
                        IconButton(
                          icon: Icon(station.isFavorite ? Icons.favorite : Icons.favorite_border, color: Colors.pink),
                          onPressed: () { setState(() => station.isFavorite = !station.isFavorite); setSheetState(() {}); },
                        )
                      ],
                    ),
                    const Divider(color: Colors.white24),
                    Row(children: [const Icon(Icons.people, color: Colors.white70), const SizedBox(width: 10), Text("Crowd: $passengers%", style: const TextStyle(color: Colors.white70))]),
                    const SizedBox(height: 10),
                    Column(children: arrivalInfos.isEmpty ? [const Text("No trains", style: TextStyle(color: Colors.white30))] : arrivalInfos),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  void _showLegend() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.grey[900],
      builder: (context) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: const EdgeInsets.all(20), height: 400,
          child: SingleChildScrollView(
            child: Column(children: [
              const Text("Legend", style: TextStyle(fontSize: 20, color: Colors.white)),
              const Divider(),
              _buildInteractiveLegendItem(line1, setModalState),
              _buildInteractiveLegendItem(line2, setModalState),
              _buildInteractiveLegendItem(line3, setModalState),
              _buildInteractiveLegendItem(line4, setModalState),
              _buildInteractiveLegendItem(line5, setModalState), 
            ]),
          ),
        )
      ),
    );
  }

  Widget _buildInteractiveLegendItem(MetroLine line, StateSetter setModalState) {
    bool isSelected = _selectedLine == line;
    return ListTile(
      onTap: () { setState(() => _selectedLine = isSelected ? null : line); setModalState(() {}); },
      leading: Container(width: 30, height: 5, color: line.color),
      title: Text(line.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white60)),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
    );
  }

  void _toggleTurbo() { setState(() => _isTurboMode = !_isTurboMode); }

  Color _getLineOpacity(MetroLine line) {
    if (_selectedLine == null) { return line.color.withValues(alpha: 0.7); }
    if (_selectedLine == line) { return line.color; }
    return line.color.withValues(alpha: 0.1); 
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];
    
    for (var station in uniqueStations) {
      bool isQuestTarget = (station == _questTargetStation);
      
      markers.add(Marker(
        point: station.coords, width: isQuestTarget ? 50 : 30, height: isQuestTarget ? 50 : 30,
        child: GestureDetector(
          onTap: () => _showStationInfo(station),
          child: isQuestTarget 
            ? const Icon(Icons.location_on, color: Colors.purpleAccent, size: 40) 
            : Image.asset('assets/station.png', color: station.isTransfer ? Colors.orange : (station.isFavorite ? Colors.pink : null)),
        ),
      ));
    }
    
    trains.forEach((id, data) {
      MetroLine lineObj = data['lineObj'];
      if (_selectedLine != null && _selectedLine != lineObj) { return; }
      bool isBroken = (id == _brokenTrainId);
      bool isPlayer = (id == "L5_Player");

      markers.add(Marker(
        point: data['pos'], width: isPlayer ? 40 : 30, height: isPlayer ? 40 : 30,
        child: GestureDetector(
          onTap: () {
            if (isBroken) {
              _repairTrain();
            } else if (isPlayer) {
               setState(() => _followedTrainId = id);
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🕹️ YOU ARE DRIVING! Use the slider below.")));
            } else {
               setState(() => _followedTrainId = id);
            }
          },
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(data['isRight'] ? 1.0 : -1.0, 1.0, 1.0),
            child: isPlayer 
              ? const Icon(Icons.train, color: Colors.purpleAccent, size: 35) 
              : (isBroken 
                  ? ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: Image.asset('assets/train.png'))
                  : Image.asset('assets/train.png')),
          ),
        ),
      ));
    });
    return markers;
  }

  @override
  void dispose() {
    _animController.dispose();
    _mapController.dispose();
    _moneyTimer?.cancel();
    _questTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        backgroundColor: Colors.grey[900],
        child: ListView(children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.purple),
            accountName: const Text("Metro Tycoon Driver"),
            // USING THE VARIABLE TO PREVENT UNUSED WARNING
            accountEmail: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Funds: ${_money.toStringAsFixed(2)} lv."),
                Text("Travelled: ${_totalDistanceKm.toStringAsFixed(1)} km"),
              ],
            ),
            currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, size: 40)),
          ),
          ListTile(leading: const Icon(Icons.confirmation_number, color: Colors.orange), title: const Text("Tickets"), onTap: _showTicketingScreen),
          ListTile(leading: const Icon(Icons.favorite, color: Colors.pink), title: const Text("Favorites"), onTap: _showFavoritesList),
          const Divider(color: Colors.white24),
          const Padding(padding: EdgeInsets.all(16), child: Text("ADMIN PANEL", style: TextStyle(color: Colors.white54))),
          ListTile(leading: const Icon(Icons.warning, color: Colors.red), title: const Text("Trigger Failure"), onTap: () { _triggerChaos(); Navigator.pop(context); }),
          ListTile(
            leading: const Icon(Icons.speed, color: Colors.yellow),
            title: const Text("Turbo Mode"),
            trailing: Switch(value: _isTurboMode, onChanged: (v) => _toggleTurbo(), activeTrackColor: Colors.yellow),
          ),
        ]),
      ),

      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _startCenter, initialZoom: _startZoom,
              onPositionChanged: (pos, hasGesture) { if (hasGesture) { setState(() => _followedTrainId = null); } },
            ),
            children: [
              TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.ruse.metro'),
              PolylineLayer(polylines: allLines.map((l) => Polyline(points: l.routePoints, strokeWidth: l.width, color: _getLineOpacity(l))).toList()),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          if (_activeQuest != null)
            Positioned(
              top: 40, left: 20, right: 20,
              child: Card(
                color: Colors.purple,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(children: [
                    const Icon(Icons.star, color: Colors.yellow),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_activeQuest!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ]),
                ),
              ),
            ),

          Positioned(
            top: 50, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green)),
              child: Row(children: [const Icon(Icons.attach_money, color: Colors.green), Text(_money.toStringAsFixed(2), style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold))]),
            ),
          ),

          Positioned(top: 50, left: 16, child: Builder(builder: (context) => FloatingActionButton.small(backgroundColor: Colors.white, child: const Icon(Icons.menu, color: Colors.black), onPressed: () => Scaffold.of(context).openDrawer()))),
          
          if (_brokenTrainId != null)
            Positioned(top: 120, right: 16, left: 16, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)), child: const Text("⚠️ FAILURE! Find the grey train and fix it!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center))),

          Positioned(
            bottom: 20, left: 20, right: 80, 
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.purpleAccent, width: 2)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Line 5: $_l5Status", style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _driverSpeed,
                    min: 0.0, max: 1.0,
                    activeColor: Colors.purpleAccent,
                    inactiveColor: Colors.purple[100],
                    onChanged: (val) {
                      setState(() => _driverSpeed = val);
                    },
                  ),
                  const Text("Slide to accelerate", style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
      
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(heroTag: "btn_north", onPressed: () => _mapController.rotate(0), backgroundColor: Colors.grey[800], child: const Icon(Icons.explore, color: Colors.white)),
          const SizedBox(height: 10),
          FloatingActionButton.small(heroTag: "btn_center", onPressed: () { _mapController.move(_startCenter, _startZoom); _mapController.rotate(0); setState(() => _followedTrainId = null); }, backgroundColor: Colors.grey[800], child: const Icon(Icons.center_focus_strong, color: Colors.white)),
          const SizedBox(height: 10),
          // RESTORED ROUTE PLANNER BUTTON
          FloatingActionButton(heroTag: "btn_route", onPressed: _showRoutePlanner, backgroundColor: Colors.greenAccent, child: const Icon(Icons.map, color: Colors.black)),
          const SizedBox(height: 10),
          FloatingActionButton(heroTag: "btn_legend", onPressed: _showLegend, backgroundColor: Colors.blueAccent, child: const Icon(Icons.list_alt, color: Colors.white)),
        ],
      ),
    );
  }
}