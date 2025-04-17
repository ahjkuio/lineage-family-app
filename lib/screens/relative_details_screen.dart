import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // Для форматирования дат
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lineage/models/family_person.dart';
import 'package:lineage/services/family_service.dart';
import 'package:lineage/widgets/loading_indicator.dart';
import '../models/family_relation.dart'; // Добавляем импорт

import '../models/user_profile.dart';
import '../services/profile_service.dart';
import '../services/chat_service.dart';
import '../providers/tree_provider.dart'; // Для treeId
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:get_it/get_it.dart';
import '../services/auth_service.dart'; // Добавляем импорт
import 'package:flutter/foundation.dart' show kIsWeb; // Для проверки платформы

class RelativeDetailsScreen extends StatefulWidget {
  final String personId;

  const RelativeDetailsScreen({required this.personId, Key? key}) : super(key: key);

  @override
  _RelativeDetailsScreenState createState() => _RelativeDetailsScreenState();
}

class _RelativeDetailsScreenState extends State<RelativeDetailsScreen> {
  // Используем widget.personId для доступа к ID
  final AuthService _auth = AuthService(); // Инициализируем
  final FamilyService _familyService = GetIt.I<FamilyService>(); 
  final ProfileService _profileService = ProfileService(); // Инициализируем
  final ChatService _chatService = ChatService();
  bool _isGeneratingLink = false;
  
  FamilyPerson? _person;
  UserProfile? _userProfile;
  UserProfile? _currentUserProfile;
  RelationType? _relationToCurrentUser;
  bool _isLoading = true;
  String _errorMessage = '';
  String? _currentTreeId;
  
  @override
  void initState() {
    super.initState();
    // Получаем treeId из провайдера ПОСЛЕ построения виджета
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _currentTreeId = Provider.of<TreeProvider>(context, listen: false).selectedTreeId;
      _loadData();
    });
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _person = null;
      _userProfile = null;
      _relationToCurrentUser = null;
    });

    if (_currentTreeId == null) {
       setState(() {
         _isLoading = false;
         _errorMessage = 'Ошибка: Не удалось определить текущее дерево.';
       });
       return;
    }

    try {
      // 0. Загружаем профиль ТЕКУЩЕГО пользователя (нужен для getReciprocalType)
      final currentUserId = _auth.currentUser?.uid;
      if (currentUserId != null) {
         try {
            _currentUserProfile = await _profileService.getUserProfile(currentUserId);
         } catch (profileError) {
            print('Не удалось загрузить профиль текущего пользователя: $profileError');
            // Не считаем критичной ошибкой для отображения деталей родственника
         }
      }

      // 1. Загружаем FamilyPerson по ID
      // TODO: FamilyService должен иметь метод getPersonById(treeId, personId)
      // Пока используем getRelatives и фильтруем
      final relatives = await _familyService.getRelatives(_currentTreeId!);
      _person = relatives.firstWhere(
         (p) => p.id == widget.personId,
         orElse: () => throw Exception('Родственник с ID ${widget.personId} не найден в дереве $_currentTreeId')
      );

      // 2. Если есть userId, пытаемся загрузить UserProfile
      if (_person!.userId != null && _person!.userId!.isNotEmpty) {
        _userProfile = await _profileService.getUserProfile(_person!.userId!);
        // Ошибку загрузки профиля пока не считаем критичной
      }

      // 3. Определяем родственную связь с текущим пользователем
      if (currentUserId != null && _person != null) {
         _relationToCurrentUser = await _familyService.getRelationBetween(_currentTreeId!, currentUserId, _person!.id);
         print('Связь ${widget.personId} с текущим пользователем ($currentUserId): $_relationToCurrentUser');
         print('Пол родственника ${_person!.id}: ${_person!.gender}');
      }

      if (mounted) {
        setState(() {
          _isLoading = false; 
        });
      }
    } catch (e) {
      print('Ошибка загрузки данных родственника ${widget.personId}: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Не удалось загрузить данные родственника.';
        });
      }
    }
  }

  // Форматирование даты
  String _formatDate(DateTime? date) {
    if (date == null) return 'Неизвестно';
    return DateFormat.yMMMMd('ru').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_person?.displayName ?? 'Профиль'),
        leading: IconButton(
           icon: Icon(Icons.arrow_back),
           onPressed: () => context.pop(),
        ),
        actions: [
          if (_canEditOrDelete())
          IconButton(
              icon: Icon(Icons.edit_outlined),
              tooltip: 'Редактировать профиль',
            onPressed: _editRelative,
          ),
          if (_canEditOrDelete())
             IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Удалить профиль',
              onPressed: _deleteRelative,
             ),
          if (_person != null && (_person!.userId == null || _person!.userId!.isEmpty) && _person!.id != _auth.currentUser?.uid)
            IconButton(
              icon: _isGeneratingLink 
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : Icon(Icons.person_add_alt_1),
              tooltip: 'Пригласить пользователя',
              onPressed: _isGeneratingLink ? null : _generateAndShareInviteLink,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage, textAlign: TextAlign.center),
        ),
      );
    }
    if (_person == null) {
      // Эта ситуация не должна возникать, если _loadData отработал без ошибок
      return const Center(child: Text('Данные родственника не найдены.'));
    }

    // Определяем, онлайн ли пользователь
    final bool isOnline = _person!.userId != null && _person!.userId!.isNotEmpty;
    // Используем данные UserProfile если они есть, иначе данные FamilyPerson
    final String displayName = _userProfile?.displayName ?? _person!.displayName;
    final String? photoUrl = _userProfile?.photoURL ?? _person!.photoUrl;
    final String? city = _userProfile?.city;
    final String? country = _userProfile?.country;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Шапка профиля ---
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                child: photoUrl == null
                    ? Text(_person!.initials, style: TextStyle(fontSize: 24))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible( // Чтобы имя переносилось
                          child: Text(
                            displayName,
                            style: Theme.of(context).textTheme.headlineSmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 2,
                          ),
                        ),
                        if (isOnline)
                          Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Icon(Icons.verified, color: Colors.blue, size: 18), // Иконка "онлайн"
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Отображаем город/страну, если есть
                     if ((city != null && city.isNotEmpty) || (country != null && country.isNotEmpty))
                       Row(
                          children: [
                            Icon(Icons.location_on, size: 16, color: Colors.grey),
                            SizedBox(width: 4),
                            Text(
                              '${city ?? ''}${(city != null && city.isNotEmpty && country != null && country.isNotEmpty) ? ', ' : ''}${country ?? ''}',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                       ),
                     const SizedBox(height: 4),
                     // Добавляем кнопку чата для онлайн пользователей
                     if (isOnline && _person!.userId != _auth.currentUser?.uid)
                       ElevatedButton.icon(
                          icon: Icon(Icons.message_outlined, size: 16),
                          label: Text('Написать', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () async {
                            try {
                              final chatId = await _chatService.getOrCreateChat(_person!.userId!);
                              if (chatId != null && mounted) {
                                final nameParam = Uri.encodeComponent(displayName);
                                final photoParam = photoUrl != null ? Uri.encodeComponent(photoUrl) : '';
                                context.push('/relatives/chat/${_person!.userId}?name=$nameParam&photo=$photoParam');
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                   SnackBar(content: Text('Не удалось начать чат.')),
                                );
                              }
                            } catch (e) {
                               print('Ошибка при переходе в чат: $e');
                               if (mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(
                                   SnackBar(content: Text('Ошибка при открытии чата.')),
                                );
                               }
                            }
                          },
                        )
                  ],
              ),
            ),
          ],
        ),
          const Divider(height: 32),

          // --- Основная информация ---
          _buildInfoSection('Основная информация', [
            _buildInfoRow('Пол:', _genderToString(_person!.gender)),
            if (_person!.maidenName != null && _person!.maidenName!.isNotEmpty)
              _buildInfoRow('Девичья фамилия:', _person!.maidenName!),
            if (_relationToCurrentUser != null && _relationToCurrentUser != RelationType.other)
              _buildInfoRow(
                 'Родственная связь:',
                 () {
                    // Отношение пользователя к родственнику (результат getRelationBetween)
                    final relationUserToRelative = _relationToCurrentUser!;
                    // Получаем зеркальное отношение (родственника к пользователю)
                    final relationRelativeToUser = FamilyRelation.getMirrorRelation(relationUserToRelative);
                    print('Отображаемая связь (пользователь -> ${_person!.id}): $relationUserToRelative');
                    print('Зеркальная связь (${_person!.id} -> пользователь): $relationRelativeToUser');
                    // Используем ЗЕРКАЛЬНОЕ отношение и ПОЛ РОДСТВЕННИКА для имени
                    return FamilyRelation.getRelationName(relationRelativeToUser, _person!.gender);
                 }()
              ),
          ]),

          // --- Даты жизни ---
          _buildInfoSection('Даты жизни', [
            _buildInfoRow('Дата рождения:', _formatDate(_person!.birthDate)),
            if (_person!.birthPlace != null && _person!.birthPlace!.isNotEmpty)
              _buildInfoRow('Место рождения:', _person!.birthPlace!),
            if (!_person!.isAlive) ...[
               _buildInfoRow('Дата смерти:', _formatDate(_person!.deathDate)),
               if (_person!.deathPlace != null && _person!.deathPlace!.isNotEmpty)
                 _buildInfoRow('Место смерти:', _person!.deathPlace!),
            ] else
               _buildInfoRow('Статус:', 'Жив(а)'),
          ]),

          // --- Заметки ---
          if (_person!.notes != null && _person!.notes!.isNotEmpty)
             _buildInfoSection('Заметки', [
               Text(_person!.notes!, style: Theme.of(context).textTheme.bodyMedium)
             ]),

           // --- Связи ---
           // TODO: Добавить отображение связей (родители, дети, супруги)
           // Нужно будет загрузить связи для этого человека
           // _buildInfoSection('Семья', [ ... ]),

           const SizedBox(height: 20), // Отступ снизу
        ],
      ),
    );
  }
  
  Widget _buildInfoSection(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120, // Фиксированная ширина для метки
            child: Text(label, style: TextStyle(color: Colors.grey[600])),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
  
  String _genderToString(Gender gender) {
    switch (gender) {
      case Gender.male: return 'Мужской';
      case Gender.female: return 'Женский';
      case Gender.other: return 'Другой';
      case Gender.unknown: return 'Не указан';
    }
  }
  
  bool _canEditOrDelete() {
    return _person != null &&
           (_person!.userId == null || _person!.userId!.isEmpty) &&
           _person!.creatorId == _auth.currentUser?.uid;
  }
  
  void _editRelative() {
     if (!_canEditOrDelete() || _currentTreeId == null) return;

     print('Переход на редактирование: personId=${_person!.id}, treeId=$_currentTreeId');
     context.push('/relatives/edit/${_currentTreeId!}/${_person!.id}', extra: _person).then((result) {
       if (result == true && mounted) {
         print('Возврат с экрана редактирования, перезагрузка данных...');
         _loadData();
      }
    });
  }

  Future<void> _deleteRelative() async {
     if (!_canEditOrDelete() || _currentTreeId == null) return;

     final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
           title: const Text('Подтверждение удаления'),
           content: Text('Вы уверены, что хотите удалить профиль ''${_person!.displayName}''? Это действие необратимо.'),
           actions: [
             TextButton(
               child: const Text('Отмена'),
               onPressed: () => Navigator.of(context).pop(false),
             ),
             TextButton(
               child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
               onPressed: () => Navigator.of(context).pop(true),
             ),
           ],
        ),
     );

     if (confirm == true) {
       setState(() { _isLoading = true; });
       try {
         await _familyService.deleteRelative(_currentTreeId!, widget.personId);
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Профиль ''${_person!.displayName}'' удален.')),
            );
            context.pop();
         }
       } catch (e) {
          print('Ошибка удаления родственника: $e');
          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Ошибка при удалении профиля: $e')),
             );
             setState(() { _isLoading = false; });
          }
       }
     }
  }

  Future<void> _generateAndShareInviteLink() async {
    if (_person == null || _currentTreeId == null) return;

    // --- Проверка на веб-платформу --- 
    if (kIsWeb) {
      // В вебе динамические ссылки не работают штатно через этот пакет
      // Можно показать сообщение или скопировать простую ссылку
      final simpleLink = 'https://lineagefamilyapp.page.link'; // Или ссылка на ваш сайт/PWA
      await Share.share(
        'Присоединяйтесь к нашему семейному древу Lineage! $simpleLink',
        subject: 'Приглашение в Lineage',
      );
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Ссылка-приглашение скопирована (веб-версия).')),
       );
      return; // Выходим, не генерируя динамическую ссылку
    }
    // --- Конец проверки --- 

    setState(() { _isGeneratingLink = true; });

    try {
      final inviteUrl = await _familyService.generateInvitationLink(
        _currentTreeId!, 
        _person!.id,
      );

      if (mounted && inviteUrl != null) {
        final box = context.findRenderObject() as RenderBox?;
        // Используем share_plus для отправки ссылки
        await Share.share(
          'Присоединяйтесь к нашему семейному древу Lineage! ${inviteUrl.toString()}', 
          subject: 'Приглашение в Lineage',
          sharePositionOrigin: box!.localToGlobal(Offset.zero) & box.size, // Позиция для iPad
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось создать ссылку-приглашение.')),
        );
      }

    } catch (e) {
      print('Ошибка при генерации или отправке ссылки: $e');
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
       if (mounted) {
        setState(() { _isGeneratingLink = false; });
      }
    }
  }
} 