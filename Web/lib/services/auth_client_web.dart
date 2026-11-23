import 'package:http/http.dart' as http;
import 'package:http/browser_client.dart';

// Flutter Web: permite o envio automático do cookie HttpOnly na API.
http.Client criarClienteAuth() => BrowserClient()..withCredentials = true;
