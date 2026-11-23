import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;

import '../../services/auth_api_service.dart';

import '../../app/app.dart';
import '../../data/mock_data.dart';
import '../../services/app_state.dart';
import '../../services/navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/ui_kit.dart';

class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key});

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  final state = AppState.instance;

  late final TextEditingController nome;
  late final TextEditingController email;
  late final TextEditingController telefone;
  late final TextEditingController endereco;
  late final TextEditingController dataNascimento;

  final senhaAtual = TextEditingController();
  final novaSenha = TextEditingController();
  final confirmarSenha = TextEditingController();

  late Set<String> restricoes;

  DateTime? dataNascimentoSelecionada;
  late bool notificacoes;

  bool mostrarSenhaAtual = false;
  bool mostrarNovaSenha = false;
  bool mostrarConfirmacao = false;

  String? mensagem;
  bool mensagemSucesso = false;
  bool carregandoPreferencias = false;
  bool preferenciasCarregadas = false;
  bool salvando = false;
  bool apagando = false;
  bool autorizouDadosAlimentares = false;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get corTitulo => isDark ? DVanilleColors.darkRose : DVanilleColors.rose;

  Color get corSecao =>
      isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.darkTaupe;

  Color get corTexto => isDark ? DVanilleColors.darkInk : DVanilleColors.ink;

  Color get corTextoSecundario =>
      isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.taupe;

  Color get corChipSelecionado =>
      isDark ? DVanilleColors.darkSurface : DVanilleColors.blush;

  Color get corCheck =>
      isDark ? DVanilleColors.darkRose : DVanilleColors.darkTaupe;

  @override
  void initState() {
    super.initState();

    final u = state.usuarioLogado;

    nome = TextEditingController(text: u?.nome ?? '');
    email = TextEditingController(text: u?.email ?? '');
    telefone = TextEditingController(text: u?.telefone ?? '');
    endereco = TextEditingController(text: u?.endereco ?? '');

    dataNascimentoSelecionada = u?.dataNascimento;

    dataNascimento = TextEditingController(
      text: u?.dataNascimento == null ? '' : _formatarData(u!.dataNascimento!),
    );

    restricoes = {...?u?.restricoes};
    notificacoes = u?.notificacoes ?? false;

    if (u != null && !u.isAdmin && state.logadoPelaApi) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _carregarPreferencias();
      });
    }
  }

  Future<void> _carregarPreferencias() async {
    if (carregandoPreferencias) return;
    final id = state.usuarioLogado?.id;
    setState(() {
      carregandoPreferencias = true;
      preferenciasCarregadas = false;
      mensagem = null;
    });
    try {
      await state.carregarPreferenciasUsuarioApi();
      if (!mounted || id != state.usuarioLogado?.id) return;
      final usuario = state.usuarioLogado;
      setState(() {
        restricoes = {...?usuario?.restricoes};
        notificacoes = usuario?.notificacoes ?? false;
        dataNascimentoSelecionada = usuario?.dataNascimento;
        dataNascimento.text = usuario?.dataNascimento == null
            ? ''
            : _formatarData(usuario!.dataNascimento!);
        autorizouDadosAlimentares = false;
        preferenciasCarregadas = true;
      });
    } on DVanilleApiException catch (e) {
      if (mounted)
        _mostrarMensagem(
          'Não foi possível carregar suas preferências: ${e.message}. '
          'Tente novamente antes de salvar.',
        );
    } catch (_) {
      if (mounted)
        _mostrarMensagem(
          'Não foi possível consultar as preferências. Tente novamente.',
        );
    } finally {
      if (mounted) setState(() => carregandoPreferencias = false);
    }
  }

  @override
  void dispose() {
    nome.dispose();
    email.dispose();
    telefone.dispose();
    endereco.dispose();
    dataNascimento.dispose();
    senhaAtual.dispose();
    novaSenha.dispose();
    confirmarSenha.dispose();
    super.dispose();
  }

  String _doisDigitos(int valor) {
    return valor.toString().padLeft(2, '0');
  }

  String _formatarData(DateTime data) {
    return '${_doisDigitos(data.day)}/'
        '${_doisDigitos(data.month)}/'
        '${data.year}';
  }

  void _mostrarMensagem(String texto) {
    setState(() {
      mensagem = texto;
      mensagemSucesso = false;
    });
  }

  Future<void> _selecionarDataNascimento() async {
    final hoje = DateTime.now();

    final selecionada = await showDatePicker(
      context: context,
      initialDate: dataNascimentoSelecionada ?? hoje,
      firstDate: DateTime(1900),
      lastDate: hoje,
      helpText: 'Selecione sua data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: isDark
                ? const ColorScheme.dark(
                    primary: DVanilleColors.darkRose,
                    onPrimary: DVanilleColors.darkInk,
                    surface: DVanilleColors.darkSurface,
                    onSurface: DVanilleColors.darkInk,
                  )
                : const ColorScheme.light(
                    primary: DVanilleColors.rose,
                    onPrimary: Colors.white,
                    surface: DVanilleColors.cream,
                    onSurface: DVanilleColors.ink,
                  ),
          ),
          child: child!,
        );
      },
    );

    if (selecionada == null || !mounted) {
      return;
    }

    setState(() {
      dataNascimentoSelecionada = selecionada;
      dataNascimento.text = _formatarData(selecionada);
      mensagem = null;
    });
  }

  String _chaveData(DateTime? data) {
    if (data == null) return '';
    return '${data.year}-${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
  }

  Future<void> _salvar() async {
    if (salvando || apagando || carregandoPreferencias) return;
    final usuario = state.usuarioLogado;
    if (usuario == null || !state.logadoPelaApi) {
      _mostrarMensagem('Entre novamente na sua conta para editar o perfil.');
      return;
    }

    final isAdmin = usuario.isAdmin;
    if (!isAdmin && !preferenciasCarregadas) {
      _mostrarMensagem('Carregue suas preferências antes de salvar.');
      return;
    }
    final nomeNovo = nome.text.trim();
    final telefoneNovo = telefone.text.trim();
    if (nomeNovo.length < 2) {
      _mostrarMensagem('Informe um nome com pelo menos 2 caracteres.');
      return;
    }
    if (!isAdmin && !RegExp(r'^[\d()+\-\s]{8,20}$').hasMatch(telefoneNovo)) {
      _mostrarMensagem('Informe um telefone válido (8 a 20 caracteres).');
      return;
    }
    if (email.text.trim().toLowerCase() != usuario.email.toLowerCase() ||
        endereco.text.trim() != usuario.endereco.trim()) {
      _mostrarMensagem(
          'Nesta etapa, e-mail e endereço não podem ser alterados no servidor.');
      return;
    }

    final querAlterarSenha = senhaAtual.text.isNotEmpty ||
        novaSenha.text.isNotEmpty ||
        confirmarSenha.text.isNotEmpty;
    if (querAlterarSenha) {
      if (senhaAtual.text.isEmpty ||
          novaSenha.text.isEmpty ||
          confirmarSenha.text.isEmpty) {
        _mostrarMensagem('Preencha senha atual, nova senha e confirmação.');
        return;
      }
      if (novaSenha.text != confirmarSenha.text) {
        _mostrarMensagem('A confirmação não coincide com a nova senha.');
        return;
      }
      if (!AppState.senhaValida(novaSenha.text)) {
        _mostrarMensagem('A nova senha deve ter entre 8 e 72 caracteres, '
            'com letra maiúscula, número e caractere especial.');
        return;
      }
      if (senhaAtual.text == novaSenha.text) {
        _mostrarMensagem('A nova senha deve ser diferente da senha atual.');
        return;
      }
    }

    final dadosAlterados = nomeNovo != usuario.nome ||
        (!isAdmin && telefoneNovo != usuario.telefone);
    final preferenciasAlteradas = !isAdmin &&
        (_chaveData(dataNascimentoSelecionada) !=
                _chaveData(usuario.dataNascimento) ||
            !setEquals(restricoes, usuario.restricoes.toSet()) ||
            notificacoes != usuario.notificacoes);
    final temDadosAlimentares = restricoes.any((r) => r != 'nenhuma');
    if (preferenciasAlteradas &&
        temDadosAlimentares &&
        !autorizouDadosAlimentares) {
      _mostrarMensagem('Autorize o armazenamento das opções alimentares '
          'selecionadas ou desmarque-as antes de salvar.');
      return;
    }
    if (!dadosAlterados && !preferenciasAlteradas && !querAlterarSenha) {
      _mostrarMensagem('Não há alterações para salvar.');
      return;
    }

    setState(() {
      salvando = true;
      mensagem = null;
    });
    var gravacoes = 0;
    try {
      if (dadosAlterados) {
        await state.atualizarDadosPessoaisApi(
          nome: nomeNovo,
          telefone: isAdmin ? usuario.telefone : telefoneNovo,
        );
        gravacoes++;
      }
      if (preferenciasAlteradas) {
        await state.salvarPreferenciasUsuarioApi(
          dataNascimento: dataNascimentoSelecionada,
          restricoes: restricoes.toList(),
          notificacoes: notificacoes,
        );
        gravacoes++;
      }
      if (querAlterarSenha) {
        await state.alterarSenhaUsuarioApi(
          senhaAtual: senhaAtual.text,
          novaSenha: novaSenha.text,
        );
        gravacoes++;
      }
      if (!mounted) return;
      senhaAtual.clear();
      novaSenha.clear();
      confirmarSenha.clear();
      setState(() {
        autorizouDadosAlimentares = false;
        mensagem = 'Dados atualizados com sucesso!';
        mensagemSucesso = true;
      });
      showToast('Perfil atualizado!', '✓');
    } on DVanilleApiException catch (e) {
      if (mounted) {
        final aviso = gravacoes > 0
            ? ' Algumas alterações anteriores foram salvas. '
                'Confira os dados antes de tentar novamente.'
            : '';
        _mostrarMensagem('${e.message}$aviso');
      }
    } catch (_) {
      if (mounted) {
        final aviso =
            gravacoes > 0 ? ' Algumas alterações podem ter sido salvas.' : '';
        _mostrarMensagem('Não foi possível concluir a atualização.$aviso');
      }
    } finally {
      if (mounted) setState(() => salvando = false);
    }
  }

  Future<void> _apagarPreferencias() async {
    if (apagando ||
        salvando ||
        carregandoPreferencias ||
        !preferenciasCarregadas) return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar preferências pessoais?'),
        content: const Text(
          'Isso apaga suas opções alimentares, data de nascimento e '
          'preferência de notificações armazenadas no servidor. '
          'Sua conta continuará ativa.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apagar preferências')),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    setState(() {
      apagando = true;
      mensagem = null;
    });
    try {
      await state.apagarPreferenciasUsuarioApi();
      if (!mounted) return;
      setState(() {
        restricoes.clear();
        notificacoes = false;
        autorizouDadosAlimentares = false;
        dataNascimentoSelecionada = null;
        dataNascimento.clear();
        mensagem = 'Preferências apagadas com sucesso!';
        mensagemSucesso = true;
      });
    } on DVanilleApiException catch (e) {
      if (mounted) _mostrarMensagem(e.message);
    } catch (_) {
      if (mounted) _mostrarMensagem('Não foi possível apagar as preferências.');
    } finally {
      if (mounted) setState(() => apagando = false);
    }
  }

  Widget _campo(
    TextEditingController controller,
    String label, {
    TextInputType tipo = TextInputType.text,
    bool somenteLeitura = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: somenteLeitura,
      keyboardType: tipo,
      style: TextStyle(color: corTexto),
      onChanged: (_) {
        if (mensagem != null) {
          setState(() {
            mensagem = null;
          });
        }
      },
      decoration: InputDecoration(
        labelText: label,
      ),
    );
  }

  Widget _campoSenha({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool mostrar,
    required VoidCallback alternarVisibilidade,
  }) {
    return TextField(
      controller: controller,
      obscureText: !mostrar,
      autofillHints: const [AutofillHints.password],
      style: TextStyle(color: corTexto),
      onChanged: (_) {
        if (mensagem != null) {
          setState(() {
            mensagem = null;
          });
        }
      },
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: IconButton(
          tooltip: mostrar ? 'Ocultar senha' : 'Mostrar senha',
          onPressed: alternarVisibilidade,
          icon: Icon(
            mostrar ? Icons.visibility_off : Icons.visibility,
          ),
        ),
      ),
    );
  }

  Widget _tituloSecao(String texto) {
    return Text(
      texto,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: corSecao,
      ),
    );
  }

  Widget _textoAuxiliar(String texto) {
    return Text(
      texto,
      style: TextStyle(
        fontSize: 13,
        color: corTextoSecundario,
      ),
    );
  }

  Widget _informacao(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              titulo,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: corTextoSecundario,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(color: corTexto),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linha(bool estreito, List<Widget> filhos) {
    if (estreito) {
      return Column(
        children: [
          filhos[0],
          const SizedBox(height: 14),
          filhos[1],
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: filhos[0]),
        const SizedBox(width: 14),
        Expanded(child: filhos[1]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final estreito = MediaQuery.sizeOf(context).width < 720;
    final usuario = state.usuarioLogado;

    // Identifica a conta administrativa.
    final isAdmin = state.isAdmin || usuario?.tipo == 'admin';

    // Somente as 14 opções pessoais aceitas pela API.
    // NÃO mesclar filtros nutricionais de produtos nesta lista.
    final labelsRestricoes = <String, String>{
      for (final opcao in opcoesRestricaoCadastro) opcao[0]: opcao[1],
    };

    return PageShell(
      // O perfil usa o mesmo cabeçalho e rodapé públicos para os dois tipos
      // de conta. O painel administrativo continua usando o AdminShell.
      activeRoute: Routes.perfil,
      child: Column(
        children: [
          const SizedBox(height: 56),

          // TÍTULO
          ContentWidth(
            child: Column(
              children: [
                Text(
                  'Meu perfil',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'CreamCake',
                    fontSize: 48,
                    fontWeight: FontWeight.w400,
                    color: corTitulo,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isAdmin ? 'Conta administrativa' : 'Minha conta',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: corSecao,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          // FORMULÁRIO
          ContentWidth(
            maxWidth: 760,
            child: InfoBox(
              padding: const EdgeInsets.all(30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (mensagem != null) ...[
                    CaixaAlerta(
                      mensagem!,
                      erro: !mensagemSucesso,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // DADOS PESSOAIS
                  _tituloSecao(isAdmin ? 'Dados da conta' : 'Dados pessoais'),
                  const SizedBox(height: 14),

                  _linha(estreito, [
                    _campo(nome, 'Nome completo *'),
                    _campo(
                      email,
                      'E-mail (não editável nesta etapa)',
                      tipo: TextInputType.emailAddress,
                      somenteLeitura: true,
                    ),
                  ]),

                  if (!isAdmin) ...[
                    const SizedBox(height: 14),
                    _linha(estreito, [
                      _campo(
                        telefone,
                        'Telefone *',
                        tipo: TextInputType.phone,
                      ),
                      TextField(
                        controller: dataNascimento,
                        readOnly: true,
                        onTap: preferenciasCarregadas && !salvando && !apagando
                            ? _selecionarDataNascimento
                            : null,
                        style: TextStyle(color: corTexto),
                        decoration: InputDecoration(
                          labelText: 'Data de nascimento (opcional)',
                          hintText: 'dd/mm/aaaa',
                          suffixIcon: IconButton(
                            tooltip: 'Limpar data de nascimento',
                            onPressed:
                                preferenciasCarregadas && !salvando && !apagando
                                    ? () => setState(() {
                                          dataNascimentoSelecionada = null;
                                          dataNascimento.clear();
                                          mensagem = null;
                                        })
                                    : null,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    TextField(
                      controller: endereco,
                      readOnly: true,
                      style: TextStyle(color: corTextoSecundario),
                      decoration: const InputDecoration(
                        labelText: 'Endereço (integração futura)',
                        hintText: 'Ainda não disponível para edição',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _textoAuxiliar(
                      'E-mail e endereço ainda não podem ser alterados nesta integração. '
                      'Nome e telefone são salvos no servidor.',
                    ),
                  ],

                  const SizedBox(height: 24),

                  // SEGURANÇA DA CONTA
                  _tituloSecao('Segurança da conta'),
                  const SizedBox(height: 8),

                  _textoAuxiliar(
                    'Para trocar sua senha, confirme a senha atual '
                    'e informe a nova senha duas vezes.',
                  ),

                  const SizedBox(height: 14),

                  _campoSenha(
                    controller: senhaAtual,
                    label: 'Senha atual',
                    hint: 'Obrigatória para trocar a senha',
                    mostrar: mostrarSenhaAtual,
                    alternarVisibilidade: () {
                      setState(() {
                        mostrarSenhaAtual = !mostrarSenhaAtual;
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  _campoSenha(
                    controller: novaSenha,
                    label: 'Nova senha (opcional)',
                    hint: 'Deixe em branco para manter a atual',
                    mostrar: mostrarNovaSenha,
                    alternarVisibilidade: () {
                      setState(() {
                        mostrarNovaSenha = !mostrarNovaSenha;
                      });
                    },
                  ),

                  const SizedBox(height: 14),

                  _campoSenha(
                    controller: confirmarSenha,
                    label: 'Confirmar nova senha',
                    hint: 'Digite novamente a nova senha',
                    mostrar: mostrarConfirmacao,
                    alternarVisibilidade: () {
                      setState(() {
                        mostrarConfirmacao = !mostrarConfirmacao;
                      });
                    },
                  ),

                  const SizedBox(height: 8),

                  DicaCampo(
                    'A senha deve ter entre 8 e 72 caracteres, '
                    'com letra maiúscula, número e caractere especial.',
                  ),

                  const SizedBox(height: 24),

                  if (!isAdmin) ...[
                    // PREFERÊNCIAS PESSOAIS PRIVADAS
                    if (carregandoPreferencias)
                      const Center(child: CircularProgressIndicator()),
                    if (!preferenciasCarregadas && !carregandoPreferencias)
                      TextButton.icon(
                        onPressed: _carregarPreferencias,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tentar carregar preferências'),
                      ),
                    _tituloSecao('Preferências alimentares (opcional)'),
                    const SizedBox(height: 8),

                    _textoAuxiliar(
                      'Essas opções podem revelar condições de saúde. '
                      'Você decide se deseja fornecê-las e pode apagá-las '
                      'a qualquer momento. Elas não garantem a segurança dos produtos.',
                    ),

                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: labelsRestricoes.entries.map((e) {
                        final ativo = restricoes.contains(e.key);

                        return FilterChip(
                          label: Text(e.value),
                          selected: ativo,
                          selectedColor: corChipSelecionado,
                          checkmarkColor: corCheck,
                          labelStyle: TextStyle(
                            color: ativo ? corTexto : corTextoSecundario,
                          ),
                          side: BorderSide(
                            color: isDark
                                ? DVanilleColors.darkBorder
                                : DVanilleColors.line,
                          ),
                          onSelected:
                              preferenciasCarregadas && !salvando && !apagando
                                  ? (valor) {
                                      setState(() {
                                        if (valor) {
                                          if (e.key == 'nenhuma') {
                                            restricoes
                                              ..clear()
                                              ..add('nenhuma');
                                          } else {
                                            restricoes
                                              ..remove('nenhuma')
                                              ..add(e.key);
                                          }
                                        } else {
                                          restricoes.remove(e.key);
                                        }

                                        mensagem = null;
                                        if (restricoes.isEmpty ||
                                            restricoes.contains('nenhuma')) {
                                          autorizouDadosAlimentares = false;
                                        }
                                      });
                                    }
                                  : null,
                        );
                      }).toList(),
                    ),

                    if (restricoes.any((r) => r != 'nenhuma')) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: autorizouDadosAlimentares,
                        onChanged: preferenciasCarregadas &&
                                !salvando &&
                                !apagando
                            ? (valor) => setState(() {
                                  autorizouDadosAlimentares = valor ?? false;
                                  mensagem = null;
                                })
                            : null,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: corCheck,
                        title: Text(
                          'Autorizo salvar ou atualizar estas opções alimentares '
                          'na minha conta.',
                          style: TextStyle(fontSize: 13, color: corTexto),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // NOTIFICAÇÕES
                    _tituloSecao('Preferências'),
                    const SizedBox(height: 8),

                    CheckboxListTile(
                      value: notificacoes,
                      onChanged:
                          preferenciasCarregadas && !salvando && !apagando
                              ? (valor) {
                                  setState(() {
                                    notificacoes = valor ?? false;
                                    mensagem = null;
                                  });
                                }
                              : null,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      activeColor: corCheck,
                      checkColor:
                          isDark ? DVanilleColors.darkCream : Colors.white,
                      title: Text(
                        'Desejo receber notificações de ofertas e novidades',
                        style: TextStyle(
                          fontSize: 14,
                          color: corTexto,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          preferenciasCarregadas && !salvando && !apagando
                              ? _apagarPreferencias
                              : null,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Apagar minhas preferências pessoais'),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Divider(
                    color: isDark
                        ? DVanilleColors.darkBorder
                        : DVanilleColors.line,
                  ),

                  const SizedBox(height: 12),

                  // INFORMAÇÕES DA CONTA
                  _tituloSecao('Informações da conta'),
                  const SizedBox(height: 12),

                  _informacao(
                    'Tipo de conta',
                    isAdmin ? 'Administrador' : 'Cliente',
                  ),

                  if (!isAdmin)
                    _informacao(
                      'Data de nascimento',
                      dataNascimento.text.isEmpty
                          ? 'Não informada'
                          : dataNascimento.text,
                    ),

                  const SizedBox(height: 24),

                  // AÇÕES
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton(
                        onPressed: (salvando ||
                                apagando ||
                                carregandoPreferencias ||
                                (!isAdmin && !preferenciasCarregadas))
                            ? null
                            : _salvar,
                        child: salvando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Salvar alterações'),
                      ),
                      if (!isAdmin) ...[
                        OutlinedButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            Routes.meusValesPresente,
                          ),
                          child: const Text('Meus vales-presente'),
                        ),
                        OutlinedButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            Routes.minhasReservas,
                          ),
                          child: const Text('Minhas reservas'),
                        ),
                      ],
                      if (isAdmin)
                        OutlinedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pushNamedAndRemoveUntil(
                            Routes.admin,
                            (r) => false,
                          ),
                          icon: const Icon(Icons.admin_panel_settings_outlined),
                          label: const Text('Voltar ao painel Admin'),
                        ),
                      TextButton(
                        onPressed: () {
                          state.logout();

                          showToast('Você saiu da sua conta.', '👋');

                          Navigator.of(context).pushNamedAndRemoveUntil(
                            Routes.home,
                            (r) => false,
                          );
                        },
                        child: const Text('Sair da conta'),
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
