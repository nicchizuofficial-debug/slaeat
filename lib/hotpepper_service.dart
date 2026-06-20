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
  });

  final String name;
  final String genre;
  final String address;
  final double lat;
  final double lng;
  final String url; // ホットペッパーの店舗ページURL

  Map<String, dynamic> toJson() => {
        'name': name,
        'genre': genre,
        'address': address,
        'lat': lat,
        'lng': lng,
        'url': url,
      };

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        name: json['name'] as String? ?? '',
        genre: json['genre'] as String? ?? '',
        address: json['address'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
        lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
        url: json['url'] as String? ?? '',
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

  // 指定した緯度・経度の周辺にある飲食店を、時間帯に応じて取得する。
  // range: 1=300m, 2=500m, 3=1000m, 4=2000m, 5=3000m。
  // budget: Hotpepper予算コード（null=指定なし）。
  // seatTypes: 絞り込む席タイプ名の集合。
  // partyCapacity: 最低収容人数（null=指定なし）。
  static Future<GourmetResult> fetchNearby({
    required double latitude,
    required double longitude,
    int range = 3,
    DateTime? now,
    MealTime? mealOverride,
    String? budget,
    Set<String> seatTypes = const {},
    int? partyCapacity,
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
      final shop = Shop(
        name: shopMap['name'] as String? ?? '',
        genre: genre,
        address: shopMap['address'] as String? ?? '',
        lat: (shopMap['lat'] as num?)?.toDouble() ?? latitude,
        lng: (shopMap['lng'] as num?)?.toDouble() ?? longitude,
        url: urls?['pc'] as String? ?? '',
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
