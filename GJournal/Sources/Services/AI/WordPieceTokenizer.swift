import Foundation

struct TokenizerOutput {
    let inputIDs: [Int32]
    let attentionMask: [Int32]

    let realTokenCount: Int
}

final class WordPieceTokenizer {
    static let maxLength = 128

    private let vocab: [String: Int]
    private let clsID: Int
    private let sepID: Int
    private let unkID: Int
    private let padID: Int

    init(vocabURL: URL) throws {
        let lines = try String(contentsOf: vocabURL, encoding: .utf8)
            .components(separatedBy: .newlines)
        var vocab = [String: Int]()
        for (index, line) in lines.enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { vocab[token] = index }
        }
        self.vocab = vocab
        self.clsID = vocab["[CLS]"] ?? 101
        self.sepID = vocab["[SEP]"] ?? 102
        self.unkID = vocab["[UNK]"] ?? 100
        self.padID = vocab["[PAD]"] ?? 0
    }

    convenience init(vocabResource: String = "vocab") throws {
        guard let url = Bundle.main.url(forResource: vocabResource, withExtension: "txt") else {
            throw TokenizerError.vocabFileNotFound(vocabResource)
        }
        try self.init(vocabURL: url)
    }

    func tokenize(_ text: String) -> TokenizerOutput {
        var tokenIDs: [Int] = [clsID]

        let lowercased = text.lowercased()

        let tokens = basicTokenize(lowercased)

        for token in tokens {
            let wordTokens = wordPieceTokenize(token)
            let remaining = Self.maxLength - 2 - tokenIDs.count + 1  // -2 for CLS+SEP
            if remaining <= 0 { break }
            tokenIDs.append(contentsOf: wordTokens.prefix(remaining))
        }

        tokenIDs.append(sepID)
        let realCount = tokenIDs.count

        while tokenIDs.count < Self.maxLength {
            tokenIDs.append(padID)
        }

        let inputIDs    = tokenIDs.map { Int32($0) }
        let attentionMask = (0..<Self.maxLength).map { Int32($0 < realCount ? 1 : 0) }

        return TokenizerOutput(
            inputIDs: inputIDs,
            attentionMask: attentionMask,
            realTokenCount: realCount
        )
    }

    // MARK: - Basic tokenization
    
    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        
        for char in text {
            if isWhitespace(char) {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else if isPunctuation(char) {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            tokens.append(current)
        }
        
        return tokens
    }
    
    private func isWhitespace(_ char: Character) -> Bool {
        char.isWhitespace
    }
    
    private func isPunctuation(_ char: Character) -> Bool {
        // BERT considers these as punctuation boundaries:
        // ASCII: !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
        let punctuation = "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
        return punctuation.contains(char)
    }

    // MARK: - WordPiece core

    private func wordPieceTokenize(_ word: String) -> [Int] {
        var result: [Int] = []
        var remaining = word

        while !remaining.isEmpty {
            var longestMatch: String?
            var longestLen = 0
            let isFirst = (remaining == word)
            let prefix = isFirst ? "" : "##"

            for end in stride(from: remaining.count, through: 1, by: -1) {
                let candidate = prefix + String(remaining.prefix(end))
                if vocab[candidate] != nil {
                    longestMatch = candidate
                    longestLen = end
                    break
                }
            }

            if let match = longestMatch {
                result.append(vocab[match]!)
                remaining = String(remaining.dropFirst(longestLen))
            } else {
                result.append(unkID)
                remaining = String(remaining.dropFirst(1))
            }
        }

        return result.isEmpty ? [unkID] : result
    }
}

enum TokenizerError: LocalizedError {
    case vocabFileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .vocabFileNotFound(let name):
            return "vocab file '\(name).txt' not found in app bundle"
        }
    }
}
