import 'dart:convert';

import 'package:http/http.dart' as http;

import 'secrets.dart';

// 食事の時間帯。
enum MealTime { morning, lunch, dinner }

// 1店舗分の情報。
class Shop {
  const Shop({
    required this.name,
    required this.genre,
    required this.address,
    required this.lat,
    required this.lng,
    required this.url,
    this.openTime = '',
  });

  final String name;
  final String genre;
  final String address;
  final double lat;
  final double lng;
  final String url; // ホットペッパーの店舗ページURL
  final String openTime; // 営業時間テキスト（例: "月〜日: 11:00〜23:00"）

  Map<String, dynamic> toJson() => {
        'name': name,
        'genre': genre,
        'address': address,
        'lat': lat,
        'lng': lng,
        'url': url,
        'openTime': openTime,
      };

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        name: json['name'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        address: json['address'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
        url: json['url'] as String? ?? '',
        openTime: json['openTime'] as String? ?? '',
      );
}

// API取得結果（ジャンル一覧＋ジャンルごとの店舗＋時間帯ラベル）。
class GourmetResult {
  const GourmetResult({
    required this.genres,
    required this.shopsByGenre,
    required this.timeLabel,
  });

  final List<String> genres; // 重複なしのジャンル一覧
  final Map<String, List<Shop>> shopsByGenre; // ジャンル名 → 店舗リスト
  final String timeLabel; // 「朝ごはん」「ランチ」「ディナー」
}

class HotpepperService {
  // 現在時刻から食事の時間帯を判定する。
  static MealTime currentMealTime([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour >= 5 && hour < 11) return MealTime.morning;
    if (hour >= 11 && hour < 16) return MealTime.lunch;
    return MealTime.dinner;
  }

  // 時間帯の表示ラベル。
  static String mealLabel(MealTime meal) {
    switch (meal) {
      case MealTime.morning:
        return '朝ごはん';
      case MealTime.lunch:
        return 'ランチ';
      case MealTime.dinner:
        return 'ディナー';
    }
  }

  // 朝は除外する（お酒メインの）ジャンル。
  static const Set<String> _morningExclude = {
    '居酒屋',
    'ダイニングバー・バル',
    'バー・カクテル',
  };

  // 席タイプ名 → APIパラメータキーのマッピング
  static const Map<String, String> seatTypeParams = {
    '個室': 'private_room',
    '座敷': 'tatami',
    'テラス': 'terrace',
    '食べ放題': 'free_food',
    '飲み放題': 'free_drink',
  };

  // 営業時間テキストをパースして現在営業中かを判定する。
  // パースできない形式の場合は true（表示する）を返す。
  static bool isCurrentlyOpen(String openTime, [DateTime? now]) {
    if (openTime.isEmpty) return true;
    final dt = now ?? DateTime.now();
    final nowMin = dt.hour * 60 + dt.minute;
    final wd = dt.weekday; // Mon=1 … Sun=7

    const kDow = {'月': 1, '火': 2, '水': 3, '木': 4, '金': 5, '土': 6, '日': 7};

    // 「祝日」「祝前日」などの複合語に含まれる「日」を日曜と誤認しないよう除去する。
    final cleaned = openTime
        .replaceAll('祝前日', '')
        .replaceAll('祝日', '')
        .replaceAll('定休日', '')
        .replaceAll('休日', '');

    final segRe = RegExp(
        r'(?:([月火水木金土日・〜～、]+)\s*[：:]\s*)?(\d{1,2}[：:]\d{2})\s*[〜～]\s*(翌)?(\d{1,2}[：:]\d{2})');

    final matches = segRe.allMatches(cleaned).toList();
    if (matches.isEmpty) return true; // パース不能 → 表示する

    for (final m in matches) {
      final daySpec = m.group(1);

      if (daySpec != null && daySpec.isNotEmpty) {
        bool dayOk = false;

        // 「月〜金」のような範囲指定
        final rangeM =
            RegExp(r'([月火水木金土日])\s*[〜～]\s*([月火水木金土日])').firstMatch(daySpec);
        if (rangeM != null) {
          final s = kDow[rangeM.group(1)]!;
          final e = kDow[rangeM.group(2)]!;
          dayOk =
              s <= e ? wd >= s && wd <= e : wd >= s || wd <= e;
        } else {
          // 個別指定（月・水・金 など）
          for (final entry in kDow.entries) {
            if (daySpec.contains(entry.key) && wd == entry.value) {
              dayOk = true;
              break;
            }
          }
        }

        if (!dayOk) continue;
      }

      final oMin = _parseHHMM(m.group(2)!);
      final nextDay = m.group(3) != null;
      var cMin = _parseHHMM(m.group(4)!);
      if (nextDay || cMin <= oMin) cMin += 24 * 60; // 深夜をまたぐ場合

      var check = nowMin;
      if (check < oMin && cMin > 24 * 60) check += 24 * 60;

      if (check >= oMin && check < cMin) return true;
    }

    return false;
  }

  static int _parseHHMM(String s) {
    final p = s.replaceAll('：', ':').split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  // 指定した緯度・経度の周辺にある飲食店を、時間帯に応じて取得する。
  // range: 1=300m, 2=500m, 3=1000m, 4=2000m, 5=3000m。
  // budget: Hotpepper予算コード（null=指定なし）。
  // seatTypes: 絞り込む席タイプ名の集合。
  // partyCapacity: 最低収容人数（null=指定なし）。
  // openNowOnly: true のとき営業時間外の店舗を除外する。
  static Future<GourmetResult> fetchNearby({
    required double latitude,
    required double longitude,
    int range = 3,
    DateTime? now,
    MealTime? mealOverride,
    String? budget,
    Set<String> seatTypes = const {},
    int? partyCapacity,
    bool openNowOnly = false,
  }) async {
    final time = now ?? DateTime.now();
    final meal = mealOverride ?? currentMealTime(time);

    // APIに渡すパラメータを組み立てる。
    final params = <String, String>{
      'key': hotpepperApiKey,
      'lat': latitude.toString(),
      'lng': longitude.toString(),
      'range': range.toString(),
      'count': '100',
      'format': 'json',
    };

    // 予算コードが指定されている場合に追加。
    if (budget != null) params['budget'] = budget;

    // 席タイプフィルタ。
    for (final seat in seatTypes) {
      final param = seatTypeParams[seat];
      if (param != null) params[param] = '1';
    }

    // 人数指定がある場合に追加。
    if (partyCapacity != null && partyCapacity >= 2) {
      params['party_capacity'] = partyCapacity.toString();
    }

    // 朝・昼は「ランチあり」の店に絞る。
    if (meal == MealTime.morning || meal == MealTime.lunch) {
      params['lunch'] = '1';
    }
    // 深夜（23時〜翌5時）は「23時以降も営業」の店に絞る。
    if (meal == MealTime.dinner && (time.hour >= 23 || time.hour < 5)) {
      params['midnight'] = '1';
    }

    final uri = Uri.https(
      'webservice.recruit.co.jp',
      '/hotpepper/gourmet/v1/',
      params,
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('通信エラー: ステータスコード ${response.statusCode}');
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    final results = data['results'] as Map<String, dynamic>;

    if (results.containsKey('error')) {
      final error = (results['error'] as List).first as Map<String, dynamic>;
      throw Exception('APIエラー: ${error['message']}');
    }

    final rawShops = results['shop'] as List<dynamic>? ?? [];

    // ジャンルごとに店舗をまとめる（Mapのキーが自動で重複排除になる）。
    final shopsByGenre = <String, List<Shop>>{};
    for (final raw in rawShops) {
      final shopMap = raw as Map<String, dynamic>;
      final rawGenre = (shopMap['genre'] as Map<String, dynamic>?)?['name'] as String?;
      final genre = rawGenre?.trim();
      if (genre == null || genre.isEmpty) continue;

      // 朝はお酒メインのジャンルを除外する。
      if (meal == MealTime.morning && _morningExclude.contains(genre)) continue;

      final urls = shopMap['urls'] as Map<String, dynamic>?;
      final openTimeText = shopMap['open'] as String? ?? '';

      if (openNowOnly && !isCurrentlyOpen(openTimeText, time)) continue;

      final shop = Shop(
        name: shopMap['name'] as String? ?? '',
        genre: genre,
        address: shopMap['address'] as String? ?? '',
        lat: (shopMap['lat'] as num?)?.toDouble() ?? latitude,
        lng: (shopMap['lng'] as num?)?.toDouble() ?? longitude,
        url: urls?['pc'] as String? ?? '',
        openTime: openTimeText,
      );

      shopsByGenre.putIfAbsent(genre, () => []).add(shop);
    }

    return GourmetResult(
      genres: shopsByGenre.keys.toList(),
      shopsByGenre: shopsByGenre,
      timeLabel: mealLabel(meal),
    );
  }
}
