from google.cloud import vision

from vision_normalize import normalize_labels


def identify_object(image_bytes: bytes) -> dict:
    client = vision.ImageAnnotatorClient()
    image = vision.Image(content=image_bytes)

    label_response = client.label_detection(image=image)
    labels = label_response.label_annotations

    object_response = client.object_localization(image=image)
    objects = object_response.localized_object_annotations

    if not labels:
        return {
            "label": "unknown item",
            "all_labels": [],
            "objects": [],
            "normalized": "unknown item",
        }

    all_labels = [label.description for label in labels[:5]]
    object_names = [obj.name for obj in objects]
    normalized = normalize_labels(all_labels)

    return {
        "label": all_labels[0],
        "all_labels": all_labels,
        "objects": object_names,
        "normalized": normalized,
    }
