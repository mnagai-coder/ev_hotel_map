import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:csv/csv.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// ★★★ ここにAPIキーを貼り直してください ★★★
const String googleMapsApiKey = 'AIzaSyDzd-cyeB0xm1DZQkMZkYNQCHZZ3CnHGDU';

void main() {
  runApp(const EvHotelApp());
}

// データモデル
class Hotel {
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String price;
  final String siteUrl;
  final String evType;
  final String chargerCount;
  final String output;
  final String maxCurrent;
  final String category;
  final String chargingFee;
  final String parkingFee;
  final String contact;
  final String reservation;
  final String manufacturer;
  final String auth;
  final String notes;
  final String imageUrl;
  final String affiliateUrl;

  Hotel({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.price,
    required this.siteUrl,
    required this.evType,
    required this.chargerCount,
    required this.output,
    required this.maxCurrent,
    required this.category,
    required this.chargingFee,
    required this.parkingFee,
    required this.contact,
    required this.reservation,
    required this.manufacturer,
    required this.auth,
    required this.notes,
    required this.imageUrl,
    required this.affiliateUrl,
  });
}

class EvHotelApp extends StatelessWidget {
  const EvHotelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EV Hotels Japan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  
  Set<Marker> _hotelMarkers = {}; 
  Marker? _userMarker;

  List<Hotel> _allHotels = [];
  List<Hotel> _filteredHotels = [];
  List<Hotel> _searchResults = [];
  
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _selectedFilter = 'すべて';
  String _statusMessage = "v11.0 Size 30 & Blue for Location Only";

  // カスタムアイコン保存用
  BitmapDescriptor? _iconTesla;
  BitmapDescriptor? _iconRapid;
  BitmapDescriptor? _iconNormal;
  BitmapDescriptor? _iconOther;
  BitmapDescriptor? _iconMyLocation;

  static const CameraPosition _kTokyoStation = CameraPosition(
    target: LatLng(35.681236, 139.767125),
    zoom: 8.0,
  );

  @override
  void initState() {
    super.initState();
    _generateCustomIcons();
    _loadCsvData();
    _determinePosition(silent: true);
  }

  // ★アイコン作成（色設定）
  Future<void> _generateCustomIcons() async {
    // ホテル用（青は絶対に使わない）
    _iconTesla = await _createMarkerBitmap(Colors.redAccent);   // 赤
    _iconRapid = await _createMarkerBitmap(Colors.orange);      // オレンジ
    _iconNormal = await _createMarkerBitmap(Colors.yellow);     // 黄色（普通充電）
    _iconOther = await _createMarkerBitmap(Colors.purple);      // 紫
    
    // 自分用（ここだけ青！）
    _iconMyLocation = await _createMarkerBitmap(Colors.blueAccent);
    
    setState(() {}); 
  }

  // ★サイズ設定：30.0 に変更
  Future<BitmapDescriptor> _createMarkerBitmap(Color color) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    
    // ★サイズ修正：30.0
    const double size = 30.0; 

    final Paint paint = Paint()..color = color;
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0 // 枠線の太さをサイズに合わせて調整
      ..style = PaintingStyle.stroke;

    // 白いフチ付きの丸を描く
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.2, paint);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2.2, borderPaint);

    final ui.Image image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  BitmapDescriptor _getIconForType(String evType) {
    final t = evType.replaceAll('　', ' ').trim().toLowerCase();
    
    if (t.contains('テスラ') || t.contains('tesla') || t.contains('supercharger')) {
      return _iconTesla ?? BitmapDescriptor.defaultMarker;
    }
    if (t.contains('急速') || t.contains('chademo') || t.contains('fast')) {
      return _iconRapid ?? BitmapDescriptor.defaultMarker;
    }
    if (t.contains('普通') || t.contains('200v') || t.contains('normal')) {
      return _iconNormal ?? BitmapDescriptor.defaultMarker;
    }
    return _iconOther ?? BitmapDescriptor.defaultMarker;
  }

  // 検索処理
  Future<void> _searchPlaceAndMove(String query) async {
    if (query.isEmpty) return;
    if (googleMapsApiKey == 'YOUR_API_KEY') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('APIキーを設定してください')));
      return;
    }
    setState(() { _statusMessage = "検索中..."; });

    final url = Uri.parse(
      'https://corsproxy.io/?' + 
      Uri.encodeComponent(
        'https://maps.googleapis.com/maps/api/place/findplacefromtext/json'
        '?input=$query'
        '&inputtype=textquery'
        '&fields=geometry'
        '&key=$googleMapsApiKey'
      )
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final location = data['candidates'][0]['geometry']['location'];
          final GoogleMapController controller = await _controller.future;
          controller.animateCamera(CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(location['lat'], location['lng']), zoom: 14.0),
          ));
          setState(() { _statusMessage = "移動しました"; });
        } else {
           _zoomToFitResults();
        }
      }
    } catch (e) {
      debugPrint("Search Error: $e");
    }
  }

  // 現在地取得
  Future<void> _determinePosition({bool silent = false}) async {
    if (!mounted && !silent) return;
    setState(() { _statusMessage = "現在地を取得中..."; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition();

      setState(() {
        _userMarker = Marker(
          markerId: const MarkerId("my_location"),
          position: LatLng(position.latitude, position.longitude),
          // 自分だけ青！
          icon: _iconMyLocation ?? BitmapDescriptor.defaultMarker,
          infoWindow: const InfoWindow(title: "現在地"),
          zIndex: 1000,
        );
        _statusMessage = "現在地を表示";
      });

      final GoogleMapController controller = await _controller.future;
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(position.latitude, position.longitude), zoom: 14.0),
      ));
    } catch (e) {
      debugPrint("Location Error: $e");
    }
  }

  // CSV読み込み
  Future<void> _loadCsvData() async {
    try {
      final rawData = await rootBundle.loadString('assets/ev_hotels.csv');
      List<List<dynamic>> listData = const CsvToListConverter().convert(rawData);
      if (listData.isEmpty) return;

      var header = listData[0].map((e) => e.toString().trim().toLowerCase()).toList();
      int findIdx(List<String> keys) {
        for (var key in keys) {
          var idx = header.indexWhere((h) => h == key);
          if (idx != -1) return idx;
        }
        return -1;
      }

      var nameIdx = findIdx(['hotel_name', 'name', '施設名']);
      var addrIdx = findIdx(['address', '住所']);
      var latIdx = findIdx(['latitude', 'lat', '緯度']);
      var lngIdx = findIdx(['longitude', 'lng', '経度']);
      var priceIdx = findIdx(['price_range', 'price', '価格']);
      var siteIdx = findIdx(['関連サイト', 'site_url']);
      var evTypeIdx = findIdx(['charger_type', 'ev_type', '充電器タイプ']);
      var countIdx = findIdx(['charger_count', '台数']);
      var outputIdx = findIdx(['出力', 'output']);
      var maxCurIdx = findIdx(['最大電流値', 'max_current']);
      var catIdx = findIdx(['種別', 'category']);
      var feeIdx = findIdx(['充電課金', 'charging_fee']);
      var parkIdx = findIdx(['駐車料金', 'parking_fee']);
      var contactIdx = findIdx(['連絡・申込', 'contact']);
      var resIdx = findIdx(['事前予約', 'reservation']);
      var makerIdx = findIdx(['メーカー', 'manufacturer']);
      var authIdx = findIdx(['認証', 'auth']);
      var noteIdx = findIdx(['備考', 'notes']);
      var imgIdx = findIdx(['image_url', 'image']);
      var affIdx = findIdx(['affiliate_url', 'affiliate']);

      if (latIdx == -1) latIdx = 3;
      if (lngIdx == -1) lngIdx = 4;
      if (nameIdx == -1) nameIdx = 1;

      List<Hotel> loadedHotels = [];
      
      for (var i = 1; i < listData.length; i++) {
        try {
          var row = listData[i];
          if (row.length <= lngIdx) continue;
          String getStr(int idx) => (idx != -1 && row.length > idx) ? row[idx].toString().trim() : "";
          double lat = 0.0;
          double lng = 0.0;
          try {
             lat = double.parse(getStr(latIdx));
             lng = double.parse(getStr(lngIdx));
          } catch(e) { continue; }

          if (lat == 0.0 || lng == 0.0) continue;

          loadedHotels.add(Hotel(
            name: getStr(nameIdx),
            address: getStr(addrIdx),
            lat: lat,
            lng: lng,
            price: getStr(priceIdx),
            siteUrl: getStr(siteIdx),
            evType: getStr(evTypeIdx),
            chargerCount: getStr(countIdx),
            output: getStr(outputIdx),
            maxCurrent: getStr(maxCurIdx),
            category: getStr(catIdx),
            chargingFee: getStr(feeIdx),
            parkingFee: getStr(parkIdx),
            contact: getStr(contactIdx),
            reservation: getStr(resIdx),
            manufacturer: getStr(makerIdx),
            auth: getStr(authIdx),
            notes: getStr(noteIdx),
            imageUrl: getStr(imgIdx),
            affiliateUrl: getStr(affIdx),
          ));
        } catch (e) {}
      }

      setState(() {
        _allHotels = loadedHotels;
        _applyFilter();
      });

    } catch (e) {
      debugPrint("CSV Load Error: $e");
    }
  }

  void _applyFilter() {
    setState(() {
      if (_selectedFilter == 'すべて') {
        _filteredHotels = _allHotels;
      } else {
        _filteredHotels = _allHotels.where((hotel) {
          final target = "${hotel.evType} ${hotel.output} ${hotel.category}";
          return target.contains(_selectedFilter);
        }).toList();
      }
      _createMarkers();
    });
  }

  void _createMarkers() {
    setState(() {
      _hotelMarkers = _filteredHotels.map((hotel) {
        return Marker(
          markerId: MarkerId(hotel.name),
          position: LatLng(hotel.lat, hotel.lng),
          icon: _getIconForType(hotel.evType),
          onTap: () => _showHotelDetails(hotel),
        );
      }).toSet();
    });
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() { _isSearching = false; _searchResults = []; });
      return;
    }
    setState(() {
      _isSearching = true;
      final lowerQuery = query.toLowerCase();
      _searchResults = _filteredHotels.where((hotel) {
        final content = "${hotel.name} ${hotel.address} ${hotel.evType} ${hotel.notes} ${hotel.contact} ${hotel.category} ${hotel.manufacturer}".toLowerCase();
        return content.contains(lowerQuery);
      }).toList();
    });
  }

  Future<void> _handleSearchSubmit(String query) async {
    if (_searchResults.isNotEmpty && _searchResults.length < 5) {
      _zoomToFitResults();
      return;
    }
    await _searchPlaceAndMove(query);
  }

  Future<void> _goToHotel(Hotel hotel) async {
    final GoogleMapController controller = await _controller.future;
    FocusScope.of(context).unfocus();
    setState(() { _isSearching = false; _searchController.clear(); });
    controller.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: LatLng(hotel.lat, hotel.lng), zoom: 15),
    ));
    if (mounted) {
      _showHotelDetails(hotel);
    }
  }

  Future<void> _zoomToFitResults() async {
    if (_searchResults.isEmpty) return;
    final GoogleMapController controller = await _controller.future;

    if (_searchResults.length == 1) {
      controller.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(_searchResults[0].lat, _searchResults[0].lng), zoom: 15),
      ));
      return;
    }

    double minLat = _searchResults[0].lat;
    double maxLat = _searchResults[0].lat;
    double minLng = _searchResults[0].lng;
    double maxLng = _searchResults[0].lng;

    for (var hotel in _searchResults) {
      if (hotel.lat < minLat) minLat = hotel.lat;
      if (hotel.lat > maxLat) maxLat = hotel.lat;
      if (hotel.lng < minLng) minLng = hotel.lng;
      if (hotel.lng > maxLng) maxLng = hotel.lng;
    }

    controller.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      50.0, 
    ));
  }

  void _showHotelDetails(Hotel hotel) {
    String proxyImageUrl(String url) {
      if (url.isEmpty || !url.startsWith('http')) return "";
      return "https://wsrv.nl/?url=${Uri.encodeComponent(url)}&w=600&output=webp";
    }

    Widget infoRow(String label, String value, {bool isLink = false, VoidCallback? onTap}) {
      if (value.isEmpty || value == "nan") return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold))),
            Expanded(child: GestureDetector(onTap: isLink ? onTap : null, child: Text(value, style: TextStyle(fontSize: 14, color: isLink ? Colors.blue : Colors.black87, decoration: isLink ? TextDecoration.underline : null)))),
          ],
        ),
      );
    }
    Widget sectionTitle(String title) {
      return Padding(padding: const EdgeInsets.only(top: 16, bottom: 8), child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)));
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.all(16),
          child: PointerInterceptor(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      child: hotel.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: proxyImageUrl(hotel.imageUrl),
                              height: 200, width: double.infinity, fit: BoxFit.cover,
                              placeholder: (context, url) => Container(height: 200, color: Colors.grey[200]),
                              errorWidget: (context, url, error) => Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.hotel, color: Colors.grey)),
                            )
                          : Container(height: 200, color: Colors.grey[300], child: const Icon(Icons.hotel, color: Colors.grey)),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircleAvatar(backgroundColor: Colors.white, radius: 20, child: IconButton(icon: const Icon(Icons.close, color: Colors.black), onPressed: () => Navigator.of(context).pop())),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(hotel.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(hotel.address, style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity, height: 45,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            icon: const Icon(Icons.directions_car), label: const Text("Googleマップでルート案内", style: TextStyle(fontWeight: FontWeight.bold)),
                            onPressed: () async {
                              final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=${hotel.lat},${hotel.lng}");
                              if (await canLaunchUrl(url)) { await launchUrl(url, mode: LaunchMode.externalApplication); }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (hotel.price.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)), child: Text("目安: ${hotel.price}", style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold))),
                        if (hotel.siteUrl.isNotEmpty && hotel.siteUrl != "nan") Padding(padding: const EdgeInsets.only(top: 8.0), child: InkWell(onTap: () async { final Uri url = Uri.parse(hotel.siteUrl); if (await canLaunchUrl(url)) await launchUrl(url); }, child: const Row(children: [Icon(Icons.link, color: Colors.blue, size: 18), Text(" ホテル公式サイト / 関連ページ", style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline))]))),
                        const Divider(height: 30),
                        sectionTitle("⚡ EV充電スペック"), infoRow("タイプ", hotel.evType), infoRow("出力", hotel.output), infoRow("台数", hotel.chargerCount), infoRow("種別", hotel.category), infoRow("最大電流", hotel.maxCurrent), infoRow("メーカー", hotel.manufacturer),
                        sectionTitle("🅿️ 利用・料金"), infoRow("充電課金", hotel.chargingFee), infoRow("駐車料金", hotel.parkingFee), infoRow("認証", hotel.auth), infoRow("事前予約", hotel.reservation), infoRow("連絡・申込", hotel.contact),
                        if (hotel.notes.isNotEmpty && hotel.notes != "nan") ...[sectionTitle("📝 備考"), Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), child: Text(hotel.notes, style: const TextStyle(fontSize: 13, height: 1.4)))],
                    ]),
                  ),
                ),
                if (hotel.affiliateUrl.isNotEmpty && hotel.affiliateUrl != "nan") Padding(padding: const EdgeInsets.all(16.0), child: SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, elevation: 5, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), onPressed: () async { final Uri url = Uri.parse(hotel.affiliateUrl); if (await canLaunchUrl(url)) { await launchUrl(url); } }, child: const Text("楽天トラベルで空室確認", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {
          setState(() {
            _selectedFilter = isSelected ? 'すべて' : label;
            _applyFilter();
          });
        },
        backgroundColor: Colors.white,
        selectedColor: Colors.blue[100],
        checkmarkColor: Colors.blue[800],
        labelStyle: TextStyle(
          color: isSelected ? Colors.blue[900] : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? Colors.blue : Colors.grey.shade300),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _kTokyoStation,
            markers: _hotelMarkers.union(_userMarker != null ? {_userMarker!} : {}),
            myLocationEnabled: true, 
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (GoogleMapController controller) {
              _controller.complete(controller);
            },
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    child: TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) {
                         _handleSearchSubmit(value);
                      },
                      decoration: const InputDecoration(
                        hintText: "場所（新宿駅）、ホテル名、充電タイプ",
                        prefixIcon: Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildFilterChip('すべて'),
                      _buildFilterChip('急速'),
                      _buildFilterChip('普通'),
                      _buildFilterChip('6kW'),
                      _buildFilterChip('テスラ'),
                    ],
                  ),
                ),
                if (_isSearching && _searchResults.isNotEmpty)
                  PointerInterceptor(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                      ),
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final hotel = _searchResults[index];
                          return ListTile(
                            title: Text(hotel.name),
                            subtitle: Text(hotel.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _goToHotel(hotel),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            bottom: 30,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white70,
                  child: Text(_statusMessage, style: const TextStyle(fontSize: 10)),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  backgroundColor: Colors.blue,
                  child: const Icon(Icons.my_location, color: Colors.white),
                  onPressed: () {
                    _determinePosition();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}