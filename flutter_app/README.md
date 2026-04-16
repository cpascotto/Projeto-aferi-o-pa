# Flutter App

Aplicativo Flutter/Android responsavel pela captura facial, extracao local de embeddings e comparacao local com os pacientes sincronizados da API.

## Fluxo atual

- A splash aquece o runtime Python/DeepFace no APK.
- A camera frontal captura a foto e o ML Kit detecta o rosto localmente.
- A imagem e normalizada, recortada e enviada ao `DeepFace` via channel nativo.
- O app baixa os pacientes de `/api/patients` e compara os embeddings localmente.
- Se houver reconhecimento, o fluxo segue no app.
- Se nao houver reconhecimento, o paciente e cadastrado por CPF e depois registra 1 foto facial.

## Estrutura principal

- `lib/main.dart`: shell do app e inicializacao global.
- `lib/screens/`: telas do fluxo de splash, captura, identificacao, CPF e cadastro facial.
- `lib/providers/`: estado do fluxo de identificacao, logs e providers de servicos.
- `lib/services/`: integracoes com API, ML Kit, normalizacao/crop e bridge do DeepFace.
- `lib/models/patient_model.dart`: modelo usado pelo app para pacientes e embeddings.
- `android/app/src/main/kotlin/.../MainActivity.kt`: channel nativo para warmup e embeddings.
- `android/app/src/main/python/deepface_bridge.py`: bridge Python que chama o DeepFace empacotado.

## Observacoes

- O backend Laravel participa apenas de persistencia e leitura.
- O fluxo antigo baseado em ArcFace/ONNX nao faz mais parte do app.
