import 'package:flutter/material.dart';

import '../../app/app.dart';
import '../../services/admin_dashboard_api_service.dart';
import '../../services/app_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ui_kit.dart';
import 'admin_shell.dart';

/// Dashboard administrativo com indicadores da API real.
/// Reservas continuam locais até existir uma integração de reservas na API.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AdminDashboardApiService _api = AdminDashboardApiService();

  AdminDashboardDados? _dados;
  String? _erro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregarDashboard();
  }

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  Future<void> _carregarDashboard() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });

    try {
      // Reutiliza a sessão em cookie HttpOnly do Web.
      // O navegador envia o cookie; não é preciso acessar o JWT em Dart.
      final dados = await _api.carregar();
      if (!mounted) return;
      setState(() => _dados = dados);
    } catch (erro) {
      if (!mounted) return;
      setState(() {
        _erro = erro is AdminDashboardApiException
            ? erro.mensagem
            : 'Não foi possível carregar o Dashboard. Tente novamente.';
      });
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _moeda(num valor) =>
      'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';

  Color _corTexto(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark
        ? Theme.of(context).colorScheme.onSurface
        : DVanilleColors.darkTaupe;
  }

  Color _corSecundaria(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? const Color(0xFFCEBFB1) : DVanilleColors.taupe;
  }

  Widget _cardEstatistica(BuildContext context, _ResumoAdmin resumo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corTexto = _corTexto(context);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DVanilleColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: resumo.cor),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        resumo.valor,
                        style: AppTheme.display(
                          size: 38,
                          weight: FontWeight.w700,
                          color: corTexto,
                        ),
                      ),
                    ),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isDark
                            ? DVanilleColors.darkCream2
                            : DVanilleColors.blush2,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        resumo.icone,
                        color: resumo.cor,
                        size: 24,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  resumo.descricao,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: corTexto,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardAtividades(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required String rota,
    required Widget conteudo,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final corTexto = _corTexto(context);

    return Container(
      constraints: const BoxConstraints(minHeight: 225),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DVanilleColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? DVanilleColors.darkCream2
                      : DVanilleColors.blush2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, color: DVanilleColors.rose, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: AppTheme.display(size: 21, color: corTexto),
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pushNamed(rota),
                icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                label: const Text('Ver todos'),
                style: TextButton.styleFrom(
                  foregroundColor: DVanilleColors.rose,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: DVanilleColors.line),
          const SizedBox(height: 15),
          conteudo,
        ],
      ),
    );
  }

  Widget _linhaPedido(
    BuildContext context, {
    required String id,
    required String cliente,
    required String valor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                id,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _corTexto(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                cliente,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: _corSecundaria(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          valor,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _corTexto(context),
          ),
        ),
      ],
    );
  }

  Widget _linhaReserva(
    BuildContext context, {
    required String nome,
    required String data,
    required String status,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _corTexto(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                data,
                style: TextStyle(
                  fontSize: 12,
                  color: _corSecundaria(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        StatusPill(status),
      ],
    );
  }

  List<_ResumoAdmin> _estatisticas(AdminDashboardDados dados, int reservasLocais) {
    return [
      _ResumoAdmin(
        valor: '${dados.totalProdutos}',
        descricao: 'Produtos cadastrados',
        icone: Icons.inventory_2_outlined,
        cor: DVanilleColors.rose,
      ),
      _ResumoAdmin(
        valor: '${dados.totalPedidos}',
        descricao: 'Pedidos realizados',
        icone: Icons.receipt_long_outlined,
        cor: DVanilleColors.taupe,
      ),
      _ResumoAdmin(
        valor: '$reservasLocais',
        descricao: 'Reservas locais (não integradas)',
        icone: Icons.calendar_month_outlined,
        cor: DVanilleColors.rose,
      ),
      _ResumoAdmin(
        valor: '${dados.totalUsuarios}',
        descricao: 'Usuários cadastrados',
        icone: Icons.people_alt_outlined,
        cor: DVanilleColors.taupe,
      ),
      _ResumoAdmin(
        valor: _moeda(dados.faturamento),
        descricao: 'Faturamento confirmado',
        icone: Icons.payments_outlined,
        cor: DVanilleColors.rose,
      ),
      _ResumoAdmin(
        valor: '${dados.pedidosEmAndamento}',
        descricao: 'Pedidos em andamento',
        icone: Icons.hourglass_top_outlined,
        cor: DVanilleColors.taupe,
      ),
      _ResumoAdmin(
        valor: '${dados.pedidosFinalizados}',
        descricao: 'Pedidos finalizados',
        icone: Icons.task_alt_outlined,
        cor: DVanilleColors.rose,
      ),
      _ResumoAdmin(
        valor: '${dados.produtosEstoqueBaixo}',
        descricao: 'Produtos com estoque baixo',
        icone: Icons.inventory_outlined,
        cor: DVanilleColors.taupe,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final recentesReservas = state.reservas.reversed.take(3).toList();
        final dados = _dados;
        final stats = dados == null
            ? <_ResumoAdmin>[]
            : _estatisticas(dados, state.reservas.length);
        final recentesPedidos = dados?.pedidosRecentes.take(3).toList() ?? [];

        return AdminShell(
          titulo: 'Dashboard',
          rotaAtual: Routes.admin,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Indicadores da cafeteria',
                      style: TextStyle(
                        color: _corSecundaria(context),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _carregando ? null : _carregarDashboard,
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                    label: const Text('Atualizar'),
                    style: TextButton.styleFrom(
                      foregroundColor: DVanilleColors.rose,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_carregando && dados == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(35),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (_erro != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    border: Border.all(color: DVanilleColors.line),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _erro!,
                    style: TextStyle(color: _corTexto(context)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (dados != null) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final largura = constraints.maxWidth;
                    final colunas = largura >= 980
                        ? 4
                        : largura >= 480
                            ? 2
                            : 1;
                    const espacamento = 16.0;
                    final larguraCard =
                        (largura - espacamento * (colunas - 1)) / colunas;

                    return Wrap(
                      spacing: espacamento,
                      runSpacing: espacamento,
                      children: stats
                          .map(
                            (resumo) => SizedBox(
                              width: larguraCard,
                              child: _cardEstatistica(context, resumo),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final largura = constraints.maxWidth;
                    final duasColunas = largura >= 850;
                    const espacamento = 20.0;
                    final larguraCard = duasColunas
                        ? (largura - espacamento) / 2
                        : largura;

                    return Wrap(
                      spacing: espacamento,
                      runSpacing: espacamento,
                      children: [
                        SizedBox(
                          width: larguraCard,
                          child: _cardAtividades(
                            context,
                            titulo: 'Pedidos recentes',
                            icone: Icons.shopping_bag_outlined,
                            rota: Routes.adminPedidos,
                            conteudo: Column(
                              children: [
                                if (recentesPedidos.isEmpty)
                                  const DicaCampo('Nenhum pedido recente.'),
                                for (var i = 0; i < recentesPedidos.length; i++) ...[
                                  if (i > 0)
                                    const Divider(
                                      height: 20,
                                      color: DVanilleColors.line,
                                    ),
                                  _linhaPedido(
                                    context,
                                    id: recentesPedidos[i].numero,
                                    cliente: recentesPedidos[i].cliente,
                                    valor: _moeda(recentesPedidos[i].total),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: larguraCard,
                          child: _cardAtividades(
                            context,
                            titulo: 'Reservas locais recentes',
                            icone: Icons.event_available_outlined,
                            rota: Routes.adminReservas,
                            conteudo: Column(
                              children: [
                                if (recentesReservas.isEmpty)
                                  const DicaCampo('Nenhuma reserva local.'),
                                for (var i = 0; i < recentesReservas.length; i++) ...[
                                  if (i > 0)
                                    const Divider(
                                      height: 20,
                                      color: DVanilleColors.line,
                                    ),
                                  _linhaReserva(
                                    context,
                                    nome: recentesReservas[i].nome,
                                    data: recentesReservas[i].dataBr,
                                    status: recentesReservas[i].status,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ResumoAdmin {
  final String valor;
  final String descricao;
  final IconData icone;
  final Color cor;

  const _ResumoAdmin({
    required this.valor,
    required this.descricao,
    required this.icone,
    required this.cor,
  });
}
