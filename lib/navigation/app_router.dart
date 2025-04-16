import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../screens/home_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/about_screen.dart';
import '../screens/password_reset_screen.dart';
import '../screens/complete_profile_screen.dart';
import '../screens/relatives_screen.dart';
import '../screens/trees_screen.dart';
import '../screens/tree_view_screen.dart';
import '../screens/tree_selector_screen.dart';
import '../screens/add_relative_screen.dart';
import '../screens/relation_requests_screen.dart';
import '../screens/send_relation_request_screen.dart';
import '../screens/create_post_screen.dart';
import '../services/auth_service.dart';
import '../screens/family_tree/create_tree_screen.dart';
import '../screens/chat_screen.dart';
import '../widgets/offline_indicator.dart';
import '../screens/offline_profiles_screen.dart';
import '../screens/relative_details_screen.dart';
import '../models/family_person.dart';
import '../screens/privacy_policy_screen.dart';
import '../providers/tree_provider.dart';
import 'package:provider/provider.dart';

// Ключ для корневого навигатора
final rootNavigatorKey = GlobalKey<NavigatorState>();
// Ключи для навигаторов внутри вкладок (опционально, для сохранения состояния глубже)
// final _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
// final _shellNavigatorRelativesKey = GlobalKey<NavigatorState>(debugLabel: 'shellRelatives');
// final _shellNavigatorTreeKey = GlobalKey<NavigatorState>(debugLabel: 'shellTree');
// final _shellNavigatorTreesKey = GlobalKey<NavigatorState>(debugLabel: 'shellTrees');
// final _shellNavigatorProfileKey = GlobalKey<NavigatorState>(debugLabel: 'shellProfile');

// --- Классы страниц GoRouter ---

// Базовый класс для кастомных переходов, наследуемся от пакета go_router
class LineageCustomTransitionPage<T> extends CustomTransitionPage<T> {
  LineageCustomTransitionPage({
    required super.child,
    required super.transitionsBuilder,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    super.transitionDuration = const Duration(milliseconds: 300),
    super.reverseTransitionDuration = const Duration(milliseconds: 300),
    // maintainState убран
  }) : super(maintainState: true); // ВОЗВРАЩАЕМ maintainState, он важен для ShellRoute!
}

// Страница без анимации для вкладок ShellRoute
class NoTransitionPage<T> extends LineageCustomTransitionPage<T> {
  NoTransitionPage({ required Widget child, LocalKey? key })
      : super(
          key: key ?? ValueKey<String>(child.toString()), // Генерируем ключ, если не предоставлен
          child: child,
          transitionsBuilder: (context, animation, secondaryAnimation, child) => child,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
}

class AuthState extends ChangeNotifier {
  final AuthService _authService;
  late final StreamSubscription<User?> _subscription;
  
  AuthState(this._authService) {
    _subscription = _authService.authStateChanges.listen((_) {
      notifyListeners();
    });
  }
  
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  final AuthService _authService = AuthService();
  final authState = AuthState(AuthService());
  
  late final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true, // Отключить в продакшн
    initialLocation: '/',
    refreshListenable: authState,
    
    // Обработчик редиректа для аутентификации
    redirect: (context, state) async {
      final isLoggedIn = FirebaseAuth.instance.currentUser != null;
      final loggingInPages = ['/login', '/password_reset', '/privacy'];
      final isLoggingIn = loggingInPages.contains(state.matchedLocation);
      final completingProfile = state.matchedLocation == '/complete_profile';
      
      // Если не залогинен и не на странице входа/сброса/завершения профиля/политики -> на /login
      if (!isLoggedIn && !isLoggingIn && !completingProfile) {
        print('Redirecting to /login (not logged in)');
        return '/login';
      }
      
      // Если залогинен и на странице входа -> на /
      if (isLoggedIn && isLoggingIn) {
        print('Redirecting to / (already logged in)');
        return '/';
      }
      
      // Если залогинен, но профиль не заполнен и не на странице заполнения -> на /complete_profile
      if (isLoggedIn && !completingProfile) {
        try {
          final user = FirebaseAuth.instance.currentUser!;
          print('Checking profile completeness for ${user.uid}');
          final profileStatus = await _authService.checkProfileCompleteness(user);
          print('Profile status: $profileStatus');
          if (!profileStatus['isComplete']!) {
            print('Redirecting to /complete_profile (profile incomplete)');
            return '/complete_profile?requiredFields=${Uri.encodeComponent(profileStatus.toString())}'; // Кодируем параметры
          }
        } catch (e) {
          print('Error checking profile completeness during redirect: $e');
          // Возможно, стоит перенаправить на страницу ошибки или остаться
        }
      }
      
      print('No redirect needed for location: ${state.matchedLocation}');
      return null; // Нет редиректа
    },
    
    routes: [
      // Основной каркас приложения с нижней навигацией
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // Возвращаем Scaffold с BottomNavigationBar
          return Scaffold(
            body: Column(
              children: [
                OfflineIndicator(), // Индикатор офлайн-режима
                Expanded(child: navigationShell), // Текущий навигатор ветки
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              type: BottomNavigationBarType.fixed, // Важно для > 3 элементов
              currentIndex: navigationShell.currentIndex,
              selectedItemColor: Theme.of(context).colorScheme.primary, // Используем colorScheme
              unselectedItemColor: Colors.grey,
              onTap: (index) {
                // Переход к ветке с сохранением состояния
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
              items: [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home), // Добавим активную иконку
                  label: 'Главная',
                ),
                BottomNavigationBarItem(
                   icon: Icon(Icons.people_outline),
                   activeIcon: Icon(Icons.people),
                  label: 'Родные',
                ),
                BottomNavigationBarItem(
                  icon: Container( // Центральная кнопка "Дерево"
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary, // Используем colorScheme
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.account_tree,
                      color: Theme.of(context).colorScheme.onPrimary, // Цвет на фоне основной кнопки
                      size: 20,
                    ),
                  ),
                  label: 'Дерево',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.forest_outlined),
                   activeIcon: Icon(Icons.forest),
                  label: 'Деревья',
                ),
                BottomNavigationBarItem(
                   icon: Icon(Icons.person_outline),
                   activeIcon: Icon(Icons.person),
                  label: 'Профиль',
                ),
              ],
            ),
          );
        },
        branches: [
          // Ветка 1: Главная
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorHomeKey,
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: HomeScreen(),
                ),
                routes: [
                  // <<< Добавляем маршрут для создания поста >>>
                  GoRoute(
                    path: 'post/create', // Относительный путь от '/'
                    // Открываем поверх основного экрана, используя rootNavigatorKey
                    parentNavigatorKey: rootNavigatorKey, 
                    pageBuilder: (context, state) => LineageCustomTransitionPage(
                      key: state.pageKey, // Используем ключ для уникальности страницы
                      child: const CreatePostScreen(),
                      // Анимация "слайд снизу вверх" для модального эффекта
                      transitionsBuilder: slideUpTransition,
                    ),
                  ),
                  // ================================================
                  GoRoute(
                    path: 'user/:userId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final userId = state.pathParameters['userId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        child: Scaffold(
                          appBar: AppBar(title: Text('Профиль пользователя (ID: $userId)')),
                          body: Center(child: Text('Отображение профиля по User ID пока не реализовано.')),
                        ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                ]
              ),
            ],
          ),
          
          // Ветка 2: Родные
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorRelativesKey,
            routes: [
              GoRoute(
                path: '/relatives',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: RelativesScreen(),
                ),
                routes: [
                  // Добавление родственника (открывается поверх)
                  GoRoute(
                    path: 'add/:treeId',
                     parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        child: AddRelativeScreen(treeId: treeId),
                        transitionsBuilder: slideTransition,
                      ); 
                    },
                  ),
                  // Маршрут для РЕДАКТИРОВАНИЯ родственника
                  GoRoute(
                    path: 'edit/:treeId/:personId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      final personId = state.pathParameters['personId'] ?? '';
                      final personToEdit = state.extra as FamilyPerson?;
                      
                      if (treeId.isEmpty || personId.isEmpty) {
                         return MaterialPage(child: Scaffold(body: Center(child: Text('Ошибка: Не указан ID дерева или родственника для редактирования.'))));
                      }
                      
                      return LineageCustomTransitionPage(
                        key: ValueKey('edit_relative_${personId}'), 
                        child: AddRelativeScreen(
                          treeId: treeId,
                          person: personToEdit,
                          isEditing: true,
                        ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Просмотр запросов (открывается поверх)
                  GoRoute(
                    path: 'requests/:treeId',
                     parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                       final treeId = state.pathParameters['treeId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        child: RelationRequestsScreen(treeId: treeId),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Отправка запроса на родство (открывается поверх)
                  GoRoute(
                    path: 'send_request/:userId',
                     parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                       final userId = state.pathParameters['userId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        child: SendRelationRequestScreen(userId: userId),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Переход в чат с пользователем
                  GoRoute(
                    path: 'chat/:userId',
                     parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                       final userId = state.pathParameters['userId'] ?? '';
                       final name = state.uri.queryParameters['name'] ?? 'Пользователь';
                       final photoUrl = state.uri.queryParameters['photo'];
                       final relativeId = state.uri.queryParameters['relativeId'] ?? ''; // <-- ИЗВЛЕКАЕМ relativeId

                       // --- Добавим проверку на наличие relativeId --- 
                       if (relativeId.isEmpty) {
                         print('Error: Missing relativeId for chat route');
                         // Можно вернуть страницу с ошибкой или перенаправить
                         return MaterialPage(
                           key: state.pageKey,
                            child: Scaffold(appBar: AppBar(title: Text('Ошибка')), body: Center(child: Text('Не найден ID родственника для чата.')))
                         );
                       }
                       // -----------------------------------------------

                       return LineageCustomTransitionPage(
                         key: state.pageKey,
                         child: ChatScreen(
                           otherUserId: userId,
                           otherUserName: name,
                           otherUserPhotoUrl: photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
                           relativeId: relativeId, // <-- ПЕРЕДАЕМ relativeId
                         ),
                         transitionsBuilder: slideTransition,
                       );
                    },
                  ),
                ],
              ),
            ],
          ),
          
          // Ветка 3: Дерево (Центральная кнопка)
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorTreeKey,
            routes: [
              GoRoute(
                path: '/tree',
                redirect: (context, state) {
                  final treeProvider = context.read<TreeProvider>();
                  final selectedTreeId = treeProvider.selectedTreeId;
                  if (selectedTreeId != null && !state.matchedLocation.startsWith('/tree/view')) {
                    print('[GoRouter Redirect] Tree is selected ($selectedTreeId), redirecting from /tree to /tree/view/$selectedTreeId');
                    // Передаем имя дерева в параметры, если оно есть
                    final nameParam = treeProvider.selectedTreeName != null ? '?name=${Uri.encodeComponent(treeProvider.selectedTreeName!)}' : '';
                    return '/tree/view/$selectedTreeId$nameParam';
                  }
                  return null;
                },
                pageBuilder: (context, state) => NoTransitionPage(
                  child: TreeSelectorScreen(),
                ),
                routes: [
                  // Просмотр конкретного дерева (открывается поверх)
                  GoRoute(
                    path: 'view/:treeId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      // treeId из pathParameters, name из queryParameters
                      final treeId = state.pathParameters['treeId'] ?? '';
                      final treeName = state.uri.queryParameters['name'] ?? 'Семейное дерево';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        // Передаем treeId и treeName обратно в конструктор, если они нужны TreeViewScreen
                        // (Если нет, то конструктор TreeViewScreen должен быть без параметров и брать данные из Provider)
                        child: TreeViewScreen( /* treeId: treeId, treeName: treeName */ ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          
          // Ветка 4: Список Деревьев
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorTreesKey,
            routes: [
              GoRoute(
                path: '/trees',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: TreesScreen(),
                ),
                 routes: [
                   GoRoute(
                     path: 'create',
                      parentNavigatorKey: rootNavigatorKey,
                     pageBuilder: (context, state) => LineageCustomTransitionPage(
                       key: state.pageKey,
                       child: const CreateTreeScreen(),
                       transitionsBuilder: slideTransition,
                     ),
                   ),
                 ],
              ),
            ],
          ),
          
          // Ветка 5: Профиль
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorProfileKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => NoTransitionPage(
                  child: ProfileScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => LineageCustomTransitionPage(
                      key: state.pageKey,
                      child: const ProfileEditScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'settings',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => LineageCustomTransitionPage(
                      key: state.pageKey,
                      child: const SettingsScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => LineageCustomTransitionPage(
                      key: state.pageKey,
                      child: const AboutScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'offline_profiles',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => LineageCustomTransitionPage(
                      key: state.pageKey,
                      child: const OfflineProfilesScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      
      // --- Маршруты вне основного Shell (доступны без BottomNavigationBar) ---
      GoRoute(
        path: '/login',
         parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          child: const AuthScreen(),
          transitionsBuilder: fadeTransition,
        ),
      ),
      GoRoute(
        path: '/password_reset',
         parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          child: const PasswordResetScreen(),
          transitionsBuilder: fadeTransition,
        ),
      ),
      GoRoute(
        path: '/complete_profile',
         parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final queryParams = state.uri.queryParameters;
          Map<String, bool> requiredFields = {};
           // Пытаемся распарсить из строки, если она есть
           final fieldsString = queryParams['requiredFields'];
           if (fieldsString != null) {
             try {
               // Убираем {} и разбиваем на пары ключ-значение
               final pairs = fieldsString.replaceAll(RegExp(r'[{}]'), '').split(', ');
               for (var pair in pairs) {
                 final parts = pair.split(': ');
                 if (parts.length == 2) {
                   requiredFields[parts[0]] = parts[1] == 'true';
                 }
               }
             } catch (e) {
               print('Error parsing requiredFields query param: $e');
               requiredFields = {'hasPhoneNumber': false, 'hasGender': false, 'hasUsername': false, 'isComplete': false};
             }
           } else {
             requiredFields = state.extra as Map<String, bool>? ??
                                {'hasPhoneNumber': false, 'hasGender': false, 'hasUsername': false, 'isComplete': false};
           }

          return LineageCustomTransitionPage(
            key: state.pageKey,
            child: CompleteProfileScreen(requiredFields: requiredFields),
            transitionsBuilder: fadeTransition,
          );
        },
      ),
      // Маршрут чата ВНЕ оболочки (дублирует тот, что внутри ветки /relatives)
      // Оставляем его для возможности перехода в чат из других мест (уведомления и т.д.)
      GoRoute(
        path: '/chat/:userId',
         parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
           final userId = state.pathParameters['userId'] ?? '';
           final name = state.uri.queryParameters['name'] ?? 'Пользователь';
           final photoUrl = state.uri.queryParameters['photo'];
           final relativeId = state.uri.queryParameters['relativeId'] ?? ''; // <-- ИЗВЛЕКАЕМ relativeId

           if (relativeId.isEmpty) {
             print('Error: Missing relativeId for chat route');
             return MaterialPage(
               key: state.pageKey,
                child: Scaffold(appBar: AppBar(title: Text('Ошибка')), body: Center(child: Text('Не найден ID родственника для чата.')))
             );
           }

           return LineageCustomTransitionPage(
             key: state.pageKey,
             child: ChatScreen(
               otherUserId: userId,
               otherUserName: name,
               otherUserPhotoUrl: photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
               relativeId: relativeId, // <-- ПЕРЕДАЕМ relativeId
             ),
             transitionsBuilder: slideTransition,
           );
        },
      ),
       GoRoute(
         path: '/user/:userId',
         parentNavigatorKey: rootNavigatorKey,
         pageBuilder: (context, state) {
           final userId = state.pathParameters['userId'] ?? '';
           return LineageCustomTransitionPage(
             key: state.pageKey,
             child: Scaffold(
                appBar: AppBar(title: Text('Профиль пользователя (ID: $userId)')),
                body: Center(child: Text('Отображение профиля по User ID пока не реализовано.')),
             ),
             transitionsBuilder: slideTransition,
           );
         },
       ),
       GoRoute(
         path: '/send_relation_request',
         parentNavigatorKey: rootNavigatorKey,
         pageBuilder: (context, state) {
           final userId = state.uri.queryParameters['userId'] ?? '';
           return LineageCustomTransitionPage(
             key: state.pageKey,
             child: SendRelationRequestScreen(userId: userId),
             transitionsBuilder: slideTransition,
           );
         },
       ),
      // --- Добавляем маршрут для Политики конфиденциальности --- 
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          child: const PrivacyPolicyScreen(),
          transitionsBuilder: slideTransition,
        ),
      ),
      // --- Общие маршруты, доступные из разных веток --- 
      GoRoute(
        path: '/relative/details/:personId',
         parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
           final personId = state.pathParameters['personId'] ?? '';
           if (personId.isEmpty) {
              return MaterialPage(
                key: state.pageKey,
                 child: Scaffold(body: Center(child: Text('Ошибка: ID родственника не указан')))
              );
           }
           return LineageCustomTransitionPage(
             key: ValueKey('relative_details_$personId'),
             child: RelativeDetailsScreen(personId: personId),
             transitionsBuilder: slideTransition,
           );
        },
      ),
    ],
    
    // Обработчик ошибок
    errorPageBuilder: (context, state) => MaterialPage(
      key: state.pageKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Страница не найдена')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ошибка 404: Страница не найдена\n${state.error}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Вернуться на главную'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  
  // Функции анимации переходов
  static Widget fadeTransition(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return FadeTransition(opacity: animation, child: child);
  }
  
  static Widget slideTransition(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;
    
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);
    
    return SlideTransition(position: offsetAnimation, child: child);
  }
  
  static Widget slideUpTransition(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;
    
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween); 
    
    return SlideTransition(position: offsetAnimation, child: child);
  }
} 