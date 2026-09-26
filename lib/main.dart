import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yanami',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF366CB6)), useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

// ==================== 主界面 ====================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final GlobalKey<AnimeRecordPageState> _recordKey = GlobalKey();
  final GlobalKey<ProfilePageState> _profileKey = GlobalKey();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [const HomePage(), AnimeRecordPage(key: _recordKey), ProfilePage(key: _profileKey)];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yanami'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: _currentIndex == 1
            ? [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.sort),
                  tooltip: '排序方式',
                  onSelected: (value) {
                    if (value == 'start') _recordKey.currentState?.sortByStartTime();
                    else if (value == 'end') _recordKey.currentState?.sortByEndTime();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'start', child: Text('按开始时间排序')),
                    const PopupMenuItem(value: 'end', child: Text('按结束时间排序')),
                  ],
                ),
              ]
            : null,
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
          if (index == 2) {
            _profileKey.currentState?.loadHeatmapData();
            _profileKey.currentState?.loadProfileData();
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: '记录'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: '个人界面'),
        ],
      ),
    );
  }
}

// ==================== 通用：Bangumi 搜索（支持类型切换） ====================
Future<List<Map<String, dynamic>>> searchBangumi(String keyword, {int type = 2}) async {
  try {
    final response = await http.post(
      Uri.parse('https://bgmapi.anibt.net/v0/search/subjects?limit=20'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'NGng127/YanamiApp/1.0 (https://github.com/NGng127)',
      },
      body: jsonEncode({
        'keyword': keyword,
        'filter': {'type': [type]},
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final List<dynamic> list = data['data'] ?? [];
      return list.map<Map<String, dynamic>>((item) {
        String name = (item['name_cn']?.toString().isNotEmpty == true) ? item['name_cn'].toString() : (item['name'] ?? '未知');
        String original = item['name'] ?? '';
        String img = item['images']?['large'] ?? item['images']?['common'] ?? '';
        if (img.isNotEmpty) {
          img = img.replaceAll('lain.bgm.tv', 'bgmimg.anibt.net');
          img = img.replaceAll('http://', 'https://');
        }
        double score = (item['rating']?['score'] ?? 0).toDouble();
        String summary = item['summary'] ?? '';
        String date = item['date'] ?? '';
        int rank = item['rank'] ?? 0;
        return {'title': name, 'original': original, 'cover': img, 'description': summary, 'date': date, 'score': score, 'rank': rank};
      }).toList();
    }
  } catch (e) {
    debugPrint('Bangumi 搜索失败: $e');
  }
  return [];
}

// ==================== 页面一：首页 ====================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _animeList = [];
  bool _isLoading = false;
  String? _errorMessage;
  int _selectedYear = DateTime.now().year;
  int _selectedQuarter = _getCurrentQuarter(DateTime.now().month);

  static int _getCurrentQuarter(int month) {
    if (month <= 3) return 1;
    if (month <= 6) return 4;
    if (month <= 9) return 7;
    return 10;
  }

  String _getSeasonName(int quarter) {
    switch (quarter) {
      case 1: return '冬季';
      case 4: return '春季';
      case 7: return '夏季';
      case 10: return '秋季';
      default: return '';
    }
  }

  String _getDataFileUrl() {
    final monthStr = _selectedQuarter.toString().padLeft(2, '0');
    return 'https://acgntaiwan.github.io/Anime-List/anime-data/anime$_selectedYear.$monthStr.json';
  }

  Future<void> _fetchRecommendations() async {
    setState(() { _isLoading = true; _errorMessage = null; _animeList = []; });
    try {
      final response = await http.get(Uri.parse(_getDataFileUrl()), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          _animeList = data.map<Map<String, dynamic>>((item) => {
            'title': item['name'] ?? '未知',
            'cover': item['img'] ?? '',
            'description': item['description'] ?? '暂无简介',
            'premiereDate': item['date'] ?? '',
            'studio': item['originalName'] ?? item['nameInJpn'] ?? '',
            'genre': item['carrier'] ?? '',
          }).toList();
          _isLoading = false;
        });
      } else {
        setState(() { _isLoading = false; _errorMessage = '这个季度暂时没有数据 (${response.statusCode})'; });
      }
    } on TimeoutException {
      setState(() { _isLoading = false; _errorMessage = '网络超时，请重试'; });
    } catch (e) {
      setState(() { _isLoading = false; _errorMessage = '网络错误：$e'; });
    }
  }

  void _showYearQuarterPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSheet) => Container(
          padding: const EdgeInsets.all(16),
          height: 480,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择年份和季度', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: 10,
                  itemBuilder: (context, index) {
                    int year = DateTime.now().year + 1 - index;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$year 年', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 6),
                          Row(children: [
                            _buildQuarterButton(year, 1, '冬季', setStateSheet),
                            _buildQuarterButton(year, 4, '春季', setStateSheet),
                            _buildQuarterButton(year, 7, '夏季', setStateSheet),
                            _buildQuarterButton(year, 10, '秋季', setStateSheet),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuarterButton(int year, int quarter, String name, StateSetter setStateSheet) {
    bool isSelected = (_selectedYear == year && _selectedQuarter == quarter);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ElevatedButton(
          onPressed: () {
            setState(() { _selectedYear = year; _selectedQuarter = quarter; _animeList = []; _errorMessage = null; });
            setStateSheet(() {});
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? const Color(0xFF366CB6) : Colors.grey[200],
            foregroundColor: isSelected ? Colors.white : Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 8),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(name, style: const TextStyle(fontSize: 13)),
        ),
      ),
    );
  }

  void _changeQuarter(bool isNext) {
    setState(() {
      if (isNext) {
        if (_selectedQuarter == 10) { _selectedQuarter = 1; _selectedYear++; }
        else { _selectedQuarter += 3; }
      } else {
        if (_selectedQuarter == 1) { _selectedQuarter = 10; _selectedYear--; }
        else { _selectedQuarter -= 3; }
      }
      _animeList = [];
      _errorMessage = null;
    });
  }

  void _showSearchDialog() {
    final TextEditingController searchCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool isSearching = false;
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSearch) {
          Future<void> doSearch() async {
            if (searchCtrl.text.trim().isEmpty) return;
            setStateSearch(() { isSearching = true; error = null; results = []; });
            final r = await searchBangumi(searchCtrl.text.trim(), type: 2);
            setStateSearch(() { results = r; isSearching = false; });
            if (r.isEmpty) setStateSearch(() { error = '没找到相关番剧，试试别的关键词'; });
          }

          return AlertDialog(
            title: const Text('搜索番剧评分'),
            content: SizedBox(
              width: double.maxFinite,
              height: 500,
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: searchCtrl, autofocus: true, decoration: const InputDecoration(hintText: '输入番剧名字', border: OutlineInputBorder()), onSubmitted: (_) => doSearch())),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: isSearching ? null : doSearch, child: isSearching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('搜索')),
                ]),
                const SizedBox(height: 12),
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                Expanded(
                  child: results.isEmpty
                      ? Center(child: Text(isSearching ? '搜索中...' : '输入名字后点搜索', style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center))
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final item = results[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: item['cover'].toString().isNotEmpty
                                    ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(item['cover'], width: 45, height: 60, fit: BoxFit.cover, headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => const Icon(Icons.image, size: 30, color: Colors.grey)))
                                    : const Icon(Icons.image, size: 30, color: Colors.grey),
                                title: Text(item['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${item['date']}   ★ ${item['score']}', style: const TextStyle(fontSize: 12)),
                                onTap: () { Navigator.pop(context); _showSearchDetail(item); },
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
          );
        },
      ),
    );
  }

  void _showSearchDetail(Map<String, dynamic> anime) {
    String coverUrl = anime['cover']?.toString() ?? '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: coverUrl.isNotEmpty
                      ? Image.network(coverUrl, width: 120, height: 170, fit: BoxFit.cover, headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => Container(width: 120, height: 170, color: Colors.grey[200], child: const Icon(Icons.image, size: 50, color: Colors.grey)))
                      : Container(width: 120, height: 170, color: Colors.grey[200], child: const Icon(Icons.image, size: 50, color: Colors.grey)),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(anime['title'] ?? '未知', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if ((anime['original'] ?? '').toString().isNotEmpty) Text(anime['original'], style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if ((anime['date'] ?? '').toString().isNotEmpty) _buildTag(anime['date'], const Color(0xFF366CB6)),
                    if ((anime['score'] ?? 0) > 0) _buildTag('★ ${anime['score']}', Colors.amber[800]!),
                    if ((anime['rank'] ?? 0) > 0) _buildTag('排名 #${anime['rank']}', Colors.purple[700]!),
                  ]),
                ])),
              ]),
              const SizedBox(height: 24),
              const Text('简介', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(anime['description'] ?? '暂无简介', style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87)),
            ]),
          ),
        ),
      ),
    );
  }

  String _resolveCoverUrl(String raw) {
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('/')) return 'https://acgntaiwan.github.io/Anime-List$raw';
    return 'https://acgntaiwan.github.io/Anime-List/$raw';
  }

  void _showAnimeDetail(Map<String, dynamic> anime) {
    String coverUrl = _resolveCoverUrl(anime['cover']?.toString() ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: coverUrl.isNotEmpty
                      ? Image.network(coverUrl, width: 120, height: 170, fit: BoxFit.cover, headers: {'Referer': 'https://acgntaiwan.github.io/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => Container(width: 120, height: 170, color: Colors.grey[200], child: const Icon(Icons.image, size: 50, color: Colors.grey)))
                      : Container(width: 120, height: 170, color: Colors.grey[200], child: const Icon(Icons.image, size: 50, color: Colors.grey)),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(anime['title'] ?? '未知', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if ((anime['premiereDate'] ?? '').toString().isNotEmpty) _buildTag(anime['premiereDate'], const Color(0xFF366CB6)),
                    if ((anime['studio'] ?? '').toString().isNotEmpty) _buildTag(anime['studio'], Colors.grey[700]!),
                    if ((anime['genre'] ?? '').toString().isNotEmpty) _buildTag(anime['genre'], Colors.orange[800]!),
                  ]),
                ])),
              ]),
              const SizedBox(height: 24),
              const Text('简介', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(anime['description'] ?? '暂无简介', style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.black87)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: _showSearchDialog,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 6)]),
            child: Row(children: [
              Icon(Icons.search, color: Colors.grey[500]),
              const SizedBox(width: 8),
              Text('搜索番剧查看 Bangumi 评分', style: TextStyle(color: Colors.grey[500], fontSize: 14)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: InkWell(
              onTap: _showYearQuarterPicker,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Flexible(child: Text('$_selectedYear年${_getSeasonName(_selectedQuarter)}新番', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_drop_down, size: 28, color: Colors.grey),
                ]),
              ),
            ),
          ),
          Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back_ios, size: 18), onPressed: () => _changeQuarter(false), tooltip: '上一季'),
            const Icon(Icons.local_fire_department, color: Colors.orange, size: 28),
            IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 18), onPressed: () => _changeQuarter(true), tooltip: '下一季'),
          ]),
        ]),
        const SizedBox(height: 4),
        Text(_animeList.isEmpty ? '点击标题选年份季度，或直接点按钮获取' : '共 ${_animeList.length} 部作品', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _fetchRecommendations,
            icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh),
            label: Text(_isLoading ? '加载中...' : '获取本季新番推荐'),
          ),
        ),
        const SizedBox(height: 16),
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
            child: Row(children: [const Icon(Icons.error_outline, color: Colors.red), const SizedBox(width: 8), Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))]),
          ),
        if (_animeList.isEmpty && !_isLoading && _errorMessage == null)
          const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 60), child: Column(children: [Icon(Icons.auto_awesome, size: 60, color: Colors.grey), SizedBox(height: 16), Text('点击标题选年份季度，再点按钮获取', style: TextStyle(color: Colors.grey))]))),
        ..._animeList.map((anime) => _buildAnimeCard(anime)).toList(),
      ]),
    );
  }

  Widget _buildAnimeCard(Map<String, dynamic> anime) {
    String coverUrl = _resolveCoverUrl(anime['cover']?.toString() ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showAnimeDetail(anime),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 70, height: 95,
              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
              child: coverUrl.isNotEmpty
                  ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(coverUrl, fit: BoxFit.cover, headers: {'Referer': 'https://acgntaiwan.github.io/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => const Icon(Icons.image, size: 35, color: Colors.grey)))
                  : const Icon(Icons.image, size: 35, color: Colors.grey),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(anime['title'] ?? '未知', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 2, children: [
                if ((anime['premiereDate'] ?? '').toString().isNotEmpty) _buildTag(anime['premiereDate'], const Color(0xFF366CB6)),
                if ((anime['studio'] ?? '').toString().isNotEmpty) _buildTag(anime['studio'], Colors.grey[700]!),
              ]),
              const SizedBox(height: 4),
              Text(anime['description'] ?? '暂无简介', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ]),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }
}

// ==================== 页面二：追番记录 ====================
class AnimeRecordPage extends StatefulWidget {
  const AnimeRecordPage({super.key});
  @override
  State<AnimeRecordPage> createState() => AnimeRecordPageState();
}

class AnimeRecordPageState extends State<AnimeRecordPage> {
  List<Map<String, dynamic>> _animeList = [];
  late SharedPreferences _prefs;

  String _searchKeyword = '';
  String _categoryFilter = '全部';

  int _coverSizeIndex = 0;
  final List<double> _coverWidths = [50.0, 80.0, 120.0];
  final List<double> _coverHeights = [70.0, 115.0, 170.0];
  final List<String> _sizeNames = ['小图', '中图', '大图'];
  final List<IconData> _sizeIcons = [Icons.photo_size_select_small, Icons.photo_size_select_large, Icons.photo_size_select_actual];

  int _filterMode = 0;
  final List<String> _filterNames = ['显示全部', '仅看未看完', '仅看已看完'];
  final List<IconData> _filterIcons = [Icons.filter_list, Icons.radio_button_unchecked, Icons.check_circle];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _prefs = await SharedPreferences.getInstance();
    String? jsonString = _prefs.getString('animeList');
    if (jsonString != null) {
      List<dynamic> decoded = jsonDecode(jsonString);
      setState(() {
        _animeList = decoded.map((e) {
          Map<String, dynamic> map = Map<String, dynamic>.from(e);
          map['sessions'] ??= [];
          map['isFinished'] ??= false;
          map['category'] ??= '番剧';
          map['volumes'] ??= [];
          return map;
        }).toList();
      });
    } else {
      setState(() {
        _animeList = [
          {
            'title': '长按可以删除',
            'subtitle': '0集 00:00:00',
            'cover': '',
            'isFinished': false,
            'category': '番剧',
            'volumes': [],
            'sessions': [{'start': '2008-11-29', 'end': '2008-11-29'}],
          },
        ];
      });
    }
  }

  Future<void> _saveData() async {
    await _prefs.setString('animeList', jsonEncode(_animeList));
  }

  void sortByStartTime() {
    setState(() {
      _animeList.sort((a, b) {
        List sA = a['sessions'] ?? [], sB = b['sessions'] ?? [];
        String tA = sA.isNotEmpty ? (sA.first['start'] ?? '') : '';
        String tB = sB.isNotEmpty ? (sB.first['start'] ?? '') : '';
        if (tA.isEmpty && tB.isEmpty) return 0;
        if (tA.isEmpty) return 1;
        if (tB.isEmpty) return -1;
        return (DateTime.tryParse(tA) ?? DateTime(1900)).compareTo(DateTime.tryParse(tB) ?? DateTime(1900));
      });
    });
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已按开始时间排序'), duration: Duration(milliseconds: 800)));
  }

  void sortByEndTime() {
    setState(() {
      _animeList.sort((a, b) {
        List sA = a['sessions'] ?? [], sB = b['sessions'] ?? [];
        String tA = sA.isNotEmpty ? (sA.last['end'] ?? '') : '';
        String tB = sB.isNotEmpty ? (sB.last['end'] ?? '') : '';
        if (tA.isEmpty && tB.isEmpty) return 0;
        if (tA.isEmpty) return 1;
        if (tB.isEmpty) return -1;
        return (DateTime.tryParse(tB) ?? DateTime(1900)).compareTo(DateTime.tryParse(tA) ?? DateTime(1900));
      });
    });
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已按结束时间排序'), duration: Duration(milliseconds: 800)));
  }

  Future<void> _showAnimeSearchDialog({
    required TextEditingController titleController,
    required TextEditingController coverController,
    required TextEditingController descController,
    required StateSetter setStateDialog,
    required String category,
  }) async {
    final TextEditingController searchCtrl = TextEditingController(text: titleController.text);
    List<Map<String, dynamic>> results = [];
    bool isSearching = false;
    String? searchError;
    final int searchType = category == '番剧' ? 2 : 1;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateSearch) {
          Future<void> doSearch() async {
            if (searchCtrl.text.trim().isEmpty) return;
            setStateSearch(() { isSearching = true; searchError = null; results = []; });
            final r = await searchBangumi(searchCtrl.text.trim(), type: searchType);
            setStateSearch(() { results = r; isSearching = false; });
            if (r.isEmpty) setStateSearch(() { searchError = '没找到相关内容'; });
          }

          return AlertDialog(
            title: Text('搜索$category'),
            content: SizedBox(
              width: double.maxFinite, height: 450,
              child: Column(children: [
                Row(children: [
                  Expanded(child: TextField(controller: searchCtrl, decoration: const InputDecoration(hintText: '输入名字', border: OutlineInputBorder()), onSubmitted: (_) => doSearch())),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: isSearching ? null : doSearch, child: isSearching ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('搜索')),
                ]),
                const SizedBox(height: 12),
                if (searchError != null) Text(searchError!, style: const TextStyle(color: Colors.red)),
                Expanded(
                  child: results.isEmpty
                      ? Center(child: Text(isSearching ? '搜索中...' : '输入名字后点搜索', style: const TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final item = results[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: item['cover'].toString().isNotEmpty
                                    ? ClipRRect(borderRadius: BorderRadius.circular(4), child: Image.network(item['cover'], width: 45, height: 60, fit: BoxFit.cover, headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => const Icon(Icons.image, size: 30, color: Colors.grey)))
                                    : const Icon(Icons.image, size: 30, color: Colors.grey),
                                title: Text(item['title'], maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${item['date']}   ★ ${item['score']}', style: const TextStyle(fontSize: 12)),
                                onTap: () {
                                  setStateDialog(() {
                                    titleController.text = item['title'];
                                    if (item['cover'].toString().isNotEmpty) coverController.text = item['cover'];
                                    if (item['description'].toString().isNotEmpty) descController.text = item['description'];
                                  });
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入《${item['title']}》'), duration: const Duration(milliseconds: 800)));
                                },
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
          );
        },
      ),
    );
  }

  Future<String?> _showAnimeProgressPicker(BuildContext context, String currentProgress) async {
    int episode = 0, hour = 0, minute = 0, second = 0;
    final epMatch = RegExp(r'(\d+)\s*集').firstMatch(currentProgress);
    if (epMatch != null) episode = int.tryParse(epMatch.group(1)!) ?? 0;
    final timeMatch = RegExp(r'(\d+):(\d+):(\d+)').firstMatch(currentProgress);
    if (timeMatch != null) {
      hour = int.tryParse(timeMatch.group(1)!) ?? 0;
      minute = int.tryParse(timeMatch.group(2)!) ?? 0;
      second = int.tryParse(timeMatch.group(3)!) ?? 0;
    }
    final epCtrl = TextEditingController(text: episode > 0 ? episode.toString() : '');
    final hCtrl = TextEditingController(text: hour.toString().padLeft(2, '0'));
    final mCtrl = TextEditingController(text: minute.toString().padLeft(2, '0'));
    final sCtrl = TextEditingController(text: second.toString().padLeft(2, '0'));
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置观看进度'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: epCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '集数', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            const Text('集', style: TextStyle(fontSize: 16)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(controller: hCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '时', border: OutlineInputBorder()))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 20))),
            Expanded(child: TextField(controller: mCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '分', border: OutlineInputBorder()))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text(':', style: TextStyle(fontSize: 20))),
            Expanded(child: TextField(controller: sCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '秒', border: OutlineInputBorder()))),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () {
            final ep = epCtrl.text.trim();
            final h = (int.tryParse(hCtrl.text.trim()) ?? 0).toString().padLeft(2, '0');
            final m = (int.tryParse(mCtrl.text.trim()) ?? 0).toString().padLeft(2, '0');
            final s = (int.tryParse(sCtrl.text.trim()) ?? 0).toString().padLeft(2, '0');
            Navigator.pop(context, '${ep.isNotEmpty ? ep : "0"}集 $h:$m:$s');
          }, child: const Text('确定')),
        ],
      ),
    );
  }

  Future<String?> _showNovelProgressPicker(BuildContext context, String currentProgress) async {
    String volume = '';
    String chapter = '';
    final volMatch = RegExp(r'第\s*([\d一二三四五六七八九十百.]+)\s*卷').firstMatch(currentProgress);
    if (volMatch != null) volume = volMatch.group(1) ?? '';
    final chapMatch = RegExp(r'第\s*([\d一二三四五六七八九十百.]+)\s*话').firstMatch(currentProgress);
    if (chapMatch != null) chapter = chapMatch.group(1) ?? '';

    final volCtrl = TextEditingController(text: volume);
    final chapCtrl = TextEditingController(text: chapter);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设置阅读进度'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: TextField(controller: volCtrl, decoration: const InputDecoration(labelText: '卷 (可留空)', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            const Text('卷', style: TextStyle(fontSize: 16)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextField(controller: chapCtrl, decoration: const InputDecoration(labelText: '话', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            const Text('话', style: TextStyle(fontSize: 16)),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () {
            final v = volCtrl.text.trim();
            final c = chapCtrl.text.trim();
            final parts = <String>[];
            if (v.isNotEmpty) parts.add('第$v卷');
            if (c.isNotEmpty) parts.add('第$c话');
            Navigator.pop(context, parts.isEmpty ? '未开始' : parts.join(' '));
          }, child: const Text('确定')),
        ],
      ),
    );
  }

  // 分册管理：支持自定义卷名 + 每卷独立封面
  Future<void> _showVolumeManager({
    required List<Map<String, dynamic>> volumes,
    required StateSetter setStateDialog,
  }) async {
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateVol) {
          return AlertDialog(
            title: const Text('分册管理'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(children: [
                Expanded(
                  child: volumes.isEmpty
                      ? const Center(child: Text('还没有分册，点击下方添加', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: volumes.length,
                          itemBuilder: (context, i) {
                            final v = volumes[i];
                            final cover = v['cover']?.toString() ?? '';
                            return ListTile(
                              leading: cover.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: cover.startsWith('http')
                                          ? Image.network(cover, width: 36, height: 48, fit: BoxFit.cover,
                                              headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'},
                                              errorBuilder: (c, e, s) => const Icon(Icons.menu_book, size: 30, color: Colors.grey))
                                          : Image.file(File(cover), width: 36, height: 48, fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) => const Icon(Icons.menu_book, size: 30, color: Colors.grey)),
                                    )
                                  : const Icon(Icons.menu_book, size: 30, color: Colors.grey),
                              title: Text((v['name'] ?? '').toString().isEmpty ? '未命名' : v['name']),
                              subtitle: Text('进度：${(v['progress'] ?? '').toString().isEmpty ? "未开始" : v['progress']}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle, color: Colors.red),
                                onPressed: () => setStateVol(() => volumes.removeAt(i)),
                              ),
                              onTap: () => _editVolume(volumes, i, setStateVol),
                            );
                          },
                        ),
                ),
                TextButton.icon(
                  onPressed: () {
                    volumes.add({'name': '', 'progress': '', 'cover': ''});
                    setStateVol(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('添加分册'),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('完成')),
            ],
          );
        },
      ),
    );
    setStateDialog(() {});
  }

  // 编辑单卷：卷名随意填（支持 SS1、99.9 等），可单独选封面
  void _editVolume(List<Map<String, dynamic>> volumes, int index, StateSetter setStateVol) {
    final nameCtrl = TextEditingController(text: volumes[index]['name'] ?? '');
    final progressCtrl = TextEditingController(text: volumes[index]['progress'] ?? '');
    String coverCtrl = volumes[index]['cover']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateVolDialog) {
          return AlertDialog(
            title: const Text('编辑分册'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '卷名',
                    hintText: '如 第一卷 / SS1 / 99.9 / 外传',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: progressCtrl,
                  decoration: const InputDecoration(
                    labelText: '进度',
                    hintText: '如 第8话 / 读完 / 未开始',
                  ),
                ),
                const SizedBox(height: 16),
                if (coverCtrl.isNotEmpty)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: coverCtrl.startsWith('http')
                          ? Image.network(coverCtrl, width: 80, height: 110, fit: BoxFit.cover,
                              headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'},
                              errorBuilder: (c, e, s) => const Icon(Icons.menu_book, size: 40, color: Colors.grey))
                          : Image.file(File(coverCtrl), width: 80, height: 110, fit: BoxFit.cover,
                              errorBuilder: (c, e, s) => const Icon(Icons.menu_book, size: 40, color: Colors.grey)),
                    ),
                  ),
                const SizedBox(height: 8),
                Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton.icon(
                      onPressed: () async {
                        final ImagePicker picker = ImagePicker();
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image != null) {
                          setStateVolDialog(() => coverCtrl = image.path);
                        }
                      },
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('从相册选封面'),
                    ),
                    if (coverCtrl.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, color: Colors.red),
                        tooltip: '移除封面',
                        onPressed: () => setStateVolDialog(() => coverCtrl = ''),
                      ),
                  ]),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              TextButton(onPressed: () {
                volumes[index]['name'] = nameCtrl.text.trim();
                volumes[index]['progress'] = progressCtrl.text.trim();
                volumes[index]['cover'] = coverCtrl;
                setStateVol(() {});
                Navigator.pop(context);
              }, child: const Text('保存')),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDatePickerField({required BuildContext context, required String label, required TextEditingController controller, required StateSetter setStateDialog}) {
    return Expanded(
      child: InkWell(
        onTap: () async {
          DateTime initialDate = DateTime.now();
          if (controller.text.isNotEmpty) { try { initialDate = DateTime.parse(controller.text); } catch (_) {} }
          final DateTime? picked = await showDatePicker(context: context, initialDate: initialDate, firstDate: DateTime(1900), lastDate: DateTime.now().add(const Duration(days: 365)));
          if (picked != null) {
            setStateDialog(() { controller.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}'; });
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), suffixIcon: const Icon(Icons.calendar_today, size: 18)),
          child: Text(controller.text.isEmpty ? '请选择日期' : controller.text, style: TextStyle(color: controller.text.isEmpty ? Colors.grey : Colors.black, fontSize: 15)),
        ),
      ),
    );
  }

  Widget _buildCategorySelector(String current, ValueChanged<String> onChanged) {
    return Wrap(
      spacing: 8,
      children: ['番剧', '小说', '漫画'].map((cat) {
        return ChoiceChip(
          label: Text(cat),
          selected: current == cat,
          onSelected: (_) => onChanged(cat),
          selectedColor: const Color(0xFF366CB6),
          labelStyle: TextStyle(color: current == cat ? Colors.white : Colors.black87),
        );
      }).toList(),
    );
  }

  void _addAnime() {
    final TextEditingController titleController = TextEditingController();
    final TextEditingController subtitleController = TextEditingController(text: '0集 00:00:00');
    final TextEditingController coverController = TextEditingController();
    final TextEditingController descController = TextEditingController();
    bool isFinished = false;
    String category = '番剧';
    List<Map<String, dynamic>> volumes = [];
    List<Map<String, TextEditingController>> sessions = [{'start': TextEditingController(), 'end': TextEditingController()}];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('添加'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('分类：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                _buildCategorySelector(category, (val) {
                  setStateDialog(() {
                    category = val;
                    if (val == '番剧') subtitleController.text = '0集 00:00:00';
                    else subtitleController.text = '未开始';
                  });
                }),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: titleController, decoration: const InputDecoration(labelText: '名字', hintText: '例如：海贼王'))),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFF366CB6)),
                    tooltip: '搜索',
                    onPressed: () {
                      _showAnimeSearchDialog(
                        titleController: titleController,
                        coverController: coverController,
                        descController: descController,
                        setStateDialog: setStateDialog,
                        category: category,
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                if (category == '番剧')
                  InkWell(
                    onTap: () async {
                      final result = await _showAnimeProgressPicker(context, subtitleController.text);
                      if (result != null) { subtitleController.text = result; setStateDialog(() {}); }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: '当前进度', border: OutlineInputBorder(), suffixIcon: Icon(Icons.edit)),
                      child: Text(subtitleController.text, style: const TextStyle(fontSize: 16)),
                    ),
                  )
                else ...[
                  Row(children: [
                    Expanded(child: Text('分册：${volumes.length} 卷', style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                      onPressed: () => _showVolumeManager(volumes: volumes, setStateDialog: setStateDialog),
                      icon: const Icon(Icons.menu_book, size: 18),
                      label: const Text('管理分册'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final result = await _showNovelProgressPicker(context, subtitleController.text);
                      if (result != null) { subtitleController.text = result; setStateDialog(() {}); }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: '总进度', border: OutlineInputBorder(), suffixIcon: Icon(Icons.edit)),
                      child: Text(subtitleController.text, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(children: [const Text('标记为已看完: '), Switch(value: isFinished, onChanged: (val) => setStateDialog(() => isFinished = val))]),
                const SizedBox(height: 8),
                if (coverController.text.isNotEmpty)
                  Center(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(coverController.text, width: 80, height: 110, fit: BoxFit.cover, headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => const Icon(Icons.image, size: 40, color: Colors.grey)))),
                if (descController.text.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(descController.text, style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 3, overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 8),
                Center(child: TextButton.icon(onPressed: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) { setStateDialog(() { coverController.text = image.path; }); }
                }, icon: const Icon(Icons.photo_library), label: const Text('从相册选择封面'))),
                const Divider(),
                const Text('观看时间记录 (可多段):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...sessions.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var controllers = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(children: [
                      _buildDatePickerField(context: context, label: '开始日期', controller: controllers['start']!, setStateDialog: setStateDialog),
                      const SizedBox(width: 8),
                      _buildDatePickerField(context: context, label: '结束日期', controller: controllers['end']!, setStateDialog: setStateDialog),
                      IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () { setStateDialog(() { sessions.removeAt(idx); }); }),
                    ]),
                  );
                }).toList(),
                TextButton.icon(onPressed: () { setStateDialog(() { sessions.add({'start': TextEditingController(), 'end': TextEditingController()}); }); }, icon: const Icon(Icons.add), label: const Text('添加观看记录')),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              TextButton(onPressed: () {
                if (titleController.text.isNotEmpty) {
                  List<Map<String, String>> sessionData = [];
                  for (var ctrl in sessions) {
                    if (ctrl['start']!.text.isNotEmpty || ctrl['end']!.text.isNotEmpty) {
                      sessionData.add({'start': ctrl['start']!.text.trim(), 'end': ctrl['end']!.text.trim()});
                    }
                  }
                  setState(() {
                    _animeList.add({
                      'title': titleController.text,
                      'subtitle': subtitleController.text,
                      'cover': coverController.text,
                      'description': descController.text,
                      'isFinished': isFinished,
                      'category': category,
                      'volumes': volumes,
                      'sessions': sessionData,
                    });
                  });
                  _saveData();
                }
                Navigator.pop(context);
              }, child: const Text('添加')),
            ],
          );
        },
      ),
    );
  }

  void _editAnime(int index) {
    final titleController = TextEditingController(text: _animeList[index]['title']);
    final subtitleController = TextEditingController(text: _animeList[index]['subtitle']);
    final coverController = TextEditingController(text: _animeList[index]['cover'] ?? '');
    final descController = TextEditingController(text: _animeList[index]['description'] ?? '');
    bool isFinished = _animeList[index]['isFinished'] ?? false;
    String category = _animeList[index]['category'] ?? '番剧';
    List<Map<String, dynamic>> volumes = (_animeList[index]['volumes'] ?? []).map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e)).toList();

    List<dynamic> existingSessions = _animeList[index]['sessions'] ?? [];
    List<Map<String, TextEditingController>> sessions = existingSessions.map((e) => {'start': TextEditingController(text: e['start'] ?? ''), 'end': TextEditingController(text: e['end'] ?? '')}).toList();
    if (sessions.isEmpty) sessions.add({'start': TextEditingController(), 'end': TextEditingController()});

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('编辑'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('分类：', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                _buildCategorySelector(category, (val) => setStateDialog(() => category = val)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: titleController, decoration: const InputDecoration(labelText: '名字'))),
                  const SizedBox(width: 8),
                  IconButton(icon: const Icon(Icons.search, color: Color(0xFF366CB6)), onPressed: () {
                    _showAnimeSearchDialog(
                      titleController: titleController,
                      coverController: coverController,
                      descController: descController,
                      setStateDialog: setStateDialog,
                      category: category,
                    );
                  }),
                ]),
                const SizedBox(height: 12),
                if (category == '番剧')
                  InkWell(
                    onTap: () async {
                      final result = await _showAnimeProgressPicker(context, subtitleController.text);
                      if (result != null) { subtitleController.text = result; setStateDialog(() {}); }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: '当前进度', border: OutlineInputBorder(), suffixIcon: Icon(Icons.edit)),
                      child: Text(subtitleController.text, style: const TextStyle(fontSize: 16)),
                    ),
                  )
                else ...[
                  Row(children: [
                    Expanded(child: Text('分册：${volumes.length} 卷', style: const TextStyle(fontSize: 14))),
                    TextButton.icon(
                      onPressed: () => _showVolumeManager(volumes: volumes, setStateDialog: setStateDialog),
                      icon: const Icon(Icons.menu_book, size: 18),
                      label: const Text('管理分册'),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final result = await _showNovelProgressPicker(context, subtitleController.text);
                      if (result != null) { subtitleController.text = result; setStateDialog(() {}); }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: '总进度', border: OutlineInputBorder(), suffixIcon: Icon(Icons.edit)),
                      child: Text(subtitleController.text, style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(children: [const Text('标记为已看完: '), Switch(value: isFinished, onChanged: (val) => setStateDialog(() => isFinished = val))]),
                const SizedBox(height: 8),
                if (coverController.text.isNotEmpty)
                  Center(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: coverController.text.startsWith('http') ? Image.network(coverController.text, width: 80, height: 110, fit: BoxFit.cover, headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => const Icon(Icons.image, size: 40, color: Colors.grey)) : Image.file(File(coverController.text), width: 80, height: 110, fit: BoxFit.cover))),
                if (descController.text.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(descController.text, style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 3, overflow: TextOverflow.ellipsis)),
                Center(child: TextButton.icon(onPressed: () async {
                  final ImagePicker picker = ImagePicker();
                  final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                  if (image != null) { setStateDialog(() { coverController.text = image.path; }); }
                }, icon: const Icon(Icons.photo_library), label: const Text('更换封面'))),
                const Divider(),
                const Text('观看时间记录 (可多段):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...sessions.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var controllers = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(children: [
                      _buildDatePickerField(context: context, label: '开始日期', controller: controllers['start']!, setStateDialog: setStateDialog),
                      const SizedBox(width: 8),
                      _buildDatePickerField(context: context, label: '结束日期', controller: controllers['end']!, setStateDialog: setStateDialog),
                      IconButton(icon: const Icon(Icons.remove_circle, color: Colors.red), onPressed: () { setStateDialog(() { sessions.removeAt(idx); }); }),
                    ]),
                  );
                }).toList(),
                TextButton.icon(onPressed: () { setStateDialog(() { sessions.add({'start': TextEditingController(), 'end': TextEditingController()}); }); }, icon: const Icon(Icons.add), label: const Text('添加观看记录')),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              TextButton(onPressed: () {
                if (titleController.text.isNotEmpty) {
                  List<Map<String, String>> sessionData = [];
                  for (var ctrl in sessions) {
                    if (ctrl['start']!.text.isNotEmpty || ctrl['end']!.text.isNotEmpty) {
                      sessionData.add({'start': ctrl['start']!.text.trim(), 'end': ctrl['end']!.text.trim()});
                    }
                  }
                  setState(() {
                    _animeList[index]['title'] = titleController.text;
                    _animeList[index]['subtitle'] = subtitleController.text;
                    _animeList[index]['cover'] = coverController.text;
                    _animeList[index]['description'] = descController.text;
                    _animeList[index]['isFinished'] = isFinished;
                    _animeList[index]['category'] = category;
                    _animeList[index]['volumes'] = volumes;
                    _animeList[index]['sessions'] = sessionData;
                  });
                  _saveData();
                }
                Navigator.pop(context);
              }, child: const Text('保存')),
            ],
          );
        },
      ),
    );
  }

  void _deleteAnime(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定要删除《${_animeList[index]['title']}》吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () { setState(() => _animeList.removeAt(index)); _saveData(); Navigator.pop(context); }, child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> displayList = _animeList.where((anime) {
      if (_categoryFilter != '全部' && anime['category'] != _categoryFilter) return false;
      if (_searchKeyword.isNotEmpty) {
        String title = anime['title'].toString().toLowerCase();
        String subtitle = anime['subtitle'].toString().toLowerCase();
        if (!title.contains(_searchKeyword.toLowerCase()) && !subtitle.contains(_searchKeyword.toLowerCase())) return false;
      }
      if (_filterMode == 1) return anime['isFinished'] != true;
      if (_filterMode == 2) return anime['isFinished'] == true;
      return true;
    }).toList();

    return Scaffold(
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.only(top: 190, bottom: 150),
            itemCount: displayList.length,
            itemBuilder: (context, index) {
              final anime = displayList[index];
              final originalIndex = _animeList.indexOf(anime);
              String coverUrl = anime['cover'] ?? '';
              List<dynamic> volumes = anime['volumes'] ?? [];
              List<dynamic> sessions = anime['sessions'] ?? [];
              String sessionSummary = '';
              if (sessions.isNotEmpty) {
                sessionSummary = '观看记录 (${sessions.length} 段): ';
                for (var s in sessions) {
                  sessionSummary += '${s['start']}~${s['end']}  ';
                }
              }

              return InkWell(
                onTap: () => _editAnime(originalIndex),
                onLongPress: () => _deleteAnime(originalIndex),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: _coverWidths[_coverSizeIndex],
                      height: _coverHeights[_coverSizeIndex],
                      child: coverUrl.isNotEmpty
                          ? ClipRRect(borderRadius: BorderRadius.circular(8), child: coverUrl.startsWith('http') ? Image.network(coverUrl, fit: BoxFit.cover, headers: {'Referer': 'https://bgm.tv/', 'User-Agent': 'Mozilla/5.0'}, errorBuilder: (c, e, s) => const Icon(Icons.star, color: Colors.orange)) : Image.file(File(coverUrl), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.star, color: Colors.orange)))
                          : Container(decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.star, color: Colors.orange)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 4),
                      Row(children: [
                        if (anime['category'] != null && anime['category'] != '番剧')
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: Colors.purple.withAlpha(30), borderRadius: BorderRadius.circular(4)),
                            child: Text(anime['category'], style: TextStyle(fontSize: 10, color: Colors.purple[700], fontWeight: FontWeight.bold)),
                          ),
                        Expanded(child: Text(anime['title'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                      if (anime['isFinished'] == true) ...[
                        const SizedBox(height: 8),
                        Row(children: [Icon(Icons.check_circle, size: 16, color: Colors.green[600]), const SizedBox(width: 4), Text('已看完', style: TextStyle(fontSize: 14, color: Colors.green[600]))]),
                      ] else ...[
                        const SizedBox(height: 8),
                        Text(anime['subtitle'], style: TextStyle(fontSize: 15, color: Colors.grey[600])),
                      ],
                      if (volumes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text('共 ${volumes.length} 卷', style: TextStyle(fontSize: 12, color: Colors.purple[400])),
                      ],
                      if (sessionSummary.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(sessionSummary, style: TextStyle(fontSize: 12, color: Colors.blue[400])),
                      ],
                    ])),
                    Checkbox(
                      value: anime['isFinished'] ?? false,
                      onChanged: (val) { setState(() => _animeList[originalIndex]['isFinished'] = val); _saveData(); },
                    ),
                  ]),
                ),
              );
            },
          ),
          Positioned(
            top: 16, left: 16, right: 16,
            child: Column(children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: ['全部', '番剧', '小说', '漫画'].map((cat) {
                  bool selected = _categoryFilter == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: selected,
                      onSelected: (_) => setState(() => _categoryFilter = cat),
                      selectedColor: const Color(0xFF366CB6),
                      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
                    ),
                  );
                }).toList()),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => setState(() => _searchKeyword = value),
                decoration: InputDecoration(
                  hintText: '搜索番剧名字或进度',
                  prefixIcon: const Icon(Icons.search),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Card(
                  elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), color: Colors.white,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() => _coverSizeIndex = (_coverSizeIndex + 1) % 3);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已切换为：${_sizeNames[_coverSizeIndex]}'), duration: const Duration(milliseconds: 800), behavior: SnackBarBehavior.floating, width: 150));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_sizeIcons[_coverSizeIndex], color: const Color(0xFF366CB6)),
                        const SizedBox(width: 6),
                        Text(_sizeNames[_coverSizeIndex], style: const TextStyle(color: Color(0xFF366CB6), fontWeight: FontWeight.bold)),
                      ]),
                    ),
                  ),
                ),
                FloatingActionButton.small(
                  heroTag: 'filterBtn', backgroundColor: Colors.white, foregroundColor: const Color(0xFF366CB6), elevation: 4,
                  onPressed: () {
                    setState(() => _filterMode = (_filterMode + 1) % 3);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('筛选：${_filterNames[_filterMode]}'), duration: const Duration(milliseconds: 800), behavior: SnackBarBehavior.floating, width: 180));
                  },
                  child: Icon(_filterIcons[_filterMode]),
                ),
              ]),
            ]),
          ),
        ],
      ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'historyBtn', backgroundColor: Colors.blueGrey, foregroundColor: Colors.white,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryPage())).then((_) {}),
          child: const Icon(Icons.history),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(heroTag: 'addBtn', onPressed: _addAnime, child: const Icon(Icons.add)),
      ]),
    );
  }
}

// ==================== 页面三：个人界面 ====================
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => ProfilePageState();
}

class ProfilePageState extends State<ProfilePage> {
  final ScrollController _heatmapScrollController = ScrollController();
  Map<String, int> _dailyMinutes = {};
  List<Map<String, dynamic>> _dailyLogs = [];
  bool _isLoading = true;

  String _profileName = '昵称';
  String _profileSignature = '签名';
  String _avatarPath = '';

  @override
  void initState() {
    super.initState();
    loadHeatmapData();
    loadProfileData();
  }

  @override
  void dispose() {
    _heatmapScrollController.dispose();
    super.dispose();
  }

  Future<void> loadProfileData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _profileName = prefs.getString('profile_name') ?? '昵称';
      _profileSignature = prefs.getString('profile_signature') ?? '签名';
      _avatarPath = prefs.getString('profile_avatar') ?? '';
    });
  }

  Future<void> _saveProfile() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_name', _profileName);
    await prefs.setString('profile_signature', _profileSignature);
    await prefs.setString('profile_avatar', _avatarPath);
  }

  Future<void> _pickAvatar() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _avatarPath = image.path);
      _saveProfile();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('头像已更新'), duration: Duration(milliseconds: 800)));
    }
  }

  void _editText(String key, String title) {
    final TextEditingController controller = TextEditingController(text: key == 'profile_name' ? _profileName : _profileSignature);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, decoration: InputDecoration(hintText: key == 'profile_name' ? '输入新名字' : '输入新签名')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () {
            if (controller.text.isNotEmpty) {
              setState(() {
                if (key == 'profile_name') _profileName = controller.text.trim();
                else _profileSignature = controller.text.trim();
              });
              _saveProfile();
            }
            Navigator.pop(context);
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  Future<void> loadHeatmapData() async {
    setState(() => _isLoading = true);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('dailyLogs');
    Map<String, int> minutesMap = {};
    List<Map<String, dynamic>> rawLogs = [];
    if (jsonString != null) {
      List<dynamic> decoded = jsonDecode(jsonString);
      for (var log in decoded) {
        Map<String, dynamic> map = Map<String, dynamic>.from(log);
        rawLogs.add(map);
        String date = map['date'];
        int duration = map['duration'] ?? 0;
        minutesMap[date] = (minutesMap[date] ?? 0) + duration;
      }
    }
    setState(() { _dailyLogs = rawLogs; _dailyMinutes = minutesMap; _isLoading = false; });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_heatmapScrollController.hasClients) _heatmapScrollController.jumpTo(_heatmapScrollController.position.maxScrollExtent);
    });
  }

  void _showDateDetails(String dateStr) {
    final dayLogs = _dailyLogs.where((log) => log['date'] == dateStr).toList();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('日期：$dateStr'),
        content: SizedBox(
          width: double.maxFinite,
          child: dayLogs.isEmpty
              ? const Text('这一天没有观看记录')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: dayLogs.length,
                  itemBuilder: (context, index) {
                    final log = dayLogs[index];
                    return ListTile(title: Text(log['title']), trailing: Text('${log['duration']} 分钟', style: const TextStyle(fontWeight: FontWeight.bold)));
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Column(children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 40, backgroundColor: const Color(0xFFD0E2F5),
                backgroundImage: _avatarPath.isNotEmpty ? FileImage(File(_avatarPath)) : null,
                child: _avatarPath.isEmpty ? const Icon(Icons.person, size: 50, color: Color(0xFF366CB6)) : null,
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _editText('profile_name', '修改名字'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_profileName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 16, color: Colors.grey),
              ]),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _editText('profile_signature', '修改签名'),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_profileSignature, style: const TextStyle(color: Colors.grey)),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 14, color: Colors.grey),
              ]),
            ),
            const SizedBox(height: 12),
            const Text('github.com/NGng127\n新番列表:https://acgntaiwan.github.io/Anime-List', style: TextStyle(color: Colors.grey, fontSize: 13), textAlign: TextAlign.center),
          ])),
          const SizedBox(height: 30),
          const Text('观看记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _isLoading ? const Center(child: CircularProgressIndicator()) : _buildHeatmap(),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            const Text('少', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 4),
            _buildLegendBox(Colors.grey[200]!),
            _buildLegendBox(const Color.fromARGB(255, 150, 224, 229)),
            _buildLegendBox(const Color.fromARGB(255, 111, 187, 201)),
            _buildLegendBox(const Color.fromARGB(255, 35, 108, 154)),
            _buildLegendBox(const Color.fromARGB(255, 12, 34, 74)),
            const SizedBox(width: 4),
            const Text('多', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildLegendBox(Color color) {
    return Container(width: 12, height: 12, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)));
  }

  Widget _buildHeatmap() {
    const double cellSize = 22.0;
    final now = DateTime.now();
    DateTime earliest = now.subtract(const Duration(days: 364));
    if (_dailyMinutes.isNotEmpty) {
      final dates = _dailyMinutes.keys.map((e) => DateTime.parse(e)).toList();
      dates.sort();
      if (dates.first.isBefore(earliest)) earliest = dates.first;
    }
    final startDate = earliest.subtract(Duration(days: earliest.weekday - 1));
    final totalDays = now.difference(startDate).inDays + 1;
    final totalWeeks = (totalDays / 7).ceil();

    return SingleChildScrollView(
      controller: _heatmapScrollController,
      scrollDirection: Axis.horizontal,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          const SizedBox(height: 40),
          ...['一', '二', '三', '四', '五', '六', '日'].map((day) => SizedBox(height: cellSize, child: Text(day, style: const TextStyle(fontSize: 10, color: Colors.grey)))),
        ]),
        const SizedBox(width: 4),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: totalWeeks * cellSize,
            height: 14,
            child: Stack(
              clipBehavior: Clip.none,
              children: List.generate(totalWeeks, (weekIndex) {
                final weekDate = startDate.add(Duration(days: weekIndex * 7));
                bool showYear = weekIndex == 0;
                if (weekIndex > 0) {
                  final prevWeekDate = startDate.add(Duration(days: (weekIndex - 1) * 7));
                  if (weekDate.year != prevWeekDate.year) showYear = true;
                }
                if (!showYear) return const SizedBox.shrink();
                return Positioned(
                  left: weekIndex * cellSize,
                  top: 0,
                  child: Text('${weekDate.year}', style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: List.generate(totalWeeks, (weekIndex) {
            final weekDate = startDate.add(Duration(days: weekIndex * 7));
            if (weekDate.day <= 7) {
              return SizedBox(width: cellSize, child: Text('${weekDate.month}月', style: const TextStyle(fontSize: 9, color: Colors.grey), softWrap: false, overflow: TextOverflow.clip));
            }
            return const SizedBox(width: cellSize);
          })),
          const SizedBox(height: 4),
          Row(children: List.generate(totalWeeks, (weekIndex) {
            return Column(children: List.generate(7, (dayIndex) {
              final cellDate = startDate.add(Duration(days: weekIndex * 7 + dayIndex));
              final dateStr = _formatDate(cellDate);
              final minutes = _dailyMinutes[dateStr] ?? 0;
              if (cellDate.isAfter(now)) {
                return Container(width: 20, height: 20, margin: const EdgeInsets.all(1), decoration: BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.circular(3)));
              }
              return GestureDetector(
                onTap: () => _showDateDetails(dateStr),
                child: Container(width: 20, height: 20, margin: const EdgeInsets.all(1), decoration: BoxDecoration(color: _getColorForMinutes(minutes), borderRadius: BorderRadius.circular(3))),
              );
            }));
          })),
        ]),
      ]),
    );
  }

  Color _getColorForMinutes(int minutes) {
    if (minutes == 0) return Colors.grey[200]!;
    if (minutes <= 30) return const Color(0xFF96E0E5);
    if (minutes <= 60) return const Color(0xFF6FBBC9);
    if (minutes <= 90) return const Color(0xFF236C9A);
    return const Color(0xFF0C224A);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

// ==================== 页面四：历史记录 ====================
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _dailyLogs = [];
  late SharedPreferences _prefs;
  DateTime _selectedDate = DateTime.now();
  DateTime? _filterDate;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    _prefs = await SharedPreferences.getInstance();
    String? jsonString = _prefs.getString('dailyLogs');
    if (jsonString != null) {
      setState(() {
        _dailyLogs = List<Map<String, dynamic>>.from(jsonDecode(jsonString));
        _dailyLogs.sort((a, b) => b['date'].compareTo(a['date']));
      });
    }
  }

  Future<void> _saveLogs() async {
    await _prefs.setString('dailyLogs', jsonEncode(_dailyLogs));
  }

  List<String> get _allTitles => _dailyLogs.map((l) => l['title'].toString()).toSet().toList();

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null && picked != _selectedDate) setState(() => _selectedDate = picked);
  }

  Future<void> _pickFilterDate() async {
    final DateTime? picked = await showDatePicker(context: context, initialDate: _filterDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
    if (picked != null) setState(() => _filterDate = picked);
  }

  void _clearFilter() => setState(() => _filterDate = null);

  void _addLog() {
    if (_titleController.text.isEmpty || _durationController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写番剧名和时长')));
      return;
    }
    final duration = int.tryParse(_durationController.text);
    if (duration == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('时长必须是数字')));
      return;
    }
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    setState(() {
      _dailyLogs.add({'date': dateStr, 'title': _titleController.text.trim(), 'duration': duration});
      _dailyLogs.sort((a, b) => b['date'].compareTo(a['date']));
    });
    _saveLogs();
    _titleController.clear();
    _durationController.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('记录已添加')));
  }

  void _editLog(int index) {
    final log = _dailyLogs[index];
    final titleCtrl = TextEditingController(text: log['title']);
    final durationCtrl = TextEditingController(text: log['duration'].toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改记录'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '番剧名')),
          const SizedBox(height: 12),
          TextField(controller: durationCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '时长(分)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () {
            final newDuration = int.tryParse(durationCtrl.text);
            if (titleCtrl.text.isNotEmpty && newDuration != null) {
              setState(() {
                _dailyLogs[index]['title'] = titleCtrl.text.trim();
                _dailyLogs[index]['duration'] = newDuration;
              });
              _saveLogs();
            }
            Navigator.pop(context);
          }, child: const Text('保存')),
        ],
      ),
    );
  }

  void _deleteLog(int index) {
    setState(() => _dailyLogs.removeAt(index));
    _saveLogs();
  }

  @override
  Widget build(BuildContext context) {
    List<Map<String, dynamic>> displayLogs = _dailyLogs;
    if (_filterDate != null) {
      String filterStr = '${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}';
      displayLogs = _dailyLogs.where((log) => log['date'] == filterStr).toList();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('每日观看历史')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(children: [
            Row(children: [
              const Text('筛选日期: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              InkWell(
                onTap: _pickFilterDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Text(_filterDate == null ? '全部' : '${_filterDate!.year}-${_filterDate!.month.toString().padLeft(2, '0')}-${_filterDate!.day.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 15)),
                ),
              ),
              if (_filterDate != null) ...[
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.clear, color: Colors.red), onPressed: _clearFilter, tooltip: '清除筛选'),
              ],
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const Text('添加记录 - 日期: ', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              InkWell(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: Text('${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 15)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                flex: 2,
                child: Autocomplete<String>(
                  optionsBuilder: (TextEditingValue tv) {
                    if (tv.text.isEmpty) return const Iterable<String>.empty();
                    return _allTitles.where((t) => t.toLowerCase().contains(tv.text.toLowerCase()));
                  },
                  onSelected: (sel) => _titleController.text = sel,
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    controller.text = _titleController.text;
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (v) => _titleController.text = v,
                      decoration: const InputDecoration(labelText: '番剧名', hintText: '如: 轻音少女'),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(flex: 1, child: TextField(controller: _durationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '时长(分)', hintText: '如: 30'))),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _addLog, icon: const Icon(Icons.save), label: const Text('保存记录'))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: displayLogs.isEmpty
              ? const Center(child: Text('暂无符合条件的记录', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: displayLogs.length,
                  itemBuilder: (context, index) {
                    final log = displayLogs[index];
                    final originalIndex = _dailyLogs.indexOf(log);
                    return ListTile(
                      leading: const Icon(Icons.check_circle_outline, color: Color(0xFF366CB6)),
                      title: Text(log['title']),
                      subtitle: Text('日期: ${log['date']}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${log['duration']} 分钟', style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.edit, color: Color(0xFF366CB6), size: 20), onPressed: () => _editLog(originalIndex)),
                        IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _deleteLog(originalIndex)),
                      ]),
                      onTap: () => _editLog(originalIndex),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}