import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../services/auth_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/ui_kit.dart';

/// Solicitação e redefinição de senha pela API própria da D'Vanille.
///
/// O link enviado pelo backend tem o formato:
/// http://localhost:8080/#/recuperar-senha?token=...
/// O fragmento não é enviado ao servidor que hospeda o Flutter Web.
class RecuperarSenhaPage extends StatefulWidget {
  const RecuperarSenhaPage({
    super.key,
    this.tokenInicial,
    this.abertoPorLink = false,
  });

  // Entregue pela navegação, caso o Flutter remova a query da URL.
  // Nunca registrar nem persistir este token.
  final String? tokenInicial;
  final bool abertoPorLink;

  @override
  State<RecuperarSenhaPage> createState() => _RecuperarSenhaPageState();
}

class _RecuperarSenhaPageState extends State<RecuperarSenhaPage> {
  final TextEditingController email = TextEditingController();
  final TextEditingController novaSenha = TextEditingController();
  final TextEditingController confirmarSenha = TextEditingController();
  final AuthApiService _api = AuthApiService();

  String? _token;
  bool _abertoPorLink = false;
  bool _solicitando = false;
  bool _redefinindo = false;
  bool enviado = false;
  bool redefinido = false;
  bool mostrarNovaSenha = false;
  bool mostrarConfirmacao = false;
  String? erroEmail;
  String? erroNovaSenha;
  String? erroConfirmacao;
  String? erroGeral;

  @override
  void initState() {
    super.initState();
    final link = _extrairTokenDoLink(Uri.base);
    _abertoPorLink = widget.abertoPorLink || link.$1;
    final candidato = widget.tokenInicial ?? link.$2;
    _token = candidato != null &&
            RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(candidato)
        ? candidato
        : null;
  }

  /// Retém apenas o token na memória, sem registrá-lo no Console.
  /// Aceita URL com fragmento (Flutter Web) ou query normal.
  (bool, String?) _extrairTokenDoLink(Uri uri) {
    final fragmento = Uri.tryParse(uri.fragment);
    final temTokenNoFragmento =
        fragmento?.queryParameters.containsKey('token') ?? false;
    final temTokenNaQuery = uri.queryParameters.containsKey('token');
    final existe = temTokenNoFragmento || temTokenNaQuery;
    final valor = (temTokenNoFragmento
            ? fragmento?.queryParameters['token']
            : uri.queryParameters['token'])
        ?.trim();
    // 32 bytes em Base64 URL sem padding = 43 caracteres.
    final valido = valor != null &&
        RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(valor);
    return (existe, valido ? valor : null);
  }

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get corDestaque =>
      isDark ? DVanilleColors.darkRose : DVanilleColors.rose;

  Color get corTexto => isDark ? DVanilleColors.darkInk : DVanilleColors.ink;

  Color get corTextoSecundario =>
      isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.darkTaupe;

  RedirecionamentoLogin? get redirecionamento {
    final argumento = ModalRoute.of(context)?.settings.arguments;
    if (argumento is RedirecionamentoLogin &&
        argumento.rota == Routes.comandaMesa) {
      return argumento;
    }
    return null;
  }

  bool get veioDaComanda => redirecionamento != null;

  bool _emailValido(String valor) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(valor.trim());

  Future<void> _enviar() async {
    if (_solicitando) return;
    final emailInformado = email.text.trim();
    if (emailInformado.isEmpty) {
      setState(() {
        erroEmail = 'Informe seu e-mail.';
        erroGeral = null;
      });
      return;
    }
    if (!_emailValido(emailInformado)) {
      setState(() {
        erroEmail = 'Digite um e-mail válido. Ex.: nome@email.com';
        erroGeral = null;
      });
      return;
    }

    setState(() {
      erroEmail = null;
      erroGeral = null;
      _solicitando = true;
    });
    try {
      // O servidor retorna mensagem genérica para evitar enumerar contas.
      await _api.solicitarRecuperacaoSenha(email: emailInformado);
      if (!mounted) return;
      setState(() => enviado = true);
    } on DVanilleApiException catch (e) {
      if (!mounted) return;
      setState(() => erroGeral = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => erroGeral =
          'Não foi possível solicitar a recuperação. Tente novamente.');
    } finally {
      if (mounted) setState(() => _solicitando = false);
    }
  }

  Future<void> _redefinirSenha() async {
    if (_redefinindo || _token == null) return;
    final senha = novaSenha.text;
    final confirmacao = confirmarSenha.text;
    String? erroSenha;
    String? erroConfirmar;

    // As mesmas regras do passwordRules do backend Node.js.
    if (senha.length < 8 || senha.length > 72 ||
        !RegExp(r'[A-Za-z]').hasMatch(senha) ||
        !RegExp(r'\d').hasMatch(senha)) {
      erroSenha = 'Use de 8 a 72 caracteres, com uma letra e um número.';
    }
    if (confirmacao.isEmpty) {
      erroConfirmar = 'Confirme a nova senha.';
    } else if (confirmacao != senha) {
      erroConfirmar = 'As senhas não coincidem.';
    }
    if (erroSenha != null || erroConfirmar != null) {
      setState(() {
        erroNovaSenha = erroSenha;
        erroConfirmacao = erroConfirmar;
        erroGeral = null;
      });
      return;
    }

    setState(() {
      erroNovaSenha = null;
      erroConfirmacao = null;
      erroGeral = null;
      _redefinindo = true;
    });
    try {
      await _api.redefinirSenha(token: _token!, novaSenha: senha);
      if (!mounted) return;
      novaSenha.clear();
      confirmarSenha.clear();
      setState(() {
        redefinido = true;
        _token = null; // Não reutilizar o token após sucesso.
      });
    } on DVanilleApiException catch (e) {
      if (!mounted) return;
      setState(() => erroGeral = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => erroGeral =
          'Não foi possível redefinir a senha. Tente novamente.');
    } finally {
      if (mounted) setState(() => _redefinindo = false);
    }
  }

  void _solicitarNovoLink() {
    setState(() {
      _abertoPorLink = false;
      _token = null;
      enviado = false;
      redefinido = false;
      erroGeral = null;
      erroEmail = null;
      erroNovaSenha = null;
      erroConfirmacao = null;
    });
    novaSenha.clear();
    confirmarSenha.clear();
  }

  void _voltarLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.login,
      (r) => false,
      arguments: redirecionamento,
    );
  }

  ButtonStyle get estiloBotao {
    return FilledButton.styleFrom(
      backgroundColor: isDark ? DVanilleColors.darkRose : DVanilleColors.rose,
      foregroundColor: isDark ? DVanilleColors.darkCream : DVanilleColors.white,
      minimumSize: const Size(190, 52),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      mostrarCabecalho: !veioDaComanda,
      mostrarRodape: !veioDaComanda,
      centralizarConteudo: veioDaComanda,
      child: ContentWidth(
        maxWidth: 480,
        child: _abertoPorLink
            ? (redefinido
                ? _sucessoRedefinicao()
                : _token == null
                    ? _linkInvalido()
                    : _formularioNovaSenha())
            : enviado
                ? _sucessoSolicitacao()
                : _formularioEmail(),
      ),
    );
  }

  Widget _titulo(String titulo, String descricao) {
    return Column(
      children: [
        Text(
          titulo,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'CreamCake',
            fontSize: 42,
            fontWeight: FontWeight.w400,
            color: corDestaque,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          descricao,
          textAlign: TextAlign.center,
          style: TextStyle(color: corTexto),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _formularioEmail() {
    return InfoBox(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _titulo('Recuperar senha',
              'Informe seu e-mail cadastrado para receber as instruções de recuperação.'),
          if (erroGeral != null) CaixaAlerta(erroGeral!),
          TextField(
            controller: email,
            enabled: !_solicitando,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            style: TextStyle(color: corTexto),
            onChanged: (_) {
              if (erroEmail != null) setState(() => erroEmail = null);
            },
            onSubmitted: (_) => _enviar(),
            decoration: InputDecoration(
              labelText: 'E-mail',
              hintText: 'nome@email.com',
              errorText: erroEmail,
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _solicitando ? null : _enviar,
              style: estiloBotao,
              child: _solicitando
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Enviar'),
            ),
          ),
          TextButton(
            onPressed: _solicitando ? null : _voltarLogin,
            child: const Text('Voltar ao login'),
          ),
        ],
      ),
    );
  }

  Widget _formularioNovaSenha() {
    return InfoBox(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _titulo('Nova senha',
              'Digite e confirme a nova senha da sua conta D\'Vanille.'),
          if (erroGeral != null) CaixaAlerta(erroGeral!),
          TextField(
            controller: novaSenha,
            enabled: !_redefinindo,
            obscureText: !mostrarNovaSenha,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) {
              if (erroNovaSenha != null) {
                setState(() => erroNovaSenha = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'Nova senha',
              errorText: erroNovaSenha,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: mostrarNovaSenha ? 'Ocultar senha' : 'Mostrar senha',
                onPressed: _redefinindo
                    ? null
                    : () => setState(() => mostrarNovaSenha = !mostrarNovaSenha),
                icon: Icon(mostrarNovaSenha
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Use de 8 a 72 caracteres, com pelo menos uma letra e um número.',
            style: TextStyle(color: corTextoSecundario, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: confirmarSenha,
            enabled: !_redefinindo,
            obscureText: !mostrarConfirmacao,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _redefinirSenha(),
            onChanged: (_) {
              if (erroConfirmacao != null) {
                setState(() => erroConfirmacao = null);
              }
            },
            decoration: InputDecoration(
              labelText: 'Confirmar nova senha',
              errorText: erroConfirmacao,
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              suffixIcon: IconButton(
                tooltip: mostrarConfirmacao
                    ? 'Ocultar confirmação'
                    : 'Mostrar confirmação',
                onPressed: _redefinindo
                    ? null
                    : () => setState(
                        () => mostrarConfirmacao = !mostrarConfirmacao),
                icon: Icon(mostrarConfirmacao
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _redefinindo ? null : _redefinirSenha,
              style: estiloBotao,
              child: _redefinindo
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Redefinir senha'),
            ),
          ),
          TextButton(
            onPressed: _redefinindo ? null : _solicitarNovoLink,
            child: const Text('Solicitar novo link'),
          ),
          TextButton(
            onPressed: _redefinindo ? null : _voltarLogin,
            child: const Text('Voltar ao login'),
          ),
        ],
      ),
    );
  }

  Widget _linkInvalido() {
    return InfoBox(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.link_off_outlined, size: 52),
          const SizedBox(height: 14),
          _titulo('Link inválido',
              'O link está incompleto ou inválido. Solicite um novo e-mail de recuperação.'),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _solicitarNovoLink,
              style: estiloBotao,
              child: const Text('Solicitar novo link'),
            ),
          ),
          TextButton(
            onPressed: _voltarLogin,
            child: const Text('Voltar ao login'),
          ),
        ],
      ),
    );
  }

  Widget _sucessoSolicitacao() {
    return InfoBox(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconeSucesso(),
          const SizedBox(height: 20),
          Text(
            'Solicitação realizada!',
            textAlign: TextAlign.center,
            style: AppTheme.display(size: 30, color: corTextoSecundario),
          ),
          const SizedBox(height: 10),
          Text(
            'Se o e-mail informado estiver cadastrado, você receberá '
            'as instruções para recuperar sua senha.',
            textAlign: TextAlign.center,
            style: TextStyle(color: corTexto),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _voltarLogin,
              style: estiloBotao,
              child: const Text('Voltar ao login'),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () {
              setState(() {
                enviado = false;
                erroEmail = null;
                erroGeral = null;
              });
            },
            child: const Text('Tentar outro e-mail'),
          ),
        ],
      ),
    );
  }

  Widget _sucessoRedefinicao() {
    return InfoBox(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const IconeSucesso(),
          const SizedBox(height: 20),
          Text(
            'Senha redefinida!',
            textAlign: TextAlign.center,
            style: AppTheme.display(size: 30, color: corTextoSecundario),
          ),
          const SizedBox(height: 12),
          Text(
            'Sua senha foi atualizada. Entre novamente usando a nova senha.',
            textAlign: TextAlign.center,
            style: TextStyle(color: corTexto),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _voltarLogin,
              style: estiloBotao,
              child: const Text('Ir para o login'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    email.dispose();
    novaSenha.dispose();
    confirmarSenha.dispose();
    _api.dispose();
    super.dispose();
  }
}

class IconeSucesso extends StatelessWidget {
  const IconeSucesso({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: isDark ? DVanilleColors.darkSurface : const Color(0xFFE4EEE0),
        shape: BoxShape.circle,
        border: isDark ? Border.all(color: DVanilleColors.darkBorder) : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.check,
        size: 40,
        color: isDark ? DVanilleColors.darkRose : const Color(0xFF3D6B3A),
      ),
    );
  }
}
