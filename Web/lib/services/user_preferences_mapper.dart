/// Traduz as chaves legadas do Flutter para os valores aceitos pela API.
/// NÃO relacionar automaticamente condições pessoais a selos dos produtos.
class UserPreferencesMapper {
  const UserPreferencesMapper._();

  static const Map<String, String> rotulosApi = {
    'nenhuma': 'Nenhuma',
    'diabetes': 'Diabetes',
    'sop': 'SOP',
    'hipertensao': 'Hipertensão',
    'sii': 'SII',
    'semLactose': 'Intolerância à Lactose',
    'celiaca': 'Doença Celíaca',
    'sensibilidadeGluten': 'Sensibilidade ao Glúten',
    'aplv': 'APLV',
    'alergiaOleaginosas': 'Alergia a Oleaginosas',
    'vegetariano': 'Vegetariano',
    'vegano': 'Vegano',
    'lowCarb': 'Low Carb',
    'outra': 'Outra',
  };

  static List<String> paraApi(Iterable<String> chaves) {
    final unicos = chaves.toSet();
    if (unicos.contains('nenhuma')) return ['Nenhuma'];
    return [
      for (final entrada in rotulosApi.entries)
        if (unicos.contains(entrada.key) && entrada.key != 'nenhuma')
          entrada.value,
    ];
  }

  static List<String> paraFlutter(Iterable<String> rotulos) {
    final reverso = {
      for (final entrada in rotulosApi.entries) entrada.value: entrada.key,
    };
    return [
      for (final rotulo in rotulos)
        if (reverso.containsKey(rotulo)) reverso[rotulo]!,
    ];
  }
}
