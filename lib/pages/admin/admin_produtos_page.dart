import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dvanille/app/app.dart';
import 'package:dvanille/data/mock_data.dart';
import 'package:dvanille/models/produto.dart';
import 'package:dvanille/services/app_state.dart';
import 'package:dvanille/services/admin_produto_api_service.dart';
import 'package:dvanille/services/navigation.dart';
import 'package:dvanille/theme/app_theme.dart';
import 'package:dvanille/widgets/ui_kit.dart';
import 'admin_shell.dart';

class AdminProdutosPage extends StatefulWidget {
  const AdminProdutosPage({super.key});

  @override
  State<AdminProdutosPage> createState() => _AdminProdutosPageState();
}

class _AdminProdutosPageState extends State<AdminProdutosPage> {
  final TextEditingController _buscaController = TextEditingController();
  String _categoriaSelecionada = 'todas';
  bool _ordemCrescente = true;
  bool _repondoEstoque = false;

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _corTexto => _isDark
      ? Theme.of(context).colorScheme.onSurface
      : DVanilleColors.darkTaupe;
  Color get _corSecundaria =>
      _isDark ? const Color(0xFFCEBFB1) : DVanilleColors.taupe;
  Color get _corBorda =>
      _isDark ? const Color(0xFF5A4D44) : DVanilleColors.line;

  void _verProduto(Produto produto) => Navigator.of(context).pushNamed(
        Routes.adminProdutoDetalhes,
        arguments: produto.id,
      );

  void _editarProduto(Produto produto) => Navigator.of(context).pushNamed(
        Routes.adminProdutoForm,
        arguments: produto.id,
      );

  Future<void> _excluirProduto(Produto produto) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(produto.ativo ? 'Desativar produto' : 'Reativar produto'),
        content: Text(produto.ativo
            ? 'Desativar "${produto.nome}" no Supabase? Não será excluído definitivamente.'
            : 'Reativar "${produto.nome}"? O produto continuará indisponível até ser liberado.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(produto.ativo ? 'Desativar' : 'Reativar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmar == true) {
      try {
        await AppState.instance.atualizarAtivacaoProdutoComApi(
          produto.id, ativo: !produto.ativo,
        );
        if (!mounted) return;
        showToast(
          produto.ativo ? 'Produto desativado no banco!' : 'Produto reativado!',
          'palmas.svg',
        );
      } on AdminProdutoApiException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.mensagem)),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falha ao alterar produto na API.')),
        );
      }
    }
  }

  /// Reposição de unidades: a API acrescenta a quantidade, sem sobrescrever
  /// um estoque que possa ter mudado após pedidos de outros clientes.
  Future<void> _reporEstoque(Produto produto) async {
    if (_repondoEstoque) return;

    String quantidadeTexto = '';
    String? erroQuantidade;
    final quantidade = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, alterarDialogo) => AlertDialog(
          title: const Text('Repor estoque'),
          content: SizedBox(
            width: 350,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  produto.nome,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _corTexto,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Quantidade atual: ${produto.estoque} unidades'),
                const SizedBox(height: 14),
                TextFormField(
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (texto) {
                    quantidadeTexto = texto;
                    if (erroQuantidade != null) {
                      alterarDialogo(() => erroQuantidade = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: 'Unidades a acrescentar',
                    hintText: 'Ex.: 10',
                    helperText: 'As unidades serão somadas ao estoque atual.',
                    errorText: erroQuantidade,
                    prefixIcon: const Icon(Icons.add_box_outlined),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                final valor = int.tryParse(quantidadeTexto.trim());
                if (valor == null || valor < 1 || valor > 1000000) {
                  alterarDialogo(() => erroQuantidade =
                      'Informe entre 1 e 1.000.000 unidades.');
                  return;
                }
                Navigator.pop(dialogContext, valor);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar unidades'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || quantidade == null) return;

    setState(() => _repondoEstoque = true);
    try {
      await AdminProdutoApiService().reporEstoque(produto.id, quantidade);
      await AppState.instance.carregarCatalogoApi();
      if (!mounted) return;
      if (AppState.instance.erroCatalogoApi != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reposição enviada, mas não foi possível atualizar a lista. '
              'Atualize a página antes de tentar novamente.',
            ),
          ),
        );
      } else {
        showToast('$quantidade unidades adicionadas ao estoque!', 'palmas.svg');
      }
    } on AdminProdutoApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${e.mensagem} Confira a quantidade atual antes de repetir a reposição.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Falha ao consultar ou atualizar o estoque. '
            'Confira a quantidade antes de tentar novamente.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _repondoEstoque = false);
    }
  }

  Widget _menuAcoes(Produto produto) {
    return PopupMenuButton<String>(
      enabled: !_repondoEstoque,
      tooltip: 'Ações de ${produto.nome}',
      icon: Icon(Icons.more_horiz_rounded, color: _corSecundaria),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (acao) {
        switch (acao) {
          case 'ver':
            _verProduto(produto);
            break;
          case 'editar':
            _editarProduto(produto);
            break;
          case 'repor':
            _reporEstoque(produto);
            break;
          case 'excluir':
            _excluirProduto(produto);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem<String>(
          value: 'ver',
          child: Row(children: [
            Icon(Icons.visibility_outlined),
            SizedBox(width: 12),
            Text('Visualizar'),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'editar',
          child: Row(children: [
            Icon(Icons.edit_outlined),
            SizedBox(width: 12),
            Text('Editar'),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'repor',
          child: Row(children: [
            Icon(Icons.add_box_outlined),
            SizedBox(width: 12),
            Text('Repor estoque'),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'excluir',
          child: Row(children: [
            Icon(Icons.delete_outline_rounded, color: Color(0xFFB5473F)),
            SizedBox(width: 12),
            Text('Ativar / desativar', style: TextStyle(color: Color(0xFFB5473F))),
          ]),
        ),
      ],
    );
  }

  Widget _etiquetaCategoria(String categoria) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: _isDark ? DVanilleColors.darkCream2 : DVanilleColors.blush2,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          labelCategoria(categoria),
          style: const TextStyle(
            color: DVanilleColors.rose,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _preco(Produto produto) {
    final promocao = produto.oferta &&
        produto.precoAntigo != null &&
        produto.precoAntigo! > produto.preco;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          money(produto.preco),
          style: TextStyle(fontWeight: FontWeight.w700, color: _corTexto),
        ),
        if (promocao)
          Text(
            money(produto.precoAntigo!),
            style: TextStyle(
              fontSize: 11,
              color: _corSecundaria,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }

  Widget _status(Produto produto) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusPill(!produto.ativo
              ? 'inativo'
              : produto.disponivel ? 'ativo' : 'indisponivel'),
          if (produto.oferta) ...[
            const SizedBox(height: 6),
            const Text(
              'Em oferta',
              style: TextStyle(color: DVanilleColors.rose, fontSize: 11),
            ),
          ],
        ],
      );

  Widget _estoque(Produto produto) {
    final esgotado = produto.estoque <= 0;
    final baixo = produto.estoque > 0 && produto.estoque <= 5;
    final cor = esgotado
        ? const Color(0xFFBA4545)
        : baixo
            ? DVanilleColors.rose
            : _corTexto;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${produto.estoque} un.',
          style: TextStyle(color: cor, fontWeight: FontWeight.w700),
        ),
        if (esgotado || baixo) ...[
          const SizedBox(height: 4),
          Text(
            esgotado ? 'Esgotado' : 'Estoque baixo',
            style: TextStyle(
              color: cor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _foto(Produto produto, double tamanho) => SizedBox(
        width: tamanho,
        height: tamanho,
        child: ImagemProduto(
          url: produto.imagem,
          icone: produto.icon,
          altura: tamanho,
          radius: BorderRadius.circular(10),
        ),
      );

  Widget _campoBusca() => TextField(
        controller: _buscaController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Pesquisar produto...',
          prefixIcon:
              const Icon(Icons.search_rounded, color: DVanilleColors.rose),
          suffixIcon: _buscaController.text.isNotEmpty
              ? IconButton(
                  onPressed: () => setState(() {
                    _buscaController.clear();
                  }),
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).cardColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: _corBorda),
          ),
        ),
      );

  Widget _campoCategoria(List<String> categorias, String selecionada) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _corBorda),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selecionada,
          isExpanded: true,
          dropdownColor: Theme.of(context).cardColor,
          items: [
            const DropdownMenuItem(
              value: 'todas',
              child: Text('Todas as categorias'),
            ),
            ...categorias.map(
              (categoria) => DropdownMenuItem(
                value: categoria,
                child: Text(labelCategoria(categoria)),
              ),
            ),
          ],
          onChanged: (valor) {
            if (valor != null) setState(() => _categoriaSelecionada = valor);
          },
        ),
      ),
    );
  }

  Widget _tabela(List<Produto> produtos) {
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _corBorda),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth < 1060 ? 1060 : constraints.maxWidth,
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 19),
                  color: _isDark
                      ? DVanilleColors.darkCream2
                      : DVanilleColors.cream2,
                  child: Row(
                    children: const [
                      Expanded(flex: 4, child: Text('PRODUTO')),
                      Expanded(flex: 3, child: Text('CATEGORIA')),
                      Expanded(flex: 2, child: Text('PREÇO')),
                      Expanded(flex: 2, child: Text('ESTOQUE')),
                      Expanded(flex: 2, child: Text('STATUS')),
                      SizedBox(width: 66, child: Text('AÇÕES')),
                    ],
                  ),
                ),
                for (final produto in produtos) ...[
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _verProduto(produto),
                      hoverColor: _isDark
                          ? const Color(0xFF42362E)
                          : const Color(0xFFFFF3F0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  _foto(produto, 54),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Text(
                                      produto.nome,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _corTexto,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _etiquetaCategoria(produto.categoria),
                              ),
                            ),
                            Expanded(flex: 2, child: _preco(produto)),
                            Expanded(flex: 2, child: _estoque(produto)),
                            Expanded(flex: 2, child: _status(produto)),
                            SizedBox(width: 66, child: _menuAcoes(produto)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: _corBorda),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardMobile(Produto produto) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _corBorda),
      ),
      child: Column(
        children: [
          Row(
            children: [
              InkWell(
                  onTap: () => _verProduto(produto), child: _foto(produto, 68)),
              const SizedBox(width: 13),
              Expanded(
                child: InkWell(
                  onTap: () => _verProduto(produto),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        produto.nome,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _corTexto,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _etiquetaCategoria(produto.categoria),
                    ],
                  ),
                ),
              ),
              _menuAcoes(produto),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: _corBorda),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _preco(produto)),
              Expanded(child: _estoque(produto)),
              _status(produto),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.instance;
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final categorias = state.produtos
            .map((produto) => produto.categoria)
            .toSet()
            .toList()
          ..sort((a, b) => labelCategoria(a).compareTo(labelCategoria(b)));
        final categoria = categorias.contains(_categoriaSelecionada)
            ? _categoriaSelecionada
            : 'todas';
        final termo = _buscaController.text.trim().toLowerCase();
        final produtos = state.produtos.where((produto) {
          return (termo.isEmpty ||
                  produto.nome.toLowerCase().contains(termo)) &&
              (categoria == 'todas' || produto.categoria == categoria);
        }).toList()
          ..sort((a, b) {
            final comparar =
                a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
            return _ordemCrescente ? comparar : -comparar;
          });

        return AdminShell(
          titulo: 'Produtos',
          rotaAtual: Routes.adminProdutos,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largura = constraints.maxWidth;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Gerencie os produtos do cardápio da D’Vanille.',
                        style: TextStyle(color: _corSecundaria),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pushNamed(
                          Routes.adminProdutoForm,
                        ),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Novo produto'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (largura >= 680)
                    Row(
                      children: [
                        Expanded(flex: 3, child: _campoBusca()),
                        const SizedBox(width: 14),
                        Expanded(
                          flex: 2,
                          child: _campoCategoria(categorias, categoria),
                        ),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _campoBusca(),
                        const SizedBox(height: 12),
                        _campoCategoria(categorias, categoria),
                      ],
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${produtos.length} de ${state.produtos.length} produtos',
                          style: TextStyle(color: _corSecundaria),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _ordemCrescente = !_ordemCrescente,
                        ),
                        icon: const Icon(Icons.sort_by_alpha_rounded),
                        label:
                            Text(_ordemCrescente ? 'Nome: A–Z' : 'Nome: Z–A'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (produtos.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Center(
                          child: Text('Nenhum produto encontrado.')),
                    )
                  else if (largura >= 700)
                    _tabela(produtos)
                  else
                    Column(children: produtos.map(_cardMobile).toList()),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
