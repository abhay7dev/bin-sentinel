LABEL_MAP = {
    'tableware': 'plastic container',
    'kitchenware': 'plastic container',
    'drinkware': 'plastic bottle',
    'bottle': 'plastic bottle',
    'plastic bottle': 'plastic bottle',
    'plastic bag': 'plastic bag film',
    'shopping bag': 'plastic bag film',
    'bag': 'plastic bag film',
    'paper bag': 'paper bag',
    'garden hose': 'garden hose tangler',
    'hose': 'garden hose tangler',
    'food packaging': 'plastic container',
    'packaging': 'plastic container',
    'container': 'plastic container',
    'pizza box': 'pizza box cardboard',
    'box': 'cardboard box',
    'aluminum can': 'aluminum can metal',
    'tin can': 'steel tin can metal',
    'glass bottle': 'glass bottle jar',
    'jar': 'glass bottle jar',
    'foam': 'styrofoam EPS foam',
    'styrofoam': 'styrofoam EPS foam',
    'newspaper': 'newspaper paper',
    'cardboard': 'corrugated cardboard',
    'cup': 'disposable cup',
    'straw': 'plastic straw',
    'cutlery': 'plastic cutlery utensil',
}


def normalize_labels(labels: list[str]) -> str:
    return ' '.join(LABEL_MAP.get(l.lower(), l.lower()) for l in labels[:4])
