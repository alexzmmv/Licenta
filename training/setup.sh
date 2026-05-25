#!/bin/bash
# GJournal training environment setup
# Supports: M1 Mac (MPS), Windows/Linux PC (CUDA), CPU fallback
set -e

echo "=== GJournal Training Setup ==="

# Create and activate venv
python3 -m venv venv
source venv/bin/activate

echo "Python: $(python --version)"
echo "Pip: $(pip --version)"

pip install --upgrade pip --quiet

# Core ML / conversion (best on Mac, must be >=7.2 for iOS17 target)
pip install "coremltools>=7.2" --quiet

# PyTorch — single command works for both M1 (MPS) and CUDA
pip install torch torchvision --quiet

# NLP / training
pip install "sentence-transformers==3.0.0" --quiet
pip install "transformers>=4.40.0" --quiet
pip install "datasets>=2.19.0" --quiet
pip install "accelerate>=0.30.0" --quiet
pip install evaluate --quiet

# ML utilities
pip install "scikit-learn>=1.4.0" --quiet
pip install "numpy>=1.26.0" --quiet
pip install scipy --quiet

# ONNX (backup conversion path)
pip install "onnx>=1.16.0" onnxruntime --quiet

echo ""
echo "=== Device Check ==="
python3 - <<'EOF'
import torch
cuda = torch.cuda.is_available()
mps  = torch.backends.mps.is_available()
print(f"CUDA available : {cuda}")
if cuda:
    print(f"  GPU          : {torch.cuda.get_device_name(0)}")
    print(f"  VRAM         : {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
print(f"MPS  available : {mps}")
device = "cuda" if cuda else "mps" if mps else "cpu"
print(f"Active device  : {device}")
if device == "cpu":
    print("WARNING: Training on CPU will be very slow. Consider using a GPU.")
EOF

echo ""
echo "=== coremltools Check ==="
python3 -c "import coremltools as ct; print(f'coremltools {ct.__version__}')"

echo ""
echo "Setup complete. Activate with: source venv/bin/activate"
