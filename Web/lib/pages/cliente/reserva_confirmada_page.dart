import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../models/reserva.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/ui_kit.dart';
import '../auth/recuperar_senha_page.dart' show IconeSucesso;

class ReservaConfirmadaPage extends StatelessWidget {
  const ReservaConfirmadaPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Somente a reserva retornada pela API pode ser exibida aqui.
    // Não utilizar dados locais ou a última reserva de outro cliente.
    final argumento = ModalRoute.of(context)?.settings.arguments;
    final Reserva? reserva = argumento is Reserva ? argumento : null;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final corTitulo =
        isDark ? DVanilleColors.darkRose : DVanilleColors.darkTaupe;

    if (reserva == null) {
      return const PageShell(
        child: EstadoVazio(
          emoji: '📅',
          titulo: 'Reserva não encontrada.',
        ),
      );
    }

    return PageShell(
      child: Column(
        children: [
          const SizedBox(height: 48),
          ContentWidth(
            maxWidth: 520,
            child: Column(
              children: [
                const IconeSucesso(),
                const SizedBox(height: 18),

                // TÍTULO

                Text(
                  'Reserva solicitada com sucesso!',
                  textAlign: TextAlign.center,
                  style: AppTheme.display(
                    size: 30,
                    color: corTitulo,
                  ),
                ),

                const SizedBox(height: 22),

                // INFORMAÇÕES DA RESERVA

                InfoBox(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      _linha(
                        context,
                        'Número',
                        reserva.id,
                        negrito: true,
                      ),
                      _linha(
                        context,
                        'Nome',
                        reserva.nome,
                      ),
                      _linha(
                        context,
                        'Data',
                        reserva.dataBr,
                      ),
                      _linha(
                        context,
                        'Horário',
                        reserva.horario,
                      ),
                      _linha(
                        context,
                        'Pessoas',
                        '${reserva.pessoas}',
                        ultima: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // STATUS

                StatusPill(reserva.status),
                const SizedBox(height: 8),
                const Text('Aguarde a confirmação da cafeteria.', textAlign: TextAlign.center),
                if (reserva.guestAccessToken != null) ...[
                  const SizedBox(height: 18),
                  InfoBox(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Text('Reserva de visitante: guarde o número e o código de acesso em local seguro. O código não será exibido novamente.'),
                        const SizedBox(height: 8),
                        SelectableText(reserva.guestAccessToken!),
                        TextButton.icon(
                          onPressed: () => Clipboard.setData(ClipboardData(text: reserva.guestAccessToken!)),
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('Copiar código de acesso'),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 26),

                // BOTÃO VOLTAR PARA HOME

                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamedAndRemoveUntil(
                    Routes.home,
                    (r) => false,
                  ),
                  child: const Text('Voltar para Home'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linha(
    BuildContext context,
    String titulo,
    String valor, {
    bool negrito = false,
    bool ultima = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final corTexto = isDark ? DVanilleColors.darkInk : DVanilleColors.ink;

    final corBorda = isDark ? DVanilleColors.darkBorder : DVanilleColors.line;

    final estilo = TextStyle(
      fontSize: 14,
      fontWeight: negrito ? FontWeight.w800 : FontWeight.w500,
      color: corTexto,
    );

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: ultima
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: corBorda,
                ),
              ),
            ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            titulo,
            style: estilo,
          ),
          Flexible(
            child: Text(
              valor,
              textAlign: TextAlign.end,
              style: estilo,
            ),
          ),
        ],
      ),
    );
  }
}
