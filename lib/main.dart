
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const RuseMetroApp());
}

// ГЛОБАЛНИ КОНСТАНТИ
const LatLng _startCenter = LatLng(43.840, 25.955);
const double _startZoom = 12.5;

class RuseMetroApp extends StatelessWidget {
  const RuseMetroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Русе Метро Tycoon',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MetroMapScreen(),
    );
  }
}

// --- МОДЕЛИ ---

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

// --- ФИЗИКА ---
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

  void setSpeed(double newSpeed) {
    speedMetersPerSecond = newSpeed;
    _calculatePhysics();
  }

  LatLng getPositionAt(double elapsedTime) {
    if (stations.isEmpty) return const LatLng(0, 0);
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
      if (timeInLoop <= currentTimeTracker + stopDurationSeconds) return stations[i+1].coords;
      currentTimeTracker += stopDurationSeconds;
    }
    return stations.last.coords;
  }

  bool isMovingRight(double elapsedTime) {
    if (stations.isEmpty) return true;
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
    if (index == -1) return null;
    double timeInLoop = currentElapsedTime % totalLoopDuration;
    double arrivalTime = _arrivalTimesAtStations[index];
    double diff = arrivalTime - timeInLoop;
    if (diff < 0) diff += totalLoopDuration;
    return diff.toInt();
  }
}

// --- ЕКРАН ---

class MetroMapScreen extends StatefulWidget {
  const MetroMapScreen({super.key});

  @override
  State<MetroMapScreen> createState() => _MetroMapScreenState();
}

class _MetroMapScreenState extends State<MetroMapScreen> with SingleTickerProviderStateMixin {
  
  final MapController _mapController = MapController();
  late AnimationController _animController;
  
  // ВРЕМЕНА ЗА ВСЯКА ЛИНИЯ
  double _timeL1 = 0.0;
  double _timeL2 = 0.0;
  double _timeL3 = 0.0;
  double _timeL4 = 0.0;
  
  // TYCOON & STATS
  double _money = 100.0; 
  final double _ticketPrice = 1.60;
  Timer? _moneyTimer;
  double _totalDistanceKm = 0.0; 
  final double _currentTrainSpeed = 120.0; // Фиксирана скорост

  // HISTORY
  final List<String> _searchHistory = []; 

  // CHAOS MODE
  String? _brokenTrainId; 
  int _repairTaps = 0; 
  bool _isTurboMode = false; 

  // FOLLOW TRAIN
  String? _followedTrainId;

  late final MetroLine line1, line2, line3, line4;
  late final RoutePhysics phys1F, phys1R, phys2F, phys2R, phys3F, phys3R, phys4F, phys4R;
  late final List<RoutePhysics> allPhysics;

  late List<MetroStation> uniqueStations;
  late List<MetroLine> allLines;
  
  Map<String, dynamic> trains = {};

  // UI State
  MetroStation? _routeStart;
  MetroStation? _routeEnd;
  String _routeResult = "";
  
  // ЛЕГЕНДА STATE
  MetroLine? _selectedLine;

  @override
  void initState() {
    super.initState();
    _initData();

    _animController = AnimationController(vsync: this, duration: const Duration(days: 1))..forward();
    _animController.addListener(_updateSimulation);

    _moneyTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (!_isLineBroken(1)) _money += 0.50;
        if (!_isLineBroken(2)) _money += 0.50;
        if (!_isLineBroken(3)) _money += 0.50;
        if (!_isLineBroken(4)) _money += 0.50;
        
        double speedKm = (_currentTrainSpeed / 1000.0) * (_isTurboMode ? 3 : 1);
        if (_brokenTrainId == null) _totalDistanceKm += speedKm;
      });
    });
  }

  void _initData() {
    final l1Stations = [
      MetroStation("Мол Русе", LatLng(43.852889, 25.990556), popularity: 5), 
      MetroStation("Олимпа", LatLng(43.850361, 25.979806), popularity: 3),
      MetroStation("Име 1", LatLng(43.845583, 25.966949), popularity: 2),
      MetroStation("Кръговото", LatLng(43.845944, 25.960194), isTransfer: true, popularity: 5),
      MetroStation("Л. Каравелов", LatLng(43.844074, 25.948995), isTransfer: true, popularity: 4),
      MetroStation("Дружба 2", LatLng(43.830379, 25.956580), isTransfer: true, popularity: 4),
      MetroStation("Волов", LatLng(43.835579, 25.965666), isTransfer: true, popularity: 3),
      MetroStation("Здравец", LatLng(43.847000, 25.982889), popularity: 4),
      MetroStation("Мол Русе (Край)", LatLng(43.852889, 25.990556), popularity: 1),
    ];
    line1 = MetroLine(name: "Линия 1", color: Colors.redAccent, stations: l1Stations, width: 7.0);
    phys1F = RoutePhysics(stations: l1Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys1R = RoutePhysics(stations: l1Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);

    final l2Stations = [
      MetroStation("Дружба 3", LatLng(43.826017, 25.972753), popularity: 3),
      MetroStation("Дружба 1", LatLng(43.830849, 25.963196), popularity: 3),
      MetroStation("Волов", LatLng(43.835579, 25.965666), isTransfer: true, popularity: 3),
      MetroStation("ЖП Гара", LatLng(43.833812, 25.956084), popularity: 4),
      MetroStation("Пазара", LatLng(43.841889, 25.960407), popularity: 5),
      MetroStation("Кръговото", LatLng(43.845944, 25.960194), isTransfer: true, popularity: 5),
      MetroStation("РУ Ангел Кънчев", LatLng(43.854684, 25.969598), popularity: 4),
      MetroStation("Младежки Парк", LatLng(43.859534, 25.966257), popularity: 5),
    ];
    line2 = MetroLine(name: "Линия 2", color: Colors.blueAccent, stations: l2Stations, width: 6.0);
    phys2F = RoutePhysics(stations: l2Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys2R = RoutePhysics(stations: l2Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);

    final l3Stations = [
      MetroStation("Кръговото", LatLng(43.845944, 25.960194), isTransfer: true, popularity: 5),
      MetroStation("Център", LatLng(43.848521, 25.953637), popularity: 5),
      MetroStation("Кея", LatLng(43.853004, 25.950266), popularity: 4),
      MetroStation("Младежки Парк", LatLng(43.859534, 25.966257), isTransfer: true, popularity: 5),
      MetroStation("Захарни заводи", LatLng(43.867365, 25.991048), popularity: 2),
      MetroStation("Дунав мост", LatLng(43.877057, 26.015669), popularity: 3),
      MetroStation("Мол Русе", LatLng(43.852889, 25.990556), isTransfer: true, popularity: 5), 
      MetroStation("Олимпа", LatLng(43.850361, 25.979806), popularity: 3),
      MetroStation("Име 1", LatLng(43.845583, 25.966949), popularity: 2),
      MetroStation("Кръговото (Край)", LatLng(43.845944, 25.960194), isTransfer: true, popularity: 1),
    ];
    line3 = MetroLine(name: "Линия 3", color: Colors.green, stations: l3Stations, width: 3.5);
    phys3F = RoutePhysics(stations: l3Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys3R = RoutePhysics(stations: l3Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);

    final l4Stations = [
      MetroStation("Басарбово", LatLng(43.774162, 25.951139), popularity: 2),
      MetroStation("Долапите", LatLng(43.796609, 25.931124), popularity: 2),
      MetroStation("Магазин Метро", LatLng(43.814856, 25.927688), popularity: 3),
      MetroStation("Л. Каравелов", LatLng(43.844074, 25.948995), isTransfer: true, popularity: 4), 
      MetroStation("Дружба 2", LatLng(43.830379, 25.956580), isTransfer: true, popularity: 4),   
      MetroStation("Средна кула", LatLng(43.802869, 25.939622), popularity: 2),
      MetroStation("Басарбово", LatLng(43.774162, 25.951139), popularity: 1),
    ];
    line4 = MetroLine(name: "Линия 4", color: Colors.orange, stations: l4Stations, width: 5.0);
    phys4F = RoutePhysics(stations: l4Stations, speedMetersPerSecond: _currentTrainSpeed); 
    phys4R = RoutePhysics(stations: l4Stations.reversed.toList(), speedMetersPerSecond: _currentTrainSpeed);

    uniqueStations = {...l1Stations, ...l2Stations, ...l3Stations, ...l4Stations}.toList();
    allLines = [line1, line2, line3, line4];
    allPhysics = [phys1F, phys1R, phys2F, phys2R, phys3F, phys3R, phys4F, phys4R];
  }

  bool _isLineBroken(int lineNum) {
    if (_brokenTrainId == null) return false;
    return _brokenTrainId!.startsWith("L$lineNum");
  }

  void _updateSimulation() {
    double delta = 0.02; 
    if (_isTurboMode) delta *= 3;

    setState(() {
      if (!_isLineBroken(1)) _timeL1 += delta;
      if (!_isLineBroken(2)) _timeL2 += delta;
      if (!_isLineBroken(3)) _timeL3 += delta;
      if (!_isLineBroken(4)) _timeL4 += delta;

      _updateTrain("L1_Fwd", phys1F, _timeL1, line1);
      _updateTrain("L1_Rev", phys1R, _timeL1, line1);
      _updateTrain("L2_Fwd", phys2F, _timeL2, line2);
      _updateTrain("L2_Rev", phys2R, _timeL2, line2);
      _updateTrain("L3_Fwd", phys3F, _timeL3, line3);
      _updateTrain("L3_Rev", phys3R, _timeL3, line3);
      _updateTrain("L4_Fwd", phys4F, _timeL4, line4);
      _updateTrain("L4_Rev", phys4R, _timeL4, line4);

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
    List<String> keys = trains.keys.toList();
    String target = keys[math.Random().nextInt(keys.length)];
    setState(() {
      _brokenTrainId = target;
      _repairTaps = 0; 
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("🚨 АВАРИЯ! Влак на линия ${target.split('_')[0]} се повреди!"), backgroundColor: Colors.red, duration: const Duration(seconds: 4))
    );
  }

  void _repairTrain() {
    if (_brokenTrainId == null) return;
    setState(() {
      _repairTaps++;
    });
    if (_repairTaps >= 5) {
      setState(() {
        _brokenTrainId = null;
        _money += 50.0; 
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Влакът е поправен! (+50 лв.)"), backgroundColor: Colors.green));
    } else {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🔧 Ремонт: ${_repairTaps * 20}%"), duration: const Duration(milliseconds: 500)));
    }
  }

  void _calculateRoute() {
    if (_routeStart == null || _routeEnd == null) {
      setState(() => _routeResult = "Моля изберете спирки.");
      return;
    }
    if (_routeStart == _routeEnd) {
      setState(() => _routeResult = "Вече сте на тази спирка!");
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
        routeDetails = "✅ Директна връзка с ${line.name}.";
        break;
      }
    }

    if (routeDetails.isEmpty) {
       timeEstimate = 15;
       routeDetails = "🔄 Маршрут с прикачване.";
    }

    setState(() => _routeResult = "$routeDetails\n💵 Цена: ${_ticketPrice.toStringAsFixed(2)} лв.\n⏱️ Време: ~$timeEstimate мин.");
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
              const Text("❤️ Любими спирки", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              if (favs.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text("Нямате любими спирки. Добавете ги от картата!", style: TextStyle(color: Colors.white54)))
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
                      const Text("🗺️ Планиране на маршрут", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 20),
                      if (_searchHistory.isNotEmpty) ...[
                        const Text("🕒 Последно търсени:", style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ..._searchHistory.map((s) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(s, style: const TextStyle(color: Colors.white70)))),
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 10),
                      ],
                      const Text("От:", style: TextStyle(color: Colors.white70)),
                      Autocomplete<MetroStation>(
                        optionsBuilder: (v) => v.text == '' ? uniqueStations : uniqueStations.where((s) => s.name.toLowerCase().contains(v.text.toLowerCase())),
                        displayStringForOption: (s) => s.name,
                        onSelected: (s) => _routeStart = s,
                        fieldViewBuilder: (ctx, controller, focusNode, onEditingComplete) {
                          return TextField(
                            controller: controller, focusNode: focusNode, onEditingComplete: onEditingComplete,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(hintText: "Начална спирка", filled: true, fillColor: Colors.black26, border: OutlineInputBorder()),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text("До:", style: TextStyle(color: Colors.white70)),
                      Autocomplete<MetroStation>(
                        optionsBuilder: (v) => v.text == '' ? uniqueStations : uniqueStations.where((s) => s.name.toLowerCase().contains(v.text.toLowerCase())),
                        displayStringForOption: (s) => s.name,
                        onSelected: (s) => _routeEnd = s,
                        fieldViewBuilder: (ctx, controller, focusNode, onEditingComplete) {
                          return TextField(
                            controller: controller, focusNode: focusNode, onEditingComplete: onEditingComplete,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(hintText: "Крайна спирка", filled: true, fillColor: Colors.black26, border: OutlineInputBorder()),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () { _calculateRoute(); setModalState(() {}); },
                          icon: const Icon(Icons.search),
                          label: const Text("Намери маршрут"),
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
        title: const Text("🎟️ Билети", style: TextStyle(color: Colors.white)),
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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Билет закупен!"), backgroundColor: Colors.green));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Няма пари!"), backgroundColor: Colors.red));
                  }
                }, 
                child: const Text("Купи билет (1.60 лв.)")
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
        String timeStr = seconds < 60 ? "< 1 мин" : "${(seconds / 60).round()} мин";
        arrivalInfos.add(ListTile(leading: Icon(Icons.train, color: color), title: Text("$lineName ($direction)"), trailing: Text(timeStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), dense: true));
      }
    }

    checkArrival("Линия 1", Colors.redAccent, phys1F, "Напред", _timeL1);
    checkArrival("Линия 1", Colors.redAccent, phys1R, "Обратно", _timeL1);
    checkArrival("Линия 2", Colors.blueAccent, phys2F, "Напред", _timeL2);
    checkArrival("Линия 2", Colors.blueAccent, phys2R, "Обратно", _timeL2);
    checkArrival("Линия 3", Colors.green, phys3F, "Напред", _timeL3);
    checkArrival("Линия 3", Colors.green, phys3R, "Обратно", _timeL3);
    checkArrival("Линия 4", Colors.orange, phys4F, "Напред", _timeL4);
    checkArrival("Линия 4", Colors.orange, phys4R, "Обратно", _timeL4);

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
                    Row(children: [const Icon(Icons.people, color: Colors.white70), const SizedBox(width: 10), Text("Натовареност: $passengers%", style: const TextStyle(color: Colors.white70))]),
                    const SizedBox(height: 10),
                    Column(children: arrivalInfos.isEmpty ? [const Text("Няма влакове", style: TextStyle(color: Colors.white30))] : arrivalInfos),
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  // --- ЛЕГЕНДА ---
  void _showLegend() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              height: 350,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Легенда", style: TextStyle(fontSize: 20, color: Colors.white)),
                        if (_selectedLine != null)
                          TextButton(onPressed: () { setState(() => _selectedLine = null); setModalState((){}); }, child: const Text("Покажи всички"))
                      ],
                    ),
                    const Divider(),
                    _buildInteractiveLegendItem(line1, setModalState),
                    _buildInteractiveLegendItem(line2, setModalState),
                    _buildInteractiveLegendItem(line3, setModalState),
                    _buildInteractiveLegendItem(line4, setModalState),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildInteractiveLegendItem(MetroLine line, StateSetter setModalState) {
    bool isSelected = _selectedLine == line;
    return ListTile(
      onTap: () {
        setState(() => _selectedLine = isSelected ? null : line);
        setModalState(() {});
      },
      leading: Container(width: 30, height: 5, color: line.color),
      title: Text(line.name, style: TextStyle(color: isSelected ? Colors.white : Colors.white60, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
    );
  }

  void _toggleTurbo() {
    setState(() => _isTurboMode = !_isTurboMode);
  }

  Color _getLineOpacity(MetroLine line) {
    if (_selectedLine == null) { return line.color.withValues(alpha: 0.7); } 
    if (_selectedLine == line) { return line.color; }
    return line.color.withValues(alpha: 0.1); 
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];
    
    for (var station in uniqueStations) {
      Color heatColor = station.popularity > 3 ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3);
      markers.add(
        Marker(
          point: station.coords,
          width: 35, height: 35,
          child: Container(decoration: BoxDecoration(color: heatColor, shape: BoxShape.circle)),
        )
      );
      markers.add(
        Marker(
          point: station.coords,
          width: 30, height: 30,
          child: GestureDetector(
            onTap: () => _showStationInfo(station),
            child: Image.asset(
              'assets/station.png',
              color: station.isTransfer ? Colors.orange : (station.isFavorite ? Colors.pink : null),
            ),
          ),
        )
      );
    }
    
    trains.forEach((id, data) {
      MetroLine lineObj = data['lineObj'];
      if (_selectedLine != null && _selectedLine != lineObj) return;

      bool isBroken = (id == _brokenTrainId);
      
      markers.add(
        Marker(
          point: data['pos'],
          width: 30, height: 30,
          child: GestureDetector(
            onTap: () {
              if (isBroken) {
                _repairTrain();
              } else {
                setState(() => _followedTrainId = id); 
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("🎥 Камерата следи влак $id"), duration: const Duration(seconds: 1)));
              }
            },
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(data['isRight'] ? 1.0 : -1.0, 1.0, 1.0),
              child: isBroken 
                ? ColorFiltered(colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation), child: Image.asset('assets/train.png'))
                : Image.asset('assets/train.png'),
            ),
          ),
        )
      );
    });
    return markers;
  }

  @override
  void dispose() {
    _animController.dispose();
    _mapController.dispose();
    _moneyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        backgroundColor: Colors.grey[900],
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.blueAccent),
              accountName: const Text("Metro Tycoon Player"),
              accountEmail: Text("Изминати км: ${_totalDistanceKm.toStringAsFixed(1)} км"),
              currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, size: 40)),
            ),
            ListTile(
              leading: const Icon(Icons.confirmation_number, color: Colors.orange),
              title: const Text("Билети", style: TextStyle(color: Colors.white)),
              onTap: _showTicketingScreen,
            ),
            ListTile(
              leading: const Icon(Icons.favorite, color: Colors.pink),
              title: const Text("Любими спирки", style: TextStyle(color: Colors.white)),
              onTap: _showFavoritesList,
            ),
            const Divider(color: Colors.white24),
            const Padding(padding: EdgeInsets.all(16), child: Text("ADMIN PANEL", style: TextStyle(color: Colors.white54))),
            ListTile(
              leading: const Icon(Icons.warning, color: Colors.redAccent),
              title: const Text("Предизвикай проблем!", style: TextStyle(color: Colors.white)),
              onTap: () { _triggerChaos(); Navigator.pop(context); },
            ),
            ListTile(
              leading: const Icon(Icons.speed, color: Colors.yellow),
              title: const Text("Турбо Режим", style: TextStyle(color: Colors.white)),
              trailing: Switch(value: _isTurboMode, onChanged: (v) => _toggleTurbo(), activeTrackColor: Colors.yellow),
            ),
          ],
        ),
      ),

      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _startCenter,
              initialZoom: _startZoom,
              onPositionChanged: (pos, hasGesture) {
                if (hasGesture) { setState(() => _followedTrainId = null); } 
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.ruse.metro.tycoon', 
              ),
              PolylineLayer(
                polylines: allLines.map((l) => Polyline(points: l.routePoints, strokeWidth: l.width, color: _getLineOpacity(l))).toList(),
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),

          Positioned(
            top: 50, right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.green)),
              child: Row(children: [const Icon(Icons.attach_money, color: Colors.green), Text(_money.toStringAsFixed(2), style: const TextStyle(color: Colors.green, fontSize: 18, fontWeight: FontWeight.bold))]),
            ),
          ),

          Positioned(
            top: 50, left: 16,
            child: Builder(builder: (context) => FloatingActionButton.small(
              backgroundColor: Colors.white,
              child: const Icon(Icons.menu, color: Colors.black),
              onPressed: () => Scaffold.of(context).openDrawer(),
            )),
          ),
          
          if (_brokenTrainId != null)
            Positioned(
              top: 100, right: 16, left: 16,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(10)),
                child: const Text("⚠️ ВНИМАНИЕ: АВАРИЯ! НАМЕРИ СИВИЯ ВЛАК И ГО УДАРИ С ЧУКА (TAP)!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
          FloatingActionButton(heroTag: "btn_route", onPressed: _showRoutePlanner, backgroundColor: Colors.greenAccent, child: const Icon(Icons.map, color: Colors.black)),
          const SizedBox(height: 10),
          FloatingActionButton(heroTag: "btn_legend", onPressed: _showLegend, backgroundColor: Colors.blueAccent, child: const Icon(Icons.list_alt, color: Colors.white)),
        ],
      ),
    );
  }
}