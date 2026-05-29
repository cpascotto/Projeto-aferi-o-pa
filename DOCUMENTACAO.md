# Documentação Técnica — Vincere Totem de Aferição

## Sumário

1. [Visão geral](#1-visão-geral)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Build e instalação](#3-build-e-instalação)
4. [Tela de administrador](#4-tela-de-administrador)
5. [Fluxo de atendimento](#5-fluxo-de-atendimento)
6. [Integração com a API Forza](#6-integração-com-a-api-forza)
7. [Reconhecimento facial](#7-reconhecimento-facial)
8. [Bluetooth — medidor de pressão](#8-bluetooth--medidor-de-pressão)
9. [Modo totem](#9-modo-totem)
10. [Problemas comuns](#10-problemas-comuns)

---

## 1. Visão geral

App Android para totem de autoatendimento. Funções:

- Identificar o paciente por **reconhecimento facial** ou **CPF**
- Cadastrar / atualizar a biometria facial
- Medir **pressão arterial** via aparelho Bluetooth BLE
- Registrar o atendimento na **API Forza ERP**

O reconhecimento facial roda **on-device** (no celular). Imagens nunca saem do
aparelho — apenas o *embedding* (vetor de 512 números) é enviado à API.

A comparação dos embeddings (cosine similarity) é feita **no backend Forza**.

---

## 2. Pré-requisitos

### Ferramentas

| Ferramenta | Observação |
|---|---|
| Flutter 3.x | Caminho padrão do script: `C:\flutter` |
| Android Studio | Fornece o JBR (Java) e o SDK |
| Android SDK (API 24+) | Inclui o ADB em `platform-tools` |

### Dispositivo

- Android 7.0 (API 24) ou superior
- Depuração USB ativa
- Conectado via USB antes de buildar

---

## 3. Build e instalação

Execute na raiz do projeto:

```bat
build_vincere.bat
```

O script faz, em ordem:

1. Mapeia drives virtuais (`X:` e `Y:`) apontando para a raiz do projeto —
   necessário porque o Gradle falha com espaços/paths sincronizados no caminho.
2. Confere os caminhos das ferramentas (Flutter, SDK, JBR, ADB).
3. Testa o ERP (informativo, não bloqueia).
4. Verifica o dispositivo via `adb devices`.
5. Roda `flutter pub get` e `flutter build apk --release`.
6. Instala no celular (`adb install -r`) e copia o APK para `/sdcard/Download`.

### Configuração no topo do `.bat`

```bat
set "ERP_AFERICAO_URL=https://api.forzauno.com.br/KB16WT/rest/Forza/prcAfericao01"
set "FLUTTER_ROOT=C:\flutter"
set "ANDROID_SDK_ROOT=C:\Users\SEU_USUARIO\AppData\Local\Android\Sdk"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
```

> A URL do ERP também pode ser trocada em tempo de execução pela tela de
> administrador, sem rebuildar.

APK final:
```
flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## 4. Tela de administrador

Acesso: toque **5 vezes na logo** (na tela inicial ou na câmera).

Seções:

1. **Modo de exibição** — liga/desliga o modo totem (tela cheia + tela sempre ligada)
2. **Ambiente da API Forza** — alterna entre Homologação e Produção; URLs
   editáveis; botão "Restaurar padrão". A mudança vale na hora, sem rebuild.
3. **Identificação do equipamento** — `ID Unidade` (enviado em N1/N2) e
   nome do totem (`ID Medidor`).
4. **Dispositivo Bluetooth** — escaneia e fixa o medidor de pressão.
5. **Diagnóstico** — visualizador dos logs do dispositivo.

As configurações são persistidas em `SharedPreferences`.

---

## 5. Fluxo de atendimento

### Tela inicial

Dois botões:

- **Início de atendimento** — paciente chegou; ao final registra a aferição (N3).
- **Fim de atendimento** — paciente saindo; faz a mesma identificação, mas ao
  final finaliza o atendimento (F1) em vez de registrar medição.

O modo escolhido é guardado e lido no momento da ação final.

### Caminho completo

```
[Início ou Fim]
   ↓
Câmera → reconhecimento facial (N1)
   │           └─ ou botão "Digitar CPF" → N2
   ↓
"É você?" (confirma identidade)
   ↓
Instruções da aferição → mede pressão (BLE) → tela de resultado (Repetir / OK)
   ↓
OK:
   • Início → N3 (registra medição)
   • Fim    → F1 (finaliza atendimento)
"Não quero aferir" → N4 (nos dois modos)
```

### Telas por código de mensagem do ERP

| Cod | Significado | Tela |
|---|---|---|
| 1 | Biometria não encontrada | Informar CPF |
| 2 | Cliente não cadastrado | Cliente não cadastrado |
| 3 | Cliente ativo | "É você?" → aferição |
| 4 | Sem acordo vigente | Cliente sem acordo |
| 5 | Já tem intervenção em andamento | Acesso liberado |
| 6 | Aferiu há menos de 1 hora | Aferição recente |
| 7 / 14 / 15 / 16 | Valores fora da normalidade | Aguardar fisioterapeuta |
| 8 | Liberado para atendimento | Liberado |
| 9 | Aferição registrada | Obrigado |
| 10 | Ação inválida | Mensagem genérica |
| 11 / 12 | CPF obrigatório / inválido | Mensagem genérica |

Roteamento centralizado em `lib/navigation/erp_flow_navigation.dart`.

---

## 6. Integração com a API Forza

- **Backend:** Forza ERP (plataforma GeneXus)
- **Endpoint único** para todas as ações (POST JSON)
- **Envelope de entrada:** `{ "sdtAfericao01Ent": { ... } }`
- **Envelope de saída:** `{ "sdtAfericao01Sai": { ID_Cliente, Nome_Cliente, ID_Acordo, TMS_Proxima_Intervencao, Erro, Mensagem: [{Cod, Msg}] } }`

### Campos enviados por ação

| Ação | Campos |
|---|---|
| **N1** (identificar) | `ID_Unidade`, `Biometria_Facial`, `Acao` (+`ID_Cliente` ao persistir biometria) |
| **N2** (validar CPF) | `ID_Unidade`, `Biometria_Facial`, `CPF`, `Acao` |
| **N3** (medição) | `ID_Cliente`, `ID_Acordo`, `TMS_Proxima_interacao`, `Sistolica`, `Diastolica`, `BPM`, `Acao` |
| **N4** (recusa) | `ID_Cliente`, `ID_Acordo`, `TMS_Proxima_interacao`, `Acao` |
| **F1** (finalizar) | `ID_Cliente`, `ID_Acordo`, `Acao` |

> `Biometria_Facial` é uma **string** JSON com o vetor de 512 floats
> (`jsonEncode(List<double>)`), não um array JSON nativo.

Camada de serviço: `lib/services/erp_api_service.dart`.

---

## 7. Reconhecimento facial

Pipeline (em `lib/services/`):

1. **Captura** — câmera frontal, foto disparada quando o rosto fica centralizado
   por 3 s (`camera_screen.dart`).
2. **Detecção** — Google ML Kit: landmarks, ângulos e olhos abertos
   (`face_detector_service.dart`).
3. **Validação de qualidade** — yaw < 12°, roll < 8°, pitch < 12°, olhos > 35%.
4. **Alinhamento + recorte** — rotaciona pelos olhos, recorta o rosto, redimensiona
   para 112×112, neutraliza o fundo (`face_image_service.dart`).
5. **Embedding** — DeepFace/Facenet512 via Chaquopy (Python embarcado), retorna
   512 floats (`embedding_service.dart` + `android/.../python/deepface_bridge.py`).
6. **Comparação** — feita no backend Forza (cosine similarity).

Modelo: **Facenet512** (pesos em `android/app/src/main/python/weights/`).
TensorFlow 2.1 / Python 3.8 via Chaquopy (versões travadas por compatibilidade
de wheels para Android).

---

## 8. Bluetooth — medidor de pressão

Implementado no nativo Android (`MainActivity.kt`).

| Parâmetro | Valor |
|---|---|
| Serviço BLE | `FFF0` |
| Característica Notify | `FFF4` |
| Característica Write | `FFF5` |
| Comando de sincronização | `6C 37 01 00 5A` |

**Fluxo:** scan pelo MAC → conecta → descobre serviços → habilita notificação
em FFF4 → escreve o comando de sync em FFF5 → recebe os registros.

O aparelho mantém um **histórico circular** (até ~18 medições). O app seleciona
o registro de **menor índice** (`minOrNull`), que corresponde à medição
recém-feita exibida na tela do aparelho.

Decodificação de cada registro (8 bytes):
- byte 5 → sistólica (BCD; offset +100 quando < 60)
- byte 6 → diastólica (BCD)
- byte 7 → pulso (BPM)

> O medidor é selecionado na tela de administrador. Para trocar de modelo de
> aparelho, ajuste as constantes/decodificação no `MainActivity.kt`.

---

## 9. Modo totem

Pensado para terminais de autoatendimento. Ativado na tela de administrador:

- Tela cheia (imersivo)
- Tela sempre ligada (wake lock)
- Bloqueia saída acidental pelo botão voltar / barra de navegação

Controlado por `lib/services/totem_mode_controller.dart`.

---

## 10. Problemas comuns

### Build falha com "parent is null" / erro de path no Gradle
Builde sempre pelo `build_vincere.bat` (ele cria o drive virtual). Buildar
direto de uma pasta do OneDrive/Dropbox causa esse erro.

### Celular não aparece no ADB
- Cabo USB de dados (não só de carga)
- Depuração USB ativa
- Aceitar o popup de autorização no celular
- Testar: `adb devices`

### Aparelho de pressão conecta mas demora / reconecta
Comportamento conhecido na primeira conexão (cache GATT do Android). Após
1–2 reconexões a leitura ocorre normalmente.

### Valores de pressão diferentes da tela do aparelho
O app usa o registro mais recente do histórico (`minOrNull`). Se aparecer um
valor antigo, verifique se há medições antigas no buffer do aparelho.

### App demora no primeiro reconhecimento
Na primeira execução após instalar, o modelo Facenet512 é carregado (warmup),
o que pode levar 20–40 s. Depois fica em cache.

### Câmera sem permissão
Configurações do celular → Apps → Vincere → Permissões → Câmera → Permitir.
