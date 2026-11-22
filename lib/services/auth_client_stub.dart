import 'package:http/http.dart' as http;

// Flutter mobile e plataformas não-web: Bearer JWT em memória, como antes.
http.Client criarClienteAuth() => http.Client();
