import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hotpepper_service.dart';

// ─── テーマ定数 ────────────────────────────────────────────────
const _kBg      = Color(0xFF111827);
const _kSurface = Color(0xFF1F2937);
const _kOrange  = Color(0xFFFF6B35);
const _kGold    = Color(0xFFFFB347);
const _kText    = Color(0xFFF9FAFB);
const _kSub     = Color(0xFF9CA3AF);

// カードの配色（インデックスでサイクル）
const _kGradients = [
  [Color(0xFFFF6B35), Color(0xFFFF8E53)],
  [Color(0xFFEC4899), Color(0xFFBE185D)],
  [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
  [Color(0xFF0EA5E9), Color(0xFF0369A1)],
  [Color(0xFF10B981), Color(0xFF065F46)],
  [Color(0xFFF59E0B), Color(0xFFB45309)],
];

// ジャンル名に対応するMaterialアイコン（部分一致）
IconData _genreIcon(String genre) {
  if (genre.contains('居酒屋'))                                return Icons.sports_bar;
  if (genre.contains('ダイニングバー') || genre.contains('バル')) return Icons.wine_bar;
  if (genre.contains('バー') || genre.contains('カクテル'))     return Icons.local_bar;
  if (genre.contains('ラーメン'))                              return Icons.ramen_dining;
  if (genre.contains('そば') || genre.contains('うどん'))       return Icons.ramen_dining;
  if (genre.contains('寿司'))                                  return Icons.set_meal;
  if (genre.contains('魚介') || genre.contains('海鮮'))         return Icons.set_meal;
  if (genre.contains('焼肉') || genre.contains('ホルモン'))     return Icons.kebab_dining;
  if (genre.contains('ステーキ') || genre.contains('ハンバーグ')) return Icons.kebab_dining;
  if (genre.contains('焼き鳥') || genre.contains('串'))         return Icons.kebab_dining;
  if (genre.contains('お好み焼き') || genre.contains('もんじゃ')) return Icons.kebab_dining;
  if (genre.contains('ハンバーガー'))                           return Icons.lunch_dining;
  if (genre.contains('ピザ'))                                  return Icons.local_pizza;
  if (genre.contains('イタリアン'))                             return Icons.local_pizza;
  if (genre.contains('フレンチ') || genre.contains('洋食'))      return Icons.bakery_dining;
  if (genre.contains('カフェ'))                                return Icons.local_cafe;
  if (genre.contains('スイーツ') || genre.contains('ケーキ'))    return Icons.cake;
  if (genre.contains('カレー') || genre.contains('インド'))      return Icons.dinner_dining;
  if (genre.contains('中華'))                                  return Icons.dinner_dining;
  if (genre.contains('和食'))                                  return Icons.set_meal;
  if (genre.contains('アジア') || genre.contains('エスニック'))  return Icons.restaurant;
  if (genre.contains('創作') || genre.contains('クリエイティブ')) return Icons.restaurant;
  if (genre.contains('とんかつ') || genre.contains('揚げ物'))    return Icons.dinner_dining;
  return Icons.restaurant;
}

// 検索範囲ラベル（range値 1〜5 → 距離文字列）
const _kRangeLabels = ['300m', '500m', '1000m', '2000m', '3000m'];
String _rangeLabelFor(int range) => _kRangeLabels[(range - 1).clamp(0, 4)];

// 表示するカードの最大枚数（店舗数が多い順）
const _kMaxCards = 10;

// 予算選択肢（ラベル, HotpepperコードまたはNull=指定なし）
const _kBudgetOptions = [
  (label: '指定なし', code: null),
  (label: '〜¥1,500', code: 'B011'),
  (label: '〜¥3,000', code: 'B002'),
  (label: '〜¥5,000', code: 'B008'),
  (label: '〜¥10,000', code: 'B005'),
];

// 席タイプ選択肢（ラベル）— APIキーは HotpepperService.seatTypeParams から引く
const _kSeatOptions = ['個室', '座敷', 'テラス', '食べ放題', '飲み放題'];

// ─── エントリポイント ───────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: _kBg,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SLAEAT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _kBg,
        colorScheme: const ColorScheme.dark(
          primary: _kOrange,
          secondary: _kGold,
          surface: _kSurface,
          onPrimary: Colors.white,
          onSurface: _kText,
        ),
        useMaterial3: true,
        // アプリ全体のフォントを Poppins に統一
        textTheme: GoogleFonts.poppinsTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
      ),
      home: const SwipePage(),
    );
  }
}

// ─── スワイプ画面 ───────────────────────────────────────────────
class SwipePage extends StatefulWidget {
  const SwipePage({super.key});

  @override
  State<SwipePage> createState() => _SwipePageState();
}

class _SwipePageState extends State<SwipePage> {
  List<String> _genres = [];
  Map<String, List<Shop>> _shopsByGenre = {};
  String _timeLabel = '';
  final List<String> _liked = [];
  final CardSwiperController _controller = CardSwiperController();
  int _range = 3;
  MealTime? _mealTimeOverride;
  String? _budget;
  Set<String> _seatTypes = {};
  int _partySize = 1; // 1 = 指定なし
  bool _loading = true;
  String? _error;
  int _currentIndex = 0;
  bool _done = false;

  // late final でキャッシュ → 再ビルド時も同一オブジェクトが渡るため CardSwiper が内部リセットしない
  late final NullableCardBuilder _cardBuilder =
      (context, index, _, __) => _GenreCard(
            genre: _genres[index],
            gradient: _kGradients[index % _kGradients.length],
            shopCount: _shopsByGenre[_genres[index]]?.length ?? 0,
          );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _resultNavigated = false;
    _done = false;
    setState(() {
      _loading = true;
      _error = null;
      _liked.clear();
      _currentIndex = 0;
    });
    try {
      final position = await determinePosition();
      final result = await HotpepperService.fetchNearby(
        latitude: position.latitude,
        longitude: position.longitude,
        range: _range,
        mealOverride: _mealTimeOverride,
        budget: _budget,
        seatTypes: _seatTypes,
        partyCapacity: _partySize >= 2 ? _partySize : null,
      );
      if (!mounted) return;

      // 店舗数が多い順にソートして上位 _kMaxCards 件に絞る（重複排除）
      final seen = <String>{};
      final sorted = result.genres
          .where((g) => seen.add(g))
          .toList()
        ..sort((a, b) => (result.shopsByGenre[b]?.length ?? 0)
            .compareTo(result.shopsByGenre[a]?.length ?? 0));

      final genreList = sorted.take(_kMaxCards).toList();
      setState(() {
        _genres = genreList;
        _shopsByGenre = result.shopsByGenre;
        _timeLabel = result.timeLabel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SettingsSheet(
        initialRange: _range,
        initialMealOverride: _mealTimeOverride,
        initialBudget: _budget,
        initialSeatTypes: _seatTypes,
        initialPartySize: _partySize,
        onApply: (range, mealOverride, budget, seatTypes, partySize) {
          setState(() {
            _range = range;
            _mealTimeOverride = mealOverride;
            _budget = budget;
            _seatTypes = seatTypes;
            _partySize = partySize;
          });
          _load();
        },
      ),
    );
  }

  bool _onSwipe(int previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (_done || _resultNavigated) return false;
    // ライブラリの previousIndex はリセットバグで信頼不可 → 自前の _currentIndex を使う
    final actualIndex = _currentIndex;
    if (actualIndex >= _genres.length) return false;
    if (direction == CardSwiperDirection.right) {
      _liked.add(_genres[actualIndex]);
    }
    final isLast = actualIndex == _genres.length - 1;
    setState(() {
      _currentIndex = actualIndex + 1;
      if (isLast) _done = true;
    });
    if (isLast) _goToResult();
    return true;
  }

  bool _resultNavigated = false;

  void _goToResult() {
    if (_resultNavigated) return;
    _resultNavigated = true;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ResultPage(
        likedGenres: List<String>.from(_liked),
        shopsByGenre: _shopsByGenre,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'SLAEAT',
              style: GoogleFonts.montserrat(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _kText,
                letterSpacing: 3,
              ),
            ),
          ),
          if (_timeLabel.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kOrange.withAlpha(_mealTimeOverride != null ? 70 : 40),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _kOrange.withAlpha(_mealTimeOverride != null ? 200 : 100),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_mealTimeOverride != null) ...[
                    const Icon(Icons.edit, size: 10, color: _kOrange),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    _timeLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kOrange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.favorite_rounded, color: _kSub),
            tooltip: 'お気に入り',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: _kSub),
            tooltip: '検索設定',
            onPressed: _showSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading || _done) return _buildLoading();
    if (_error != null) {
      return _MessageView(icon: Icons.error_outline, message: _error!, onRetry: _load);
    }
    if (_genres.isEmpty) {
      return _MessageView(
        icon: Icons.search_off,
        message: '半径${_rangeLabelFor(_range)}以内にお店が見つかりませんでした\n設定から範囲を広げてみてください',
        onRetry: _load,
      );
    }
    return _buildSwipeUI();
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kOrange.withAlpha(25),
              shape: BoxShape.circle,
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(color: _kOrange, strokeWidth: 3),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '近くのお店を探しています…',
            style: TextStyle(fontSize: 15, color: _kSub),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeUI() {
    final remaining = _genres.length - _currentIndex;
    return Column(
      children: [
        // 進捗バー
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Row(
            children: [
              Text(
                '半径 ${_rangeLabelFor(_range)}',
                style: const TextStyle(fontSize: 13, color: _kSub),
              ),
              const Spacer(),
              Text(
                '残り $remaining 枚',
                style: const TextStyle(
                    fontSize: 13, color: _kOrange, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _genres.isEmpty ? 0 : _currentIndex / _genres.length,
              minHeight: 3,
              backgroundColor: _kSurface,
              valueColor: const AlwaysStoppedAnimation(_kOrange),
            ),
          ),
        ),
        // カード
        Expanded(
          child: CardSwiper(
            controller: _controller,
            cardsCount: _genres.length,
            onSwipe: _onSwipe,
            onEnd: _goToResult,
            isLoop: false,
            numberOfCardsDisplayed: 2,
            scale: 0.9,
            backCardOffset: const Offset(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            cardBuilder: _cardBuilder,
          ),
        ),
        // スワイプボタン
        Padding(
          padding: const EdgeInsets.fromLTRB(48, 0, 48, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SwipeButton(
                icon: Icons.close_rounded,
                label: 'ナシ',
                color: const Color(0xFF6B7280),
                onTap: () => _controller.swipe(CardSwiperDirection.left),
              ),
              _SwipeButton(
                icon: Icons.favorite_rounded,
                label: 'アリ',
                color: _kOrange,
                onTap: () => _controller.swipe(CardSwiperDirection.right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── スワイプボタン ────────────────────────────────────────────
class _SwipeButton extends StatelessWidget {
  const _SwipeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(100), width: 2),
            ),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ─── ジャンルカード ────────────────────────────────────────────
class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.genre,
    required this.gradient,
    required this.shopCount,
  });

  final String genre;
  final List<Color> gradient;
  final int shopCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient[0].withAlpha(100),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 背景の装飾円
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(18),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            left: -24,
            bottom: -24,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // コンテンツ（Positioned.fillで横幅をカード全体に広げてcenterが効くようにする）
          Positioned.fill(
            child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_genreIcon(genre), size: 52, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Text(
                  genre,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '近くに $shopCount 軒',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ), // Positioned.fill
        ],
      ),
    );
  }
}

// ─── エラー・空表示 ────────────────────────────────────────────
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                  color: _kSurface, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: _kSub),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(fontSize: 15, color: _kSub, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('再試行'),
              style: FilledButton.styleFrom(
                backgroundColor: _kOrange,
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 設定ボトムシート ──────────────────────────────────────────
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.initialRange,
    required this.initialMealOverride,
    required this.initialBudget,
    required this.initialSeatTypes,
    required this.initialPartySize,
    required this.onApply,
  });

  final int initialRange;
  final MealTime? initialMealOverride;
  final String? initialBudget;
  final Set<String> initialSeatTypes;
  final int initialPartySize;
  final void Function(
    int range,
    MealTime? mealOverride,
    String? budget,
    Set<String> seatTypes,
    int partySize,
  ) onApply;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late double _sliderVal;
  MealTime? _mealOverride;
  String? _budget;
  late Set<String> _seatTypes;
  late int _partySize;

  String get _distLabel => _kRangeLabels[_sliderVal.round()];
  int get _rangeVal => _sliderVal.round() + 1;

  @override
  void initState() {
    super.initState();
    _sliderVal = (widget.initialRange - 1).toDouble().clamp(0, 4);
    _mealOverride = widget.initialMealOverride;
    _budget = widget.initialBudget;
    _seatTypes = Set<String>.from(widget.initialSeatTypes);
    _partySize = widget.initialPartySize;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ハンドル
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _kSub.withAlpha(120),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('検索設定',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _kText)),
          const SizedBox(height: 24),

          // ── 検索範囲スライダー ──────────────────────
          Row(
            children: [
              const Text('検索範囲',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kText)),
              const Spacer(),
              Text(
                '半径 $_distLabel',
                style: const TextStyle(
                    fontSize: 15,
                    color: _kOrange,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _kOrange,
              inactiveTrackColor: _kBg,
              thumbColor: _kOrange,
              overlayColor: _kOrange.withAlpha(40),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              min: 0,
              max: 4,
              divisions: 4,
              value: _sliderVal,
              onChanged: (v) => setState(() => _sliderVal = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _kRangeLabels
                  .map((l) => Text(l,
                      style: const TextStyle(fontSize: 10, color: _kSub)))
                  .toList(),
            ),
          ),
          const SizedBox(height: 28),

          // ── 時間帯 ──────────────────────────────────
          const Text('時間帯',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kText)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MealChip(
                label: '自動',
                icon: Icons.access_time_rounded,
                selected: _mealOverride == null,
                onTap: () => setState(() => _mealOverride = null),
              ),
              _MealChip(
                label: '朝ごはん',
                icon: Icons.wb_sunny_rounded,
                selected: _mealOverride == MealTime.morning,
                onTap: () => setState(() => _mealOverride = MealTime.morning),
              ),
              _MealChip(
                label: 'ランチ',
                icon: Icons.light_mode_rounded,
                selected: _mealOverride == MealTime.lunch,
                onTap: () => setState(() => _mealOverride = MealTime.lunch),
              ),
              _MealChip(
                label: 'ディナー',
                icon: Icons.nights_stay_rounded,
                selected: _mealOverride == MealTime.dinner,
                onTap: () => setState(() => _mealOverride = MealTime.dinner),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── 予算 ─────────────────────────────────────
          const Text('予算（1人あたり）',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kText)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kBudgetOptions.map((opt) {
              final selected = _budget == opt.code;
              return GestureDetector(
                onTap: () => setState(() => _budget = opt.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? _kOrange : _kBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? _kOrange : _kSub.withAlpha(70),
                      width: selected ? 0 : 1,
                    ),
                  ),
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? Colors.white : _kSub,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // ── 席タイプ ──────────────────────────────────
          const Text('席タイプ',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kText)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kSeatOptions.map((seat) {
              final selected = _seatTypes.contains(seat);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) {
                    _seatTypes.remove(seat);
                  } else {
                    _seatTypes.add(seat);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: selected ? _kOrange : _kBg,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? _kOrange : _kSub.withAlpha(70),
                      width: selected ? 0 : 1,
                    ),
                  ),
                  child: Text(
                    seat,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? Colors.white : _kSub,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 28),

          // ── 人数 ──────────────────────────────────────
          Row(
            children: [
              const Text('人数',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _kText)),
              const Spacer(),
              _PartyStepper(
                value: _partySize,
                onChanged: (v) => setState(() => _partySize = v),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // ── 適用ボタン ────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onApply(_rangeVal, _mealOverride, _budget, Set<String>.from(_seatTypes), _partySize);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _kOrange,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('この設定で探す',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
        ), // Column
      ), // SingleChildScrollView
    ); // DraggableScrollableSheet
  }
}

// 人数ステッパー
class _PartyStepper extends StatelessWidget {
  const _PartyStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value == 1 ? '指定なし' : '$value 人',
          style: TextStyle(
            fontSize: 15,
            color: value == 1 ? _kSub : _kOrange,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 12),
        _StepBtn(
          icon: Icons.remove,
          onTap: value > 1 ? () => onChanged(value - 1) : null,
        ),
        const SizedBox(width: 8),
        _StepBtn(
          icon: Icons.add,
          onTap: value < 20 ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: enabled ? _kOrange.withAlpha(30) : _kBg,
          shape: BoxShape.circle,
          border: Border.all(
            color: enabled ? _kOrange : _kSub.withAlpha(50),
            width: 1,
          ),
        ),
        child: Icon(icon, size: 16, color: enabled ? _kOrange : _kSub.withAlpha(80)),
      ),
    );
  }
}

// 時間帯選択チップ
class _MealChip extends StatelessWidget {
  const _MealChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _kOrange : _kBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? _kOrange : _kSub.withAlpha(70),
            width: selected ? 0 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14,
                color: selected ? Colors.white : _kSub),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : _kSub,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 結果画面 ──────────────────────────────────────────────────
class ResultPage extends StatefulWidget {
  const ResultPage({
    super.key,
    required this.likedGenres,
    required this.shopsByGenre,
  });

  final List<String> likedGenres;
  final Map<String, List<Shop>> shopsByGenre;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage>
    with SingleTickerProviderStateMixin {
  late final String? _answer;
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  Map<String, Shop> _favorites = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _answer = widget.likedGenres.isEmpty
        ? null
        : widget.likedGenres[Random().nextInt(widget.likedGenres.length)];

    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('favorites_data') ?? [];
    final map = <String, Shop>{};
    for (final s in saved) {
      try {
        final shop = Shop.fromJson(json.decode(s) as Map<String, dynamic>);
        if (shop.url.isNotEmpty) map[shop.url] = shop;
      } catch (_) {}
    }
    if (mounted) setState(() => _favorites = map);
  }

  Future<void> _toggleFavorite(Shop shop) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favorites.containsKey(shop.url)) {
        _favorites.remove(shop.url);
      } else {
        _favorites[shop.url] = shop;
      }
    });
    await prefs.setStringList(
      'favorites_data',
      _favorites.values.map((s) => json.encode(s.toJson())).toList(),
    );
  }

  Future<void> _openShop(Shop shop) async {
    if (shop.url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(shop.url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('お店のページを開けませんでした')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: _answer == null ? _buildEmpty() : _buildResult(_answer),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF374151), Color(0xFF1F2937)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.sentiment_dissatisfied_rounded, size: 52, color: _kSub),
            ),
            const SizedBox(height: 24),
            const Text(
              'アリが1つもありませんでした',
              style: TextStyle(
                  fontSize: 20, color: _kText, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text('もう一度やり直してみましょう',
                style: TextStyle(fontSize: 14, color: _kSub)),
            const SizedBox(height: 48),
            _retryButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(String answer) {
    final shops = widget.shopsByGenre[answer] ?? [];
    final idx = widget.likedGenres.indexOf(answer);
    final gradient = _kGradients[(idx < 0 ? 0 : idx) % _kGradients.length];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 発表カード
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('今日のごはんはこれ！',
                  style: TextStyle(fontSize: 13, color: _kSub)),
              const SizedBox(height: 12),
              ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: gradient[0].withAlpha(100),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(40),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_genreIcon(answer), size: 38, color: Colors.white),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              answer,
                              style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '近くに ${shops.length} 軒あります',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // 店舗一覧ヘッダー
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text('近くのお店',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _kText)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${shops.length}件',
                    style: const TextStyle(
                        fontSize: 12,
                        color: _kOrange,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // 店舗リスト
        Expanded(
          child: shops.isEmpty
              ? const Center(
                  child: Text('近くのお店情報がありません',
                      style: TextStyle(color: _kSub)))
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: shops.length,
                  itemBuilder: (context, index) {
                    final shop = shops[index];
                    return _ShopCard(
                      shop: shop,
                      isFavorited: _favorites.containsKey(shop.url),
                      onFavoriteToggle: () => _toggleFavorite(shop),
                      onTap: () => _openShop(shop),
                    );
                  },
                ),
        ),
        // もう一度ボタン
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: _retryButton(),
        ),
      ],
    );
  }

  Widget _retryButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const SwipePage()),
          (route) => false,
        ),
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('もう一度やる', style: TextStyle(fontSize: 16)),
        style: FilledButton.styleFrom(
          backgroundColor: _kOrange,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}

// ─── お気に入りページ ─────────────────────────────────────────
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  Map<String, Shop> _favorites = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('favorites_data') ?? [];
    final map = <String, Shop>{};
    for (final s in saved) {
      try {
        final shop = Shop.fromJson(json.decode(s) as Map<String, dynamic>);
        if (shop.url.isNotEmpty) map[shop.url] = shop;
      } catch (_) {}
    }
    if (mounted) setState(() { _favorites = map; _loading = false; });
  }

  Future<void> _toggleFavorite(Shop shop) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favorites.containsKey(shop.url)) {
        _favorites.remove(shop.url);
      } else {
        _favorites[shop.url] = shop;
      }
    });
    await prefs.setStringList(
      'favorites_data',
      _favorites.values.map((s) => json.encode(s.toJson())).toList(),
    );
  }

  Future<void> _openShop(Shop shop) async {
    if (shop.url.isEmpty) return;
    final ok = await launchUrl(Uri.parse(shop.url),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('お店のページを開けませんでした')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final shops = _favorites.values.toList();
    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded, color: _kSub),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'お気に入り',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold, color: _kText),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // リスト
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _kOrange))
                  : shops.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: _kSurface,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: _kSub.withAlpha(60), width: 1.5),
                                ),
                                child: const Icon(Icons.favorite_border_rounded,
                                    size: 40, color: _kSub),
                              ),
                              const SizedBox(height: 16),
                              const Text('お気に入りがまだありません',
                                  style: TextStyle(color: _kSub, fontSize: 15)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          itemCount: shops.length,
                          itemBuilder: (context, index) {
                            final shop = shops[index];
                            return _ShopCard(
                              shop: shop,
                              isFavorited: true,
                              onFavoriteToggle: () => _toggleFavorite(shop),
                              onTap: () => _openShop(shop),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 店舗カード（結果画面） ────────────────────────────────────
class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.shop,
    required this.isFavorited,
    required this.onFavoriteToggle,
    required this.onTap,
  });

  final Shop shop;
  final bool isFavorited;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: _kSurface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: shop.url.isEmpty ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _kOrange.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.store_rounded, color: _kOrange, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop.name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600, color: _kText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shop.address,
                      style: const TextStyle(fontSize: 12, color: _kSub),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // お気に入りボタン
              GestureDetector(
                onTap: onFavoriteToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      key: ValueKey(isFavorited),
                      color: isFavorited ? Colors.redAccent : _kSub,
                      size: 22,
                    ),
                  ),
                ),
              ),
              if (shop.url.isNotEmpty)
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: _kSub),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── GPS ──────────────────────────────────────────────────────
Future<Position> determinePosition() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('位置情報サービスがOFFです。端末の設定でONにしてください。');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('位置情報の許可が拒否されました。');
    }
  }
  if (permission == LocationPermission.deniedForever) {
    throw Exception('位置情報が「常に拒否」になっています。端末の設定から許可してください。');
  }

  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
  );
}
