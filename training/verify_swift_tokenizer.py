#!/usr/bin/env python3
"""
Verify Swift WordPieceTokenizer against Python tokenizer output.

This script loads the actual MobileBERT vocab files from the project and
compares the Swift tokenizer implementation (implemented in Python here for testing)
against the Python tokenizer output.

Usage:
    python verify_swift_tokenizer.py

Expected output: All test cases pass and match the Python tokenizer output.
"""

import json
from pathlib import Path
from typing import List, Tuple

# Expected token IDs from Python verify_tokenizer.py (MobileBERT)
TEST_CASES = [
    ("I felt happy today", [101, 1045, 2371, 3407, 2651, 102]),
    ("I am feeling anxious about tomorrow's meeting", [101, 1045, 2572, 3110, 11480, 2055, 4826, 1005, 1055, 3116, 102]),
    ("She was overwhelmed with joy and gratitude", [101, 2016, 2001, 13394, 2007, 6569, 1998, 15531, 102]),
    ("Nothing really happened, just a quiet day", [101, 2498, 2428, 3047, 1010, 2074, 1037, 4251, 2154, 102]),
    ("I can't believe how angry I got over something so small", [101, 1045, 2064, 1005, 1056, 2903, 2129, 4854, 1045, 2288, 2058, 2242, 2061, 2235, 102]),
    ("I'm grateful for the support from my friends", [101, 1045, 1005, 1049, 8794, 2005, 1996, 2490, 2013, 2026, 2814, 102]),
    ("Feeling hopeful about the future", [101, 3110, 17772, 2055, 1996, 2925, 102]),
]

class SwiftTokenizerValidator:
    """Swift WordPieceTokenizer implementation in Python for validation."""
    
    def __init__(self, vocab_path: str):
        self.vocab = self._load_vocab(vocab_path)
        self.cls_id = self.vocab.get("[CLS]", 101)
        self.sep_id = self.vocab.get("[SEP]", 102)
        self.unk_id = self.vocab.get("[UNK]", 100)
        self.pad_id = self.vocab.get("[PAD]", 0)
        self.max_length = 128
    
    def _load_vocab(self, vocab_path: str) -> dict:
        """Load vocab.txt file into {token: id} dict."""
        vocab = {}
        try:
            with open(vocab_path, 'r', encoding='utf-8') as f:
                for idx, line in enumerate(f):
                    token = line.rstrip('\n').strip()
                    if token:
                        vocab[token] = idx
            print(f"✓ Loaded vocab from {vocab_path} ({len(vocab)} tokens)")
            return vocab
        except FileNotFoundError:
            print(f"✗ Vocab file not found: {vocab_path}")
            raise
    
    def tokenize(self, text: str) -> List[int]:
        """Tokenize text (Swift implementation)."""
        token_ids = [self.cls_id]
        
        lowercased = text.lower()
        tokens = self._basic_tokenize(lowercased)
        
        for token in tokens:
            word_tokens = self._wordpiece_tokenize(token)
            remaining = self.max_length - 2 - len(token_ids) + 1
            if remaining <= 0:
                break
            token_ids.extend(word_tokens[:remaining])
        
        token_ids.append(self.sep_id)
        
        while len(token_ids) < self.max_length:
            token_ids.append(self.pad_id)
        
        return token_ids
    
    def _basic_tokenize(self, text: str) -> List[str]:
        """Split on whitespace and punctuation (BERT basic tokenization)."""
        tokens = []
        current = ""
        
        for char in text:
            if char.isspace():
                if current:
                    tokens.append(current)
                    current = ""
            elif self._is_punctuation(char):
                if current:
                    tokens.append(current)
                    current = ""
                tokens.append(char)
            else:
                current += char
        
        if current:
            tokens.append(current)
        
        return tokens
    
    def _is_punctuation(self, char: str) -> bool:
        """Check if character is BERT punctuation."""
        punct = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~'
        return char in punct
    
    def _wordpiece_tokenize(self, word: str) -> List[int]:
        """WordPiece tokenization with ## prefix for subwords."""
        tokens = []
        remaining = word
        
        while remaining:
            longest_match = None
            longest_len = 0
            is_first = (remaining == word)
            prefix = "" if is_first else "##"
            
            # Try longest match first
            for end in range(len(remaining), 0, -1):
                candidate = prefix + remaining[:end]
                if candidate in self.vocab:
                    longest_match = candidate
                    longest_len = end
                    break
            
            if longest_match:
                tokens.append(self.vocab[longest_match])
                remaining = remaining[longest_len:]
            else:
                # No match — emit [UNK] and move to next character
                tokens.append(self.unk_id)
                remaining = remaining[1:]
        
        return tokens if tokens else [self.unk_id]


def find_vocab_file() -> str:
    """Find MobileBERT vocab file in the project."""
    project_root = Path(__file__).parent.parent
    vocab_files = [
        project_root / "GJournal" / "MLModels" / "vocab_gjournalembeddingmobilebert.txt",
        project_root / "GJournal" / "MLModels" / "vocab_gjournalembeddingdistilbert.txt",
        project_root / "training" / "vocab_mobilebert.txt",
    ]
    
    for vocab_file in vocab_files:
        if vocab_file.exists():
            return str(vocab_file)
    
    raise FileNotFoundError(
        f"Could not find vocab file. Searched:\n" +
        "\n".join(str(f) for f in vocab_files)
    )


def main():
    print("=" * 70)
    print("SWIFT WORDPIECE TOKENIZER VERIFICATION")
    print("=" * 70)
    
    # Find and load vocab
    try:
        vocab_path = find_vocab_file()
    except FileNotFoundError as e:
        print(f"\n✗ Error: {e}")
        print("\nMake sure you're running this from the Licenta directory.")
        exit(1)
    
    validator = SwiftTokenizerValidator(vocab_path)
    
    print("\n" + "-" * 70)
    print("Running validation tests:")
    print("-" * 70 + "\n")
    
    passed = 0
    failed = 0
    failures = []
    
    for text, expected_ids in TEST_CASES:
        result = validator.tokenize(text)
        
        # Compare only the real tokens (not padding)
        real_count = len(expected_ids)
        result_tokens = result[:real_count]
        
        if result_tokens == expected_ids:
            print(f"✅ PASS: \"{text}\"")
            passed += 1
        else:
            print(f"❌ FAIL: \"{text}\"")
            print(f"   Expected: {expected_ids}")
            print(f"   Got:      {result_tokens}")
            print()
            failed += 1
            failures.append((text, expected_ids, result_tokens))
    
    print("\n" + "=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)
    
    if failures:
        print("\n⚠️  FAILURE DETAILS:")
        for text, expected, result in failures:
            print(f"\nSentence: \"{text}\"")
            print(f"Expected ({len(expected)} tokens): {expected}")
            print(f"Got ({len(result)} tokens):      {result}")
            
            # Show differences
            max_len = max(len(expected), len(result))
            print("Diff:")
            for i in range(max_len):
                exp = expected[i] if i < len(expected) else "MISSING"
                res = result[i] if i < len(result) else "MISSING"
                match = "✓" if exp == res else "✗"
                print(f"  [{i:2d}] {match} expected {exp:5} got {res:5}")
    else:
        print("\n✅ All tests passed! Swift tokenizer matches Python output.")
        print("\nThe Swift WordPieceTokenizer is ready for use in CoreML models.")
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    exit(main())
