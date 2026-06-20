import 'package:flutter_test/flutter_test.dart';
import 'package:shoukyohou_food/hotpepper_service.dart';

void main() {
  // 指定した時刻のDateTimeを作るヘルパー。
  DateTime at(int hour) => DateTime(2026, 6, 21, hour, 0);

  group('時間帯（朝・昼・晩）の判定', () {
    test('朝: 5〜10時は morning', () {
      expect(HotpepperService.currentMealTime(at(5)), MealTime.morning);
      expect(HotpepperService.currentMealTime(at(7)), MealTime.morning);
      expect(HotpepperService.currentMealTime(at(10)), MealTime.morning);
    });

    test('昼: 11〜15時は lunch', () {
      expect(HotpepperService.currentMealTime(at(11)), MealTime.lunch);
      expect(HotpepperService.currentMealTime(at(12)), MealTime.lunch);
      expect(HotpepperService.currentMealTime(at(15)), MealTime.lunch);
    });

    test('晩: 16〜翌4時は dinner', () {
      expect(HotpepperService.currentMealTime(at(16)), MealTime.dinner);
      expect(HotpepperService.currentMealTime(at(20)), MealTime.dinner);
      expect(HotpepperService.currentMealTime(at(23)), MealTime.dinner);
      expect(HotpepperService.currentMealTime(at(2)), MealTime.dinner);
      expect(HotpepperService.currentMealTime(at(4)), MealTime.dinner);
    });

    test('ラベルが正しい', () {
      expect(HotpepperService.mealLabel(MealTime.morning), '朝ごはん');
      expect(HotpepperService.mealLabel(MealTime.lunch), 'ランチ');
      expect(HotpepperService.mealLabel(MealTime.dinner), 'ディナー');
    });
  });
}
