import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../data/mock_data.dart';
import '../../services/app_state.dart';
import '../../services/reserva_api_service.dart';
import '../../services/auth_api_service.dart' show DVanilleApiException;
import '../../models/reserva.dart';
import '../../services/navigation.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/ui_kit.dart';
import '../../theme/app_theme.dart';

class ReservasPage extends StatefulWidget {
  const ReservasPage({super.key});

  @override
  State<ReservasPage> createState() => _ReservasPageState();
}

class _ReservasPageState extends State<ReservasPage> {
  final state = AppState.instance;

  final formularioKey = GlobalKey<FormState>();

  late final TextEditingController nome;
  late final TextEditingController email;
  late final TextEditingController telefone;

  final pessoas = TextEditingController(text: '2');
  final preferencias = TextEditingController();
  final observacoes = TextEditingController();

  DateTime? data;
  String horario = horariosReserva.first;

  bool tentouEnviar = false;
  bool _salvando = false;

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  Color get corTitulo => isDark ? DVanilleColors.darkRose : DVanilleColors.rose;

  Color get corSubtitulo =>
      isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.darkTaupe;

  Color get corTexto => isDark ? DVanilleColors.darkInk : DVanilleColors.ink;

  Color get corTextoSecundario =>
      isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.taupe;

  @override
  void initState() {
    super.initState();

    final u = state.usuarioLogado;

    nome = TextEditingController(
      text: u?.nome ?? '',
    );

    email = TextEditingController(
      text: u?.email ?? '',
    );

    telefone = TextEditingController(
      text: u?.telefone ?? '',
    );
  }

  @override
  void dispose() {
    nome.dispose();
    email.dispose();
    telefone.dispose();
    pessoas.dispose();
    preferencias.dispose();
    observacoes.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final hoje = DateTime.now();

    final escolhida = await showDatePicker(
      context: context,
      initialDate: data ?? hoje,
      firstDate: DateTime(
        hoje.year,
        hoje.month,
        hoje.day,
      ),
      lastDate: DateTime(
        hoje.year + 2,
      ),
      helpText: 'Selecione a data da reserva',
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

    if (escolhida != null) {
      setState(() {
        data = escolhida;
      });
    }
  }

  String? _validarObrigatorio(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Campo obrigatório';
    }

    return null;
  }

  String? _validarEmail(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Campo obrigatório';
    }

    final emailDigitado = valor.trim();

    final emailValido = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(emailDigitado);

    if (!emailValido) {
      return 'Informe um e-mail válido';
    }

    return null;
  }

  String? _validarTelefone(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Campo obrigatório';
    }

    final numeros = valor.replaceAll(
      RegExp(r'\D'),
      '',
    );

    if (numeros.length != 11) {
      return 'Informe um telefone com 11 números';
    }

    if (numeros[2] != '9') {
      return 'Informe um celular válido';
    }

    return null;
  }

  String? _validarPessoas(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Campo obrigatório';
    }

    final quantidade = int.tryParse(
      valor.trim(),
    );

    if (quantidade == null || quantidade < 1) {
      return 'Informe uma quantidade válida';
    }

    return null;
  }

  Future<void> _solicitar() async {
    FocusScope.of(context).unfocus();

    setState(() {
      tentouEnviar = true;
    });

    final valido = formularioKey.currentState?.validate() ?? false;

    if (!valido) {
      return;
    }

    if (data == null) {
      return;
    }

    final hoje = DateTime.now();

    final hojeSemHorario = DateTime(
      hoje.year,
      hoje.month,
      hoje.day,
    );

    if (data!.isBefore(hojeSemHorario)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A data da reserva não pode ser no passado.',
          ),
        ),
      );

      return;
    }

    final quantidade = int.tryParse(
          pessoas.text.trim(),
        ) ??
        0;

    if (quantidade < 1) {
      return;
    }

    if (_salvando) return;
    if (!state.podeFazerReserva) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppState.avisoContaAdministrativa)),
      );
      return;
    }
    setState(() => _salvando = true);
    try {
      final Reserva reserva = await ReservaApiService.instance.criar(
        nome: nome.text.trim(),
        email: email.text.trim(),
        telefone: telefone.text.trim(),
        data: _formatarData(data!),
        horario: horario,
        pessoas: quantidade,
        preferencias: preferencias.text.trim(),
        observacoes: observacoes.text.trim(),
      );
      if (!mounted) return;
      showToast('Solicitação de reserva enviada!', 'agenda.svg');
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.reservaConfirmada,
        (rota) => false,
        arguments: reserva,
      );
    } on DVanilleApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível enviar a reserva. Tente novamente.')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  String _formatarData(DateTime data) {
    return '${data.year}-'
        '${data.month.toString().padLeft(2, '0')}-'
        '${data.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final estreito = MediaQuery.sizeOf(context).width < 720;

    final erroData = tentouEnviar && data == null ? 'Campo obrigatório' : null;

    return PageShell(
      child: Column(
        children: [
          const SizedBox(height: 56),

          // TÍTULO

          ContentWidth(
            child: Column(
              children: [
                Text(
                  'Fazer uma reserva',
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
                  'Garanta seu lugar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    color: corSubtitulo,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // BOTÃO MINHAS RESERVAS

          OutlinedButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                Routes.minhasReservas,
              );
            },
            icon: const Icon(
              Icons.calendar_month_outlined,
              size: 20,
            ),
            label: const Text(
              'Minhas reservas',
            ),
          ),

          const SizedBox(height: 16),
          ContentWidth(
            maxWidth: 760,
            child: Text(
              'Sua reserva será enviada para análise. O horário só estará confirmado após aprovação da cafeteria.',
              textAlign: TextAlign.center,
              style: TextStyle(color: corTextoSecundario, fontSize: 13),
            ),
          ),
          const SizedBox(height: 25),

          // FORMULÁRIO

          ContentWidth(
            maxWidth: 760,
            child: Form(
              key: formularioKey,
              child: InfoBox(
                padding: const EdgeInsets.all(30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // NOME + E-MAIL

                    _par(
                      estreito,
                      [
                        TextFormField(
                          controller: nome,
                          validator: _validarObrigatorio,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          style: TextStyle(color: corTexto),
                          decoration: const InputDecoration(
                            labelText: 'Nome *',
                          ),
                        ),
                        TextFormField(
                          controller: email,
                          keyboardType: TextInputType.emailAddress,
                          validator: _validarEmail,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          style: TextStyle(color: corTexto),
                          decoration: const InputDecoration(
                            labelText: 'E-mail *',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // TELEFONE + QUANTIDADE

                    _par(
                      estreito,
                      [
                        TextFormField(
                          controller: telefone,
                          keyboardType: TextInputType.phone,
                          validator: _validarTelefone,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          style: TextStyle(color: corTexto),
                          decoration: const InputDecoration(
                            labelText: 'Telefone *',
                            hintText: '(11) 98765-4321',
                          ),
                        ),
                        TextFormField(
                          controller: pessoas,
                          keyboardType: TextInputType.number,
                          validator: _validarPessoas,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          style: TextStyle(color: corTexto),
                          decoration: const InputDecoration(
                            labelText: 'Quantidade de pessoas *',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // DATA + HORÁRIO

                    _par(
                      estreito,
                      [
                        InkWell(
                          onTap: _escolherData,
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Data *',
                              suffixIcon: const Icon(
                                Icons.calendar_today,
                                size: 18,
                              ),
                              errorText: erroData,
                            ),
                            child: Text(
                              data == null
                                  ? 'Selecione uma data'
                                  : '${data!.day.toString().padLeft(2, '0')}/'
                                      '${data!.month.toString().padLeft(2, '0')}/'
                                      '${data!.year}',
                              style: TextStyle(
                                color: data == null
                                    ? corTextoSecundario
                                    : corTexto,
                              ),
                            ),
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: horario,
                          decoration: const InputDecoration(
                            labelText: 'Horário *',
                          ),
                          items: horariosReserva
                              .map(
                                (horario) => DropdownMenuItem<String>(
                                  value: horario,
                                  child: Text(horario),
                                ),
                              )
                              .toList(),
                          onChanged: (valor) {
                            if (valor == null) {
                              return;
                            }

                            setState(() {
                              horario = valor;
                            });
                          },
                          validator: (valor) {
                            if (valor == null || valor.trim().isEmpty) {
                              return 'Campo obrigatório';
                            }

                            return null;
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // PREFERÊNCIAS — OPCIONAL

                    TextFormField(
                      controller: preferencias,
                      style: TextStyle(color: corTexto),
                      decoration: const InputDecoration(
                        labelText: 'Preferências de produtos',
                        hintText:
                            'Ex: mesa perto da janela, produtos sem glúten...',
                      ),
                    ),

                    const SizedBox(height: 14),

                    // INFORMAÇÕES ADICIONAIS — OPCIONAL

                    TextFormField(
                      controller: observacoes,
                      maxLines: 3,
                      style: TextStyle(color: corTexto),
                      decoration: const InputDecoration(
                        labelText: 'Informações adicionais',
                        hintText: 'Digite alguma informação importante...',
                      ),
                    ),

                    const SizedBox(height: 22),

                    // BOTÃO

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _salvando ? null : _solicitar,
                        child: Text(_salvando ? 'Enviando...' : 'Solicitar reserva'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 56),
        ],
      ),
    );
  }

  Widget _par(
    bool estreito,
    List<Widget> filhos,
  ) {
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
        Expanded(
          child: filhos[0],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: filhos[1],
        ),
      ],
    );
  }
}
