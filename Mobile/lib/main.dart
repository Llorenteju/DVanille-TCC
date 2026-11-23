import 'package:flutter/material.dart';

import 'models/models.dart';
import 'theme/app_theme.dart';
import 'state/app_state.dart';

import 'screens/auth/auth_screens.dart';
import 'screens/home/main_nav_screen.dart';
import 'screens/menu/menu_screen.dart';
import 'screens/menu/product_details_screen.dart';
import 'screens/favorites/favorites_screen.dart';
import 'screens/offers/offers_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/checkout/delivery_screen.dart';
import 'screens/checkout/payment_screen.dart';
import 'screens/checkout/order_confirmation_screen.dart';
import 'screens/orders/orders_screens.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/addresses_screen.dart';
import 'screens/profile/restrictions_notifications_settings.dart';
import 'screens/conheca/conheca_screen.dart';
import 'screens/admin/admin_screens.dart';
import 'screens/contato/contato_screen.dart';

void main() {
  runApp(const DVanilleApp());
}

class DVanilleApp extends StatelessWidget {
  const DVanilleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    // O JWT do Mobile e mantido em memoria nesta versao.
    // Depois de F5, nao mostrar rotas protegidas sem sessao ativa.
    Widget apenasCliente(Widget tela) =>
        state.isLoggedIn && !state.isAdmin ? tela : const LoginScreen();

    Widget apenasAdmin(Widget tela) =>
        state.isLoggedIn && state.isAdmin ? tela : const LoginScreen();

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
      title: "D'Vanille",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: state.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: '/login',
      routes: {
        // Autenticação
        '/login': (context) => const LoginScreen(),
        '/cadastro': (context) => const CadastroScreen(),
        '/recuperar': (context) => const RecuperarScreen(),
        '/emailok': (context) => const EmailOkScreen(),
        '/emailfail': (context) => const EmailFailScreen(),

        // Navegação principal
        '/main': (context) => apenasCliente(const MainNavScreen()),
        '/home': (context) => apenasCliente(const MainNavScreen()),
        '/cardapio': (context) => apenasCliente(const MenuScreen()),
        '/ofertas': (context) => apenasCliente(const OffersScreen()),
        '/conheca': (context) => apenasCliente(const ConhecaScreen()),
        '/contato': (context) => apenasCliente(const ContatoScreen()),

        // Favoritos / vale-presente
        '/favoritos': (context) => apenasCliente(const FavoritesScreen()),
        '/vale-presente': (context) => apenasCliente(const GiftCardScreen()),
        '/meus-vales': (context) => apenasCliente(const MyGiftCardsScreen()),

        // Carrinho / checkout
        '/carrinho': (context) => apenasCliente(const CartScreen()),
        '/revisar-pedido': (context) => apenasCliente(const ReviewOrderScreen()),
        '/entrega': (context) => apenasCliente(const DeliveryScreen()),
        '/pagamento': (context) => apenasCliente(const PaymentScreen()),
        '/checkout-ok': (context) => apenasCliente(const OrderConfirmationScreen()),

        // Pedidos
        '/pedidos': (context) => apenasCliente(const OrdersScreen()),

        // Perfil
        '/perfil': (context) => apenasCliente(const ProfileScreen()),
        '/editar-perfil': (context) => apenasCliente(const EditProfileScreen()),
        '/enderecos': (context) => apenasCliente(const AddressesScreen()),
        '/restricoes': (context) => apenasCliente(const RestrictionsScreen()),
        '/notificacoes': (context) => apenasCliente(const NotificationsScreen()),
        '/configuracoes': (context) => apenasCliente(const SettingsScreen()),

        // Admin
        '/admin': (context) => apenasAdmin(const AdminDashboardScreen()),
        '/admin-produtos': (context) => apenasAdmin(const AdminProductsScreen()),
        '/admin-pedidos': (context) => apenasAdmin(const AdminOrdersScreen()),
      },
      onGenerateRoute: (settings) {
        // As rotas abaixo exigem argumentos; o Flutter pode tentar
        // consultar '/' na inicializacao. Nao interceptamos '/' aqui.
        if (!const {'/detalhes', '/pedido-detalhes', '/rastreamento'}
            .contains(settings.name)) {
          return null;
        }
        // Uma URL antiga (por exemplo #/detalhes) nao pode abrir
        // uma tela de cliente depois que a sessao em memoria acaba.
        if (!state.isLoggedIn || state.isAdmin) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const LoginScreen(),
          );
        }
        switch (settings.name) {
          case '/detalhes':
            final product = settings.arguments as Product;
            return MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: product));
          case '/pedido-detalhes':
            final order = settings.arguments as Order;
            return MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order));
          case '/rastreamento':
            final order = settings.arguments as Order;
            return MaterialPageRoute(builder: (_) => OrderTrackingScreen(order: order));
        }
        return null;
      },
      ),
    );
  }
}
