import coremltools as ct
import numpy as np

# Load model
model = ct.models.MLModel('training/coreml_models/GJournalEmbeddingDistilBERT.mlpackage')

# Create dummy inputs
input_ids = np.zeros((1, 128), dtype=np.int32)
input_ids[0, 0] = 101 # [CLS]
input_ids[0, 1] = 2000
input_ids[0, 2] = 102 # [SEP]

attention_mask = np.zeros((1, 128), dtype=np.int32)
attention_mask[0, 0:3] = 1

# Predict
out = model.predict({'input_ids': input_ids, 'attention_mask': attention_mask})

hidden = out['last_hidden_state']
print("Shape:", hidden.shape)
print("CLS token first 10 values:", hidden[0, 0, :10])
