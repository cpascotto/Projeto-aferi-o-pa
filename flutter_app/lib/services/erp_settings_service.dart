import 'package:shared_preferences/shared_preferences.dart';

/// Ambientes disponíveis para a API Forza ERP.
enum ErpEnvironment { homologation, production }

/// Defaults de URL para cada ambiente.
class ErpUrlDefaults {
  static const String homologation =
      'https://api.forzauno.com.br/KB16WT/rest/Forza/prcAfericao01';

  /// Produção ainda não disponível — preenchida pela operação no admin.
  static const String production = '';
}

/// Service que persiste e expõe as URLs e o ambiente ativo da API Forza.
///
/// Singleton — chame `ErpSettingsService.instance.load()` antes de usar.
class ErpSettingsService {
  ErpSettingsService._();

  static final ErpSettingsService instance = ErpSettingsService._();

  static const String _kHomologationUrl = 'erp_homologation_url';
  static const String _kProductionUrl = 'erp_production_url';
  static const String _kEnvironment = 'erp_environment';

  String _homologationUrl = ErpUrlDefaults.homologation;
  String _productionUrl = ErpUrlDefaults.production;
  ErpEnvironment _environment = ErpEnvironment.homologation;
  bool _loaded = false;

  String get homologationUrl => _homologationUrl;
  String get productionUrl => _productionUrl;
  ErpEnvironment get environment => _environment;

  /// URL ativa — a que será usada pelo ErpApiService.
  String get activeUrl => _environment == ErpEnvironment.production
      ? _productionUrl
      : _homologationUrl;

  bool get isLoaded => _loaded;

  /// Carrega as configurações persistidas. Deve ser chamado no boot do app.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _homologationUrl =
        prefs.getString(_kHomologationUrl) ?? ErpUrlDefaults.homologation;
    _productionUrl =
        prefs.getString(_kProductionUrl) ?? ErpUrlDefaults.production;

    final rawEnv = prefs.getString(_kEnvironment);
    _environment = rawEnv == 'production'
        ? ErpEnvironment.production
        : ErpEnvironment.homologation;

    _loaded = true;
  }

  Future<void> setHomologationUrl(String url) async {
    _homologationUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHomologationUrl, url);
  }

  Future<void> setProductionUrl(String url) async {
    _productionUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProductionUrl, url);
  }

  Future<void> setEnvironment(ErpEnvironment env) async {
    _environment = env;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kEnvironment,
      env == ErpEnvironment.production ? 'production' : 'homologation',
    );
  }

  /// Restaura ambas as URLs para os defaults.
  Future<void> resetToDefaults() async {
    _homologationUrl = ErpUrlDefaults.homologation;
    _productionUrl = ErpUrlDefaults.production;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kHomologationUrl, ErpUrlDefaults.homologation);
    await prefs.setString(_kProductionUrl, ErpUrlDefaults.production);
  }
}
