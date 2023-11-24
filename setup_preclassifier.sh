#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR"

python3 -m venv pre_classifier_env > /dev/null
touch pre_classifier_env/.gdignore
source pre_classifier_env/bin/activate > /dev/null

pip install torch transformers nltk --quiet --disable-pip-version-check > /dev/null

python3 pre_classifier.py