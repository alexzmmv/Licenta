"""
Tokenizer verification tool — validate Swift WordPiece output matches Python.

Purpose: The Swift WordPieceTokenizer MUST produce identical token IDs to
HuggingFace. If they differ, all embeddings will be wrong even with a
perfect model.

How to use:
  1. Run this script: python backup/verify_tokenizer.py
  2. Copy the printed token IDs
  3. Run the same sentences through the Swift tokenizer
  4. Confirm the IDs match exactly

Any mismatch → fix the Swift tokenizer before running on-device.

Pitfall ref: 09_AI_PITFALLS.md Pitfall 2.1
"""

from transformers import AutoTokenizer

TEST_SENTENCES = [
    "I felt happy today",
    "I am feeling anxious about tomorrow's meeting",
    "She was overwhelmed with joy and gratitude",
    "Nothing really happened, just a quiet day",
    "I can't believe how angry I got over something so small",
    "I'm grateful for the support from my friends",
    "Feeling hopeful about the future",
    "unknownword123 thetestsentence ##subword",  # edge case: unknown tokens
]

MAX_LENGTH = 128
MODELS = [
    ("google/mobilebert-uncased", "../models/mobilebert-stsb"),
    ("distilbert-base-uncased",   "../models/distilbert-stsb"),
]


def tokenize_and_print(tokenizer_path: str, label: str):
    print(f"\n{'='*60}")
    print(f"Tokenizer: {label}")
    print(f"{'='*60}")

    try:
        tokenizer = AutoTokenizer.from_pretrained(tokenizer_path, cache_dir="../hf_cache")
    except Exception as e:
        print(f"Could not load from {tokenizer_path}: {e}")
        return

    print(f"Vocab size: {tokenizer.vocab_size}")
    print(f"[CLS] id: {tokenizer.cls_token_id}  [SEP] id: {tokenizer.sep_token_id}  [UNK] id: {tokenizer.unk_token_id}  [PAD] id: {tokenizer.pad_token_id}")
    print()

    for sentence in TEST_SENTENCES:
        enc = tokenizer(
            sentence,
            padding="max_length",
            max_length=MAX_LENGTH,
            truncation=True,
        )
        input_ids     = enc["input_ids"]
        attention_mask = enc["attention_mask"]
        real_len      = sum(attention_mask)

        # Show only real tokens (no padding)
        real_ids  = input_ids[:real_len]
        real_toks = tokenizer.convert_ids_to_tokens(real_ids)

        print(f"Sentence : {sentence[:60]}")
        print(f"Token IDs: {real_ids}")
        print(f"Tokens   : {real_toks}")
        print(f"Attn mask: {attention_mask[:real_len]} (then {MAX_LENGTH - real_len} zeros)")
        print()

    print("─" * 60)
    print("Copy the Token IDs above and compare against Swift WordPieceTokenizer output.")
    print("They MUST match exactly. Any difference = embedding corruption.")


if __name__ == "__main__":
    for model_name, local_path in MODELS:
        # Prefer local fine-tuned model, fall back to HuggingFace download
        from pathlib import Path
        source = local_path if Path(local_path).exists() else model_name
        tokenize_and_print(source, model_name)
