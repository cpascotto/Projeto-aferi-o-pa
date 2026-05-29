# Vincere — Totem de Aferição

Aplicativo Android (Flutter) para totem de autoatendimento: identifica o paciente
por **reconhecimento facial** ou **CPF**, mede a **pressão arterial** via aparelho
Bluetooth e registra o atendimento na **API Forza ERP**.

Todo o processamento de imagem e o reconhecimento facial acontecem **no próprio
dispositivo** — nenhuma foto é enviada para servidores. Apenas o *embedding*
facial (vetor numérico) é trafegado.

---

## Estrutura do repositório

```
flutter_app/        Código-fonte do app Flutter
build_vincere.bat   Script de build + instalação via ADB
Diagrama Aferição.jpg   Diagrama do fluxo de atendimento
README.md           Este arquivo
DOCUMENTACAO.md     Documentação técnica completa
```

---

## Arquitetura (resumo)

```
[Totem / celular]                         [Forza ERP - GeneXus]
  câmera → detecta rosto (ML Kit)
        → recorta + alinha (112x112)
        → gera embedding (DeepFace/Facenet512, 512 floats)
        → envia embedding ──────────────► N1: cosine similarity no backend
                                          ◄── retorna o cliente identificado
  mede pressão (Bluetooth BLE)
        → envia medição ────────────────► N3 / N4 / F1
```

- **Identificação:** o app gera o embedding; o **Forza** faz a comparação
  (cosine similarity) e devolve o cliente.
- **Aferição:** lida via Bluetooth de um medidor de pressão e registrada no ERP.
- **Endpoint único:** todas as ações (N1, N2, N3, N4, F1) usam o mesmo endpoint
  REST do Forza, com o envelope `sdtAfericao01Ent`.

---

## Fluxo de atendimento

```
Tela inicial  →  [Início de atendimento]  ou  [Fim de atendimento]
       │
       ▼
   Câmera (reconhecimento facial)  ─ ou ─  Digitar CPF
       │
       ▼
   "É você?" (confirmação)
       │
       ▼
   Instruções + medição da pressão (Bluetooth)
       │
       ▼
   Resultado  →  OK
       │
   ┌───┴───────────────┐
   ▼                   ▼
 Início = N3        Fim = F1
 (registra)         (finaliza)
```

Detalhes completos em [`DOCUMENTACAO.md`](DOCUMENTACAO.md).

---

## Como buildar

### Pré-requisitos

- Flutter instalado (padrão do script: `C:\flutter`)
- Android Studio (usa o JBR como Java)
- Android SDK + `platform-tools` (ADB)
- Celular Android 7.0+ com **Depuração USB** ativa

### Build e instalação

```bat
build_vincere.bat
```

O script:
1. Mapeia um drive virtual (`X:`) para contornar espaços no caminho
2. Verifica conectividade com o ERP (informativo)
3. Confirma o dispositivo conectado no ADB
4. Roda `flutter pub get` e gera o APK release
5. Instala no celular e copia o APK para a pasta `Download` do aparelho

> **Importante:** o build deve rodar pelo drive virtual que o script cria.
> Buildar direto de uma pasta sincronizada (OneDrive/Dropbox) pode falhar com
> erro de path no Gradle.

APK gerado em:
```
flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

---

## Configuração (tela de administrador)

Toque **5 vezes na logo** (tela inicial ou câmera) para abrir o painel. Lá é
possível configurar:

- **Ambiente da API** — Homologação / Produção (URLs editáveis)
- **Identificação do equipamento** — ID Unidade e nome do totem (ID Medidor)
- **Dispositivo Bluetooth** — medidor de pressão pareado
- **Diagnóstico** — visualização dos logs do dispositivo

---

## Tecnologias

| Camada | Tecnologia |
|---|---|
| App | Flutter + Riverpod |
| Detecção de rosto | Google ML Kit |
| Embedding facial | DeepFace / Facenet512 (TensorFlow via Chaquopy) |
| Bluetooth | BLE nativo (Android/Kotlin) |
| Backend | Forza ERP (GeneXus) |

Veja a [`DOCUMENTACAO.md`](DOCUMENTACAO.md) para detalhes de cada parte.
