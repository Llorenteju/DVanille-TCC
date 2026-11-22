import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../services/app_state.dart';
import '../../services/navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/ui_kit.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final senha = TextEditingController();

  String? erro;
  bool mostrarSenha = false;
  bool entrando = false;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get corDestaque =>
      isDark ? DVanilleColors.darkRose : DVanilleColors.rose;

  Color get corSubtitulo =>
      isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.darkTaupe;

  // Identifica se o login foi aberto a partir da comanda.
  RedirecionamentoLogin? get redirecionamento {
    final argumento = ModalRoute.of(context)?.settings.arguments;

    if (argumento is RedirecionamentoLogin &&
        argumento.rota == Routes.comandaMesa) {
      return argumento;
    }

    return null;
  }

  bool get veioDaComanda => redirecionamento != null;

  @override
  void dispose() {
    email.dispose();
    senha.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (entrando) return;

    if (email.text.trim().isEmpty || senha.text.isEmpty) {
      setState(() => erro = 'Informe seu e-mail e sua senha.');
      return;
    }

    setState(() {
      entrando = true;
      erro = null;
    });

    // Login de verdade: POST /api/auth/login (backend Node.js).
    final mensagem = await AppState.instance.loginComApi(
      email.text,
      senha.text,
    );

    if (!mounted) return;
    setState(() => entrando = false);

    if (mensagem != null) {
      setState(() => erro = mensagem);
      return;
    }

    showToast('Login realizado com sucesso!', 'palmas.svg');

    final arg = ModalRoute.of(context)?.settings.arguments;
    final navigator = Navigator.of(context);

    if (arg is RedirecionamentoLogin) {
      navigator.pushNamedAndRemoveUntil(
        arg.rota,
        (r) => false,
        arguments: arg.argumentos,
      );
      return;
    }

    navigator.pushNamedAndRemoveUntil(
      AppState.instance.isAdmin ? Routes.admin : Routes.home,
      (r) => false,
    );
  }

  void _abrirPaginaAutenticacao(String rota) {
    if (entrando) return;
    Navigator.pushNamed(
      context,
      rota,
      arguments: redirecionamento,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      mostrarCabecalho: !veioDaComanda,
      mostrarRodape: !veioDaComanda,
      child: Column(
        children: [
          const SizedBox(height: 56),
          ContentWidth(
            maxWidth: 480,
            child: InfoBox(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Text(
                    'Bem-vindo de volta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'CreamCake',
                      fontSize: 42,
                      fontWeight: FontWeight.w400,
                      color: corDestaque,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Entrar',
                    textAlign: TextAlign.center,
                    style: AppTheme.display(
                      size: 26,
                      weight: FontWeight.w600,
                      color: corSubtitulo,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 28),
                  if (erro != null) CaixaAlerta(erro!),
                  TextField(
                    controller: email,
                    enabled: !entrando,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: senha,
                    enabled: !entrando,
                    obscureText: !mostrarSenha,
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Senha',
                      suffixIcon: IconButton(
                        tooltip:
                            mostrarSenha ? 'Ocultar senha' : 'Mostrar senha',
                        onPressed: entrando
                            ? null
                            : () => setState(() {
                                  mostrarSenha = !mostrarSenha;
                                }),
                        icon: Icon(
                          mostrarSenha
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: entrando ? null : _entrar,
                      style: isDark
                          ? FilledButton.styleFrom(
                              backgroundColor: DVanilleColors.darkRose,
                              foregroundColor: DVanilleColors.darkCream,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                      child: entrando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: entrando
                        ? null
                        : () => _abrirPaginaAutenticacao(Routes.recuperarSenha),
                    child: const Text('Esqueci minha senha'),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Ainda não tem conta?'),
                      TextButton(
                        onPressed: entrando
                            ? null
                            : () => _abrirPaginaAutenticacao(Routes.cadastro),
                        child: const Text('Criar conta'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
