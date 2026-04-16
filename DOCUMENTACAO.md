# Documentação — Vincere App Mobile

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Configuração da API](#3-configuração-da-api)
4. [Como buildar e instalar](#4-como-buildar-e-instalar)
5. [Fluxo do app](#5-fluxo-do-app)
6. [Endpoints da API](#6-endpoints-da-api)
7. [Bluetooth — Medidor de pressão](#7-bluetooth--medidor-de-pressão)
8. [Modo Totem](#8-modo-totem)
9. [Problemas comuns](#9-problemas-comuns)

---

## 1. Visão Geral

O Vincere é um app Android para:

- Identificar pacientes por CPF
- Cadastrar amostras faciais
- Realizar identificação facial on-device (sem enviar imagens para o servidor)
- Medir pressão arterial via dispositivo Bluetooth BLE

Todo o processamento de imagem e reconhecimento facial ocorre **dentro do próprio celular**. O backend é usado apenas para persistir dados (pacientes, embeddings, medições).

---

## 2. Pré-requisitos

### Ferramentas de desenvolvimento

| Ferramenta | Versão mínima | Observação |
|---|---|---|
| Flutter | 3.x | Instalar em `C:\flutter` ou ajustar caminho no `.bat` |
| Android Studio | Electric Eel+ | Necessário para o JBR (Java) e SDK |
| Android SDK | API 24+ | Instalado pelo Android Studio |
| ADB | qualquer | Incluído no Android SDK (`platform-tools`) |

### Celular / dispositivo

- Android 7.0 (API 24) ou superior
- Depuração USB ativa (Configurações → Opções do desenvolvedor → Depuração USB)
- Conectado ao computador via cabo USB antes de rodar o script

---

## 3. Configuração da API

O app se comunica com uma API backend (Laravel). Antes de buildar, abra o arquivo `build_vincere.bat` em um editor de texto e localize a seção de configuração no topo:

```bat
:: --- Configuracoes de API ---
set "API_BASE_URL=http://SEU_IP_AQUI:PORTA"
set "API_FALLBACK_BASE_URL=http://SEU_IP_AQUI:PORTA"
```

Substitua `SEU_IP_AQUI:PORTA` de acordo com o cenário:

---

### Cenário 1 — API em servidor de produção (IP público)

```bat
set "API_BASE_URL=http://203.0.113.50:8030"
set "API_FALLBACK_BASE_URL=http://203.0.113.50:8030"
```

> Substitua `203.0.113.50` pelo IP público do seu servidor e `8030` pela porta configurada.

---

### Cenário 2 — API rodando no mesmo computador, celular na mesma rede Wi-Fi

O celular não consegue acessar `localhost` do computador. Use o IP local do computador na rede.

**Como descobrir o IP local no Windows:**

1. Abra o Prompt de Comando (`cmd`)
2. Digite: `ipconfig`
3. Localize o adaptador de rede ativo (Wi-Fi ou Ethernet)
4. Copie o valor de **Endereço IPv4**, por exemplo: `192.168.1.105`

```bat
set "API_BASE_URL=http://192.168.1.105:8000"
set "API_FALLBACK_BASE_URL=http://192.168.1.105:8000"
```

> A porta padrão do servidor Laravel local é `8000`.  
> O celular e o computador **precisam estar na mesma rede Wi-Fi**.

---

### Cenário 3 — Emulador Android (não recomendado para este app)

O emulador usa o endereço especial `10.0.2.2` para acessar o `localhost` do computador host:

```bat
set "API_BASE_URL=http://10.0.2.2:8000"
set "API_FALLBACK_BASE_URL=http://10.0.2.2:8000"
```

> Este app usa câmera e Bluetooth, que **não funcionam bem em emuladores**. Recomenda-se usar celular físico.

---

### Verificando se a API está acessível

Antes de buildar, confirme que a API responde. Abra o navegador do celular (ou do computador) e acesse:

```
http://SEU_IP:PORTA/up
```

Deve retornar algo como:

```json
{"status": "ok"}
```

Também teste o endpoint de pacientes:

```
http://SEU_IP:PORTA/api/patients
```

Resposta esperada (banco vazio):

```json
{"patients": []}
```

Se não responder, verifique se o servidor está rodando e se o firewall libera a porta.

---

## 4. Como buildar e instalar

### Passo a passo

1. Conecte o celular ao computador via USB
2. Abra `build_vincere.bat` e configure a `API_BASE_URL` (veja seção anterior)
3. Verifique os caminhos das ferramentas no topo do arquivo:

```bat
set "FLUTTER_ROOT=C:\flutter"
set "ANDROID_SDK_ROOT=C:\Users\SEU_USUARIO\AppData\Local\Android\Sdk"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
```

> Ajuste `SEU_USUARIO` e os caminhos se necessário.

4. Dê duplo clique em `build_vincere.bat` (ou execute pelo terminal)

O script vai:

1. Mapear os drives virtuais (necessário por causa de espaços no caminho)
2. Testar conectividade com a API
3. Verificar o dispositivo conectado via ADB
4. Rodar `flutter clean` + `flutter pub get`
5. Gerar o APK com as URLs configuradas
6. Instalar o APK no celular via ADB
7. Copiar o APK para `Downloads` do celular

### Onde fica o APK gerado

```
flutter_app\build\app\outputs\flutter-apk\vincere.apk
```

O APK também é copiado para o celular em:

```
/sdcard/Download/app-mobile-debug.apk
```

---

## 5. Fluxo do app

```
Splash Screen
    │
    ▼
Tela de CPF
    │  (CPF digitado e confirmado)
    ▼
Cadastro Facial
    │  (rosto capturado com qualidade)
    ▼
Tela de Identificação  ←── (identificação bem-sucedida)
    │  (confirma: SIM)
    ▼
Instrução de Pressão Arterial
    │  (medição via Bluetooth)
    ▼
Resultado da Medição
    │  (10 segundos)
    ▼
Tela inicial
```

### Detalhes de cada tela

#### Tela de CPF
- Teclado numérico próprio (não usa teclado do sistema)
- Aceita exatamente 11 dígitos
- Envia para a API: `POST /api/patient/register-basic`

#### Cadastro Facial
- Câmera traseira com overlay circular guia
- Detecta rosto em tempo real via ML Kit
- Exige que o rosto esteja centralizado e enquadrado
- Validações de qualidade:
  - Yaw (lateral) < 12°
  - Roll (inclinação) < 8°
  - Pitch (vertical) < 12°
  - Probabilidade de olhos abertos > 35%
- Contagem regressiva de 3 segundos antes de capturar
- O embedding facial é gerado localmente (DeepFace Facenet512)
- Envia para a API: `POST /api/patient/register-face-sample`

#### Tela de Identificação
- Exibe o CPF do paciente identificado
- Botões: **SIM** (confirmar) ou **NÃO** (cadastrar novamente)

#### Instrução de Pressão Arterial
- Exibe imagens instrutivas sobre como posicionar o aparelho
- Aguarda medição via Bluetooth
- Salva resultado na API: `POST /api/patient/blood-pressure-measurements`
- Retorna para tela inicial após 10 segundos

---

## 6. Endpoints da API

O app consome os seguintes endpoints. Todos usam `Content-Type: application/json`.

### `GET /api/patients`

Retorna todos os pacientes com seus embeddings faciais.

**Resposta:**
```json
{
  "patients": [
    {
      "id": 1,
      "cpf": "12345678901",
      "face_samples": [
        {
          "face_embedding": "[0.123, -0.456, ...]"
        }
      ]
    }
  ]
}
```

---

### `POST /api/patient/register-basic`

Cadastra um paciente pelo CPF.

**Body:**
```json
{
  "cpf": "12345678901"
}
```

**Resposta:**
```json
{
  "patient": {
    "id": 1,
    "cpf": "12345678901"
  }
}
```

---

### `POST /api/patient/register-face-sample`

Salva uma amostra facial de um paciente.

**Body:**
```json
{
  "patient_id": 1,
  "capture_type": "enrollment",
  "face_image_b64": "base64...",
  "face_embedding": "[0.123, -0.456, ...]"
}
```

---

### `POST /api/patient/blood-pressure-measurements`

Salva uma medição de pressão arterial.

**Body:**
```json
{
  "patient_id": 1,
  "systolic": 120,
  "diastolic": 80,
  "bpm": 72,
  "measured_at": "2025-01-15T10:30:00",
  "raw_payload": "6C370100..."
}
```

---

### `POST /api/mobile-debug-logs`

Envia logs de debug do app para o servidor (usado em desenvolvimento).

---

## 7. Bluetooth — Medidor de pressão

O app se conecta automaticamente ao dispositivo BLE configurado em:

```
flutter_app/android/app/src/main/kotlin/.../MainActivity.kt
```

Configurações do dispositivo:

| Parâmetro | Valor |
|---|---|
| Nome do dispositivo | `BT-BPM BLE` |
| Serviço BLE | `FFF0` |
| Característica Notify | `FFF4` |
| Característica Write | `FFF5` |
| Comando de início | `6C 37 01 00 5A` |

> Para trocar o dispositivo de medição, altere as constantes correspondentes em `MainActivity.kt` e rebuilde o APK.

---

## 8. Modo Totem

O app tem suporte a **modo totem** (quiosque), pensado para uso em terminais de atendimento.

**Como ativar:**
- Toque **5 vezes** na logo na tela inicial para abrir o painel de administração
- O painel permite ativar/desativar:
  - Tela cheia (fullscreen imersivo)
  - Tela sempre ligada (wake lock)

Em modo totem, o app impede que o usuário saia acidentalmente pelo botão voltar ou pela barra de navegação.

---

## 9. Problemas comuns

### "API nao respondeu"

O script testa a API antes de buildar. Se falhar:

- Confirme que o servidor backend está rodando
- Confirme que a `API_BASE_URL` no `.bat` está correta
- Teste manualmente no navegador: `http://SEU_IP:PORTA/up`
- Verifique se o firewall do Windows não está bloqueando a porta

---

### "Flutter nao encontrado"

Ajuste o caminho `FLUTTER_ROOT` no topo do `build_vincere.bat`:

```bat
set "FLUTTER_ROOT=C:\caminho\para\flutter"
```

---

### "ADB nao encontrado" / celular não reconhecido

- Confirme que o cabo USB está conectado
- Ative **Depuração USB** nas opções do desenvolvedor do celular
- Em alguns celulares é necessário aceitar a permissão de depuração na tela
- Teste manualmente: abra o terminal e digite `adb devices`

---

### App instala mas não consegue conectar na API

Isso geralmente acontece quando:

1. **Celular e computador em redes diferentes** — conecte ambos ao mesmo Wi-Fi
2. **Usando `localhost` ou `127.0.0.1`** — o celular não acessa o `localhost` do PC; use o IP local (ex: `192.168.1.105`)
3. **Firewall bloqueando** — libere a porta da API no Firewall do Windows

---

### Erro de câmera ou permissão negada

Na primeira execução, o app solicita permissão de câmera. Se negada acidentalmente:

- Configurações do celular → Apps → Vincere → Permissões → Câmera → Permitir

---

### App trava no warmup do Python/DeepFace

Na primeira execução após instalação, o app inicializa o modelo de reconhecimento facial (Facenet512). Isso pode levar **20 a 40 segundos** na primeira vez. Aguarde até aparecer a tela principal.
