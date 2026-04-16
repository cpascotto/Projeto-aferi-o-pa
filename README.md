# Vincere — App Mobile

App Flutter para identificacao facial e aferição de pressao arterial, com processamento on-device.

## Estrutura

```
flutter_app/        # codigo-fonte do app Flutter
build_vincere.bat   # script de build e instalacao via ADB
```

## Arquitetura

1. O celular captura a imagem.
2. O celular detecta e recorta o rosto localmente (ML Kit).
3. O celular gera o embedding facial localmente (DeepFace / Facenet512 via Chaquopy).
4. O celular compara os embeddings localmente com os baixados do backend.
5. O backend persiste: dados do paciente, embeddings, amostras faciais e aferições.

O backend **nao** processa imagens — atua apenas como camada de persistencia.

## Como buildar

### Pre-requisitos

- Flutter instalado em `C:\flutter`
- Android SDK instalado
- Android Studio com JBR
- Celular conectado via USB com depuracao USB ativa

### Build e instalacao

1. Abra `build_vincere.bat` e confirme as configuracoes no topo do arquivo:
   - `API_BASE_URL` — URL da API de producao
   - `FLUTTER_ROOT`, `ANDROID_SDK_ROOT`, `JAVA_HOME` — caminhos das ferramentas

2. Execute:
   ```
   build_vincere.bat
   ```

O script vai:
- Testar conectividade com a API
- Rodar `flutter clean` + `flutter pub get`
- Gerar o APK com as variaveis de ambiente corretas
- Instalar no celular via ADB
- Copiar o APK para `Downloads` do celular como `app-mobile-debug.apk`

O APK final tambem fica salvo em:
```
flutter_app\build\app\outputs\flutter-apk\vincere.apk
```

## Variaveis de ambiente do app

| Variavel | Descricao |
|---|---|
| `API_BASE_URL` | URL principal da API |
| `API_FALLBACK_BASE_URL` | URL de fallback da API |

Ambas sao injetadas via `--dart-define` no momento do build.
