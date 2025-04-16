import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum AppEventType {
  birthday,
  memorial9days,
  memorial40days,
  // anniversary, // Пока не используем
  other,
}

class AppEvent {
  final String id; // Может быть полезен, например, personId + eventType
  final AppEventType type;
  final DateTime date;
  final String title; // Например, "День рождения" или "9 дней"
  final String personName;
  final String personId;
  final IconData icon; // Иконка для отображения

  AppEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.title,
    required this.personName,
    required this.personId,
    required this.icon,
  });

  // Метод для получения оставшегося времени или статуса
  String get status {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final difference = eventDay.difference(today).inDays;

    if (difference == 0) {
      return 'Сегодня';
    } else if (difference == 1) {
      return 'Завтра';
    } else if (difference > 1 && difference <= 7) {
      return 'Через \$difference дн.'; // TODO: Склонение дней
    } else if (difference < 0) {
      return 'Прошло'; // На всякий случай
    } else {
      // Показываем дату для событий > недели
      return DateFormat.MMMd('ru').format(date);
    }
  }
} 