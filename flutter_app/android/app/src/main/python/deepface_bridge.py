import base64
import io
import os
import shutil
from typing import Dict, List

import numpy as np
from PIL import Image
from deepface.modules import modeling, representation


_MODEL_CACHE: Dict[str, object] = {}


def _ensure_bundled_weights(model_name: str) -> None:
    if model_name != "Facenet512":
        return

    source = os.path.join(
        os.path.dirname(__file__),
        "weights",
        "facenet512_weights.h5",
    )
    if not os.path.isfile(source):
        return

    deepface_home = os.getenv("DEEPFACE_HOME", os.path.expanduser("~"))
    target_dir = os.path.join(deepface_home, ".deepface", "weights")
    target = os.path.join(target_dir, "facenet512_weights.h5")

    if os.path.isfile(target) and os.path.getsize(target) == os.path.getsize(source):
        return

    os.makedirs(target_dir, exist_ok=True)
    shutil.copyfile(source, target)


def _decode_image(base64_image: str) -> np.ndarray:
    raw = base64.b64decode(base64_image)
    image = Image.open(io.BytesIO(raw)).convert("RGB")
    return np.array(image)


def _get_model(model_name: str):
    model = _MODEL_CACHE.get(model_name)
    if model is None:
        _ensure_bundled_weights(model_name)
        model = modeling.build_model(task="facial_recognition", model_name=model_name)
        _MODEL_CACHE[model_name] = model
    return model


def warmup_model(model_name: str = "Facenet512") -> bool:
    _get_model(model_name)
    return True


def extract_embedding(base64_image: str, model_name: str = "Facenet512") -> List[float]:
    image = _decode_image(base64_image)
    # Preload once to surface model/bootstrap errors earlier and keep the model warm.
    _get_model(model_name)
    result = representation.represent(
        img_path=image,
        model_name=model_name,
        detector_backend="skip",
        enforce_detection=False,
        align=False,
        normalization="base",
    )
    if not result:
        raise RuntimeError("DeepFace nao retornou embeddings para a imagem recebida.")

    embedding = result[0].get("embedding")
    if not embedding:
        raise RuntimeError("DeepFace retornou um embedding vazio.")

    return [float(value) for value in embedding]
