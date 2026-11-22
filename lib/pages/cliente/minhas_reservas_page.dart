import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/app.dart';
import '../../models/reserva.dart';
import '../../services/reserva_api_service.dart';
import '../../services/auth_api_service.dart' show DVanilleApiException;
import '../../services/navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/ui_kit.dart';

class MinhasReservasPage extends StatefulWidget {
  const MinhasReservasPage({super.key});

  @override
  State<MinhasReservasPage> createState() => _MinhasReservasPageState();
}

class _MinhasReservasPageState extends State<MinhasReservasPage> {
  List<Reserva> _reservas = [];
  bool _carregando = true;
  bool _cancelando = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final reservas = await ReservaApiService.instance.listarMinhas();
      if (!mounted) return;
      setState(() => _reservas = reservas);
    } on DVanilleApiException catch (erro) {
      if (!mounted) return;
      setState(() {
        _reservas = [];
        _erro = erro.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reservas = [];
        _erro = 'Não foi possível consultar suas reservas.';
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageShell(
      child: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;

          final corTexto =
              isDark ? DVanilleColors.darkInk : DVanilleColors.darkTaupe;

          final corTextoSecundario =
              isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.taupe;

          final reservas = _reservas;

          return Column(
            children: [
              const SizedBox(height: 56),
              ContentWidth(
                child: Column(
                  children: [
                    const Text(
                      'Minhas reservas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'CreamCake',
                        fontSize: 48,
                        fontWeight: FontWeight.w400,
                        color: DVanilleColors.rose,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Acompanhe suas reservas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.italic,
                        color: corTextoSecundario,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: _carregando ? null : _carregar,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar reservas'),
              ),
              const SizedBox(height: 25),
              ContentWidth(
                maxWidth: 850,
                child: _carregando
                    ? const Center(child: CircularProgressIndicator())
                    : _erro != null
                        ? Column(children: [
                            Text(_erro!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton(
                                onPressed: _carregar,
                                child: const Text('Tentar novamente')),
                          ])
                        : reservas.isEmpty
                            ? _vazio(
                                context, isDark, corTexto, corTextoSecundario)
                            : Column(
                                children: [
                                  for (final reserva in reservas)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 20),
                                      child: _cartaoReserva(
                                        context,
                                        reserva,
                                        isDark,
                                        corTexto,
                                        corTextoSecundario,
                                      ),
                                    ),
                                ],
                              ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _vazio(
    BuildContext context,
    bool isDark,
    Color corTexto,
    Color corTextoSecundario,
  ) {
    return InfoBox(
      padding: const EdgeInsets.all(35),
      child: Column(
        children: [
          SvgPicture.asset(
            'assets/images/agenda.svg',
            width: 85,
            height: 85,
            fit: BoxFit.contain,
            colorFilter: ColorFilter.mode(
              isDark ? DVanilleColors.darkRose : DVanilleColors.rose,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Você ainda não possui reservas.',
            textAlign: TextAlign.center,
            style: AppTheme.display(
              size: 24,
              color: corTexto,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Faça uma reserva para garantir seu lugar na D’Vanille.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: corTextoSecundario,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.pushNamed(
                context,
                Routes.reservas,
              );
            },
            icon: SvgPicture.asset(
              'assets/images/agenda.svg',
              width: 19,
              height: 19,
              fit: BoxFit.contain,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            label: const Text('Fazer uma reserva'),
          ),
        ],
      ),
    );
  }

  Widget _cartaoReserva(
    BuildContext context,
    Reserva reserva,
    bool isDark,
    Color corTexto,
    Color corTextoSecundario,
  ) {
    final status = reserva.status.toLowerCase();

    final podeCancelar = status == 'solicitada' || status == 'confirmada';

    final corBorda = isDark ? DVanilleColors.darkBorder : DVanilleColors.line;

    return InfoBox(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: isDark
                      ? DVanilleColors.darkSurface
                      : DVanilleColors.blush2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: corBorda),
                ),
                child: SvgPicture.asset(
                  'assets/images/agenda.svg',
                  fit: BoxFit.contain,
                  colorFilter: ColorFilter.mode(
                    isDark ? DVanilleColors.darkRose : DVanilleColors.rose,
                    BlendMode.srcIn,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reserva ${reserva.id}',
                      style: AppTheme.display(
                        size: 23,
                        color: corTexto,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _statusTexto(reserva.status),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _statusCor(reserva.status, isDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Divider(color: corBorda),
          const SizedBox(height: 16),
          _linha(
            'Data',
            _formatarData(reserva.data),
            Icons.calendar_today_outlined,
            corTexto,
            corTextoSecundario,
          ),
          _linha(
            'Horário',
            reserva.horario,
            Icons.access_time_outlined,
            corTexto,
            corTextoSecundario,
          ),
          _linha(
            'Pessoas',
            '${reserva.pessoas}',
            Icons.people_outline,
            corTexto,
            corTextoSecundario,
          ),
          _linha(
            'Nome',
            reserva.nome,
            Icons.person_outline,
            corTexto,
            corTextoSecundario,
          ),
          _linha(
            'E-mail',
            reserva.email,
            Icons.email_outlined,
            corTexto,
            corTextoSecundario,
          ),
          _linha(
            'Telefone',
            reserva.telefone,
            Icons.phone_outlined,
            corTexto,
            corTextoSecundario,
          ),
          if (reserva.preferencias.trim().isNotEmpty)
            _linha(
              'Preferências',
              reserva.preferencias,
              Icons.restaurant_menu_outlined,
              corTexto,
              corTextoSecundario,
            ),
          if (reserva.observacoes.trim().isNotEmpty)
            _linha(
              'Informações adicionais',
              reserva.observacoes,
              Icons.notes_outlined,
              corTexto,
              corTextoSecundario,
            ),
          if (podeCancelar) ...[
            const SizedBox(height: 10),
            Divider(color: corBorda),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _cancelando
                    ? null
                    : () {
                        _confirmarCancelamento(
                          context,
                          reserva,
                        );
                      },
                icon: const Icon(
                  Icons.cancel_outlined,
                  size: 19,
                ),
                label: const Text('Cancelar reserva'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB96D6D),
                  side: const BorderSide(
                    color: Color(0xFFB96D6D),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmarCancelamento(
    BuildContext context,
    Reserva reserva,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final corTexto = isDark ? DVanilleColors.darkInk : DVanilleColors.darkTaupe;

    final corSecundaria =
        isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.taupe;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor:
              isDark ? DVanilleColors.darkSurface : DVanilleColors.cream,
          title: Text(
            'Cancelar reserva?',
            style: TextStyle(color: corTexto),
          ),
          content: Text(
            'Tem certeza que deseja cancelar a reserva ${reserva.id}?',
            style: TextStyle(color: corSecundaria),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Voltar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9B5555),
              ),
              child: const Text('Cancelar reserva'),
            ),
          ],
        );
      },
    );

    if (confirmar != true) {
      return;
    }

    if (_cancelando) return;
    setState(() => _cancelando = true);
    try {
      await ReservaApiService.instance.cancelarMinha(reserva.id);
      if (!mounted) return;
      showToast('Reserva cancelada com sucesso.', 'agenda.svg');
      await _carregar();
    } on DVanilleApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível cancelar sua reserva.')),
      );
    } finally {
      if (mounted) setState(() => _cancelando = false);
    }
  }

  Widget _linha(
    String titulo,
    String valor,
    IconData icone,
    Color corTexto,
    Color corTextoSecundario,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icone,
            size: 20,
            color: corTextoSecundario,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 145,
            child: Text(
              titulo,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: corTexto,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: corTextoSecundario,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatarData(String data) {
    final partes = data.split('-');

    if (partes.length == 3) {
      return '${partes[2]}/${partes[1]}/${partes[0]}';
    }

    return data;
  }

  String _statusTexto(String status) {
    switch (status.toLowerCase()) {
      case 'solicitada':
        return 'Reserva solicitada';

      case 'confirmada':
        return 'Reserva confirmada';

      case 'cancelada':
        return 'Reserva cancelada';

      case 'finalizada':
      case 'concluida':
      case 'concluída':
        return 'Reserva concluída';

      default:
        return status;
    }
  }

  Color _statusCor(String status, bool isDark) {
    switch (status.toLowerCase()) {
      case 'confirmada':
        return isDark ? const Color(0xFF91C99A) : const Color(0xFF4D7650);

      case 'cancelada':
        return isDark ? const Color(0xFFE69A9A) : const Color(0xFF9B5555);

      case 'finalizada':
      case 'concluida':
      case 'concluída':
        return isDark ? DVanilleColors.darkTextSecondary : DVanilleColors.taupe;

      case 'solicitada':
      default:
        return isDark ? DVanilleColors.darkRose : DVanilleColors.rose;
    }
  }
}
