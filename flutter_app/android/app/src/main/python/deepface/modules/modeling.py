# built-in dependencies
from importlib import import_module
from typing import Any


_MODEL_LOADERS = {
    "facial_recognition": {
        "VGG-Face": ("deepface.models.facial_recognition.VGGFace", "VggFaceClient"),
        "OpenFace": ("deepface.models.facial_recognition.OpenFace", "OpenFaceClient"),
        "Facenet": ("deepface.models.facial_recognition.Facenet", "FaceNet128dClient"),
        "Facenet512": ("deepface.models.facial_recognition.Facenet", "FaceNet512dClient"),
        "DeepFace": ("deepface.models.facial_recognition.FbDeepFace", "DeepFaceClient"),
        "DeepID": ("deepface.models.facial_recognition.DeepID", "DeepIdClient"),
        "Dlib": ("deepface.models.facial_recognition.Dlib", "DlibClient"),
        "ArcFace": ("deepface.models.facial_recognition.ArcFace", "ArcFaceClient"),
        "SFace": ("deepface.models.facial_recognition.SFace", "SFaceClient"),
        "GhostFaceNet": (
            "deepface.models.facial_recognition.GhostFaceNet",
            "GhostFaceNetClient",
        ),
        "Buffalo_L": ("deepface.models.facial_recognition.Buffalo_L", "Buffalo_L"),
    },
    "spoofing": {
        "Fasnet": ("deepface.models.spoofing.FasNet", "Fasnet"),
    },
    "facial_attribute": {
        "Emotion": ("deepface.models.demography.Emotion", "EmotionClient"),
        "Age": ("deepface.models.demography.Age", "ApparentAgeClient"),
        "Gender": ("deepface.models.demography.Gender", "GenderClient"),
        "Race": ("deepface.models.demography.Race", "RaceClient"),
    },
    "face_detector": {
        "opencv": ("deepface.models.face_detection.OpenCv", "OpenCvClient"),
        "mtcnn": ("deepface.models.face_detection.MtCnn", "MtCnnClient"),
        "ssd": ("deepface.models.face_detection.Ssd", "SsdClient"),
        "dlib": ("deepface.models.face_detection.Dlib", "DlibClient"),
        "retinaface": ("deepface.models.face_detection.RetinaFace", "RetinaFaceClient"),
        "mediapipe": ("deepface.models.face_detection.MediaPipe", "MediaPipeClient"),
        "yolov8": ("deepface.models.face_detection.Yolo", "YoloDetectorClientV8n"),
        "yolov11n": ("deepface.models.face_detection.Yolo", "YoloDetectorClientV11n"),
        "yolov11s": ("deepface.models.face_detection.Yolo", "YoloDetectorClientV11s"),
        "yolov11m": ("deepface.models.face_detection.Yolo", "YoloDetectorClientV11m"),
        "yunet": ("deepface.models.face_detection.YuNet", "YuNetClient"),
        "fastmtcnn": ("deepface.models.face_detection.FastMtCnn", "FastMtCnnClient"),
        "centerface": ("deepface.models.face_detection.CenterFace", "CenterFaceClient"),
    },
}


def build_model(task: str, model_name: str) -> Any:
    """
    This function loads a pre-trained models as singletonish way
    Parameters:
        task (str): facial_recognition, facial_attribute, face_detector, spoofing
        model_name (str): model identifier
            - VGG-Face, Facenet, Facenet512, OpenFace, DeepFace, DeepID, Dlib,
                ArcFace, SFace and GhostFaceNet for face recognition
            - Age, Gender, Emotion, Race for facial attributes
            - opencv, mtcnn, ssd, dlib, retinaface, mediapipe, yolov8, 'yolov11n',
                'yolov11s', 'yolov11m', yunet, fastmtcnn or centerface for face detectors
            - Fasnet for spoofing
    Returns:
            built model class
    """

    # singleton design pattern
    global cached_models

    if _MODEL_LOADERS.get(task) is None:
        raise ValueError(f"unimplemented task - {task}")

    if not "cached_models" in globals():
        cached_models = {current_task: {} for current_task in _MODEL_LOADERS.keys()}

    if cached_models[task].get(model_name) is None:
        loader = _MODEL_LOADERS[task].get(model_name)
        if loader is None:
            raise ValueError(f"Invalid model_name passed - {task}/{model_name}")

        module_name, class_name = loader
        module = import_module(module_name)
        cached_models[task][model_name] = getattr(module, class_name)()

    return cached_models[task][model_name]
