import Foundation

enum TranscriptOutputStyle: String {
    case verbatim = "verbatim"
    case clean = "clean"
    case cleanHinglish = "clean_hinglish"
}

enum TranscriptProcessingMode: String {
    case dictation = "dictation"
    case rewrite = "rewrite"
}

class WhisperService {
    private let transcriptionEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    private let completionEndpoint = "https://api.openai.com/v1/chat/completions"
    private let transcriptionModel = "gpt-4o-transcribe"
    private let fallbackTranscriptionModel = "whisper-1"
    private let textModel = "gpt-4.1-mini"
    
    func transcribeAndPolish(
        audioData: Data,
        language: String = "hi",
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        transcribe(audioData: audioData, language: language) { [weak self] result in
            switch result {
            case .success(let transcript):
                self?.postProcess(text: transcript, style: style, processingMode: processingMode) { polished in
                    switch polished {
                    case .success(let text):
                        completion(.success(text))
                    case .failure(let error):
                        print("Post-processing failed, using raw transcript: \(error)")
                        completion(.success(transcript))
                    }
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func transcribe(audioData: Data, language: String = "hi", completion: @escaping (Result<String, Error>) -> Void) {
        transcribeWithModel(audioData: audioData, language: language, model: transcriptionModel) { [weak self] result in
            switch result {
            case .success:
                completion(result)
            case .failure(let error):
                if self?.shouldRetryWithFallback(error: error) == true {
                    self?.transcribeWithModel(audioData: audioData, language: language, model: self?.fallbackTranscriptionModel ?? "whisper-1", completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    private func transcribeWithModel(
        audioData: Data,
        language: String,
        model: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let apiKey = UserDefaults.standard.string(forKey: "openai_api_key")
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ""
        guard !apiKey.isEmpty else {
            completion(.failure(WhisperError.noAPIKey))
            return
        }
        
        guard let url = URL(string: transcriptionEndpoint) else {
            completion(.failure(WhisperError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .ascii)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .ascii)!)
        body.append(audioData)
        body.append("\r\n".data(using: .ascii)!)
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .ascii)!)
        body.append("\(model)\r\n".data(using: .ascii)!)

        // Encourage same-language transcript with Latin script for Hindi content.
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .ascii)!)
        body.append("Do not translate. Keep original spoken language. If speech is Hindi, output Hindi words in Latin script (Hinglish). Use plain text.\r\n".data(using: .ascii)!)
        
        if language != "auto" {
            body.append("--\(boundary)\r\n".data(using: .ascii)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .ascii)!)
            body.append("\(language)\r\n".data(using: .ascii)!)
        }
        
        body.append("--\(boundary)--\r\n".data(using: .ascii)!)
        
        request.httpBody = body
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(WhisperError.noData))
                return
            }
            
            // Parse JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["text"] as? String {
                    completion(.success(text))
                } else {
                    // If no text field, check for error
                    if let errorJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? [String: Any],
                       let message = errorMessage["message"] as? String {
                        completion(.failure(WhisperError.apiError(message)))
                    } else {
                        completion(.failure(WhisperError.parseError))
                    }
                }
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }

    private func shouldRetryWithFallback(error: Error) -> Bool {
        guard case let WhisperError.apiError(message) = error else {
            return false
        }
        let lowered = message.lowercased()
        return lowered.contains("model") || lowered.contains("not found") || lowered.contains("not have access")
    }

    private func postProcess(
        text: String,
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(""))
            return
        }

        if style == .verbatim {
            completion(.success(trimmed))
            return
        }

        if style == .cleanHinglish {
            normalizeBilingualSegments(text: trimmed, processingMode: processingMode, completion: completion)
            return
        }

        let styleInstruction: String
        switch style {
        case .clean:
            styleInstruction = "Return polished English text with grammar and punctuation fixed."
        case .cleanHinglish:
            styleInstruction = """
            Return polished bilingual text in Latin script only.
            If speech is English, keep English wording in English.
            If speech is Hindi, keep Hindi wording but write it in Latin script (example: "mera naam raunak hai").
            For mixed speech, preserve each segment's language naturally.
            Never output Devanagari or any non-Latin script.
            Do not translate across languages unless the user explicitly asked to translate.
            """
        case .verbatim:
            styleInstruction = ""
        }

        let rewriteInstruction = processingMode == .rewrite
            ? "Rewrite the transcript into concise, polished final text and infer implied question intent when obvious."
            : "Stay close to the spoken wording."

        let systemPrompt = """
        You are a speech-to-text cleanup assistant.
        Keep the original meaning exactly.
        Remove filler words (umm, uh, ahh, matlab, like, you know) when not meaningful.
        Fix grammar, punctuation, capitalization, and sentence boundaries.
        Do not add new facts.
        \(rewriteInstruction)
        Output plain text only.
        \(styleInstruction)
        """

        runChatCompletion(systemPrompt: systemPrompt, userText: trimmed) { [weak self] result in
            switch result {
            case .success(let cleaned):
                if style == .cleanHinglish, self?.containsDevanagari(cleaned) == true {
                    self?.forceLatinScript(input: cleaned, completion: completion)
                } else {
                    completion(.success(cleaned))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func normalizeBilingualSegments(
        text: String,
        processingMode: TranscriptProcessingMode,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let rewriteInstruction = processingMode == .rewrite
            ? "If user intent is clearly a question or request, rewrite naturally as that final request."
            : "Keep wording close to spoken dictation."

        let prompt = """
        You are a bilingual transcript normalizer.
        Process each sentence independently.
        Rules:
        1) English speech remains English wording.
        2) Hindi speech remains Hindi wording, but in Latin script only.
        3) Mixed speech stays mixed naturally.
        4) Remove filler words and fix punctuation/grammar.
        5) Never output Devanagari or any non-Latin script.
        6) Do not translate English into Hindi or Hindi into English.
        7) \(rewriteInstruction)
        Output only final plain text.
        """

        runChatCompletion(systemPrompt: prompt, userText: text) { [weak self] result in
            switch result {
            case .success(let normalized):
                if self?.containsDevanagari(normalized) == true {
                    self?.forceLatinScript(input: normalized, completion: completion)
                } else {
                    completion(.success(normalized))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func forceLatinScript(input: String, completion: @escaping (Result<String, Error>) -> Void) {
        let locallyTransliterated = transliterateToLatin(input)
        if !containsDevanagari(locallyTransliterated) {
            completion(.success(locallyTransliterated))
            return
        }

        let prompt = """
        Convert only non-Latin script portions to Latin script.
        Never output Devanagari or any non-Latin script.
        Preserve original wording and language choice.
        Keep English text in English.
        Keep Hindi text in Hindi wording but Latin letters.
        Output plain text only.
        """

        runChatCompletion(systemPrompt: prompt, userText: input, completion: completion)
    }

    private func transliterateToLatin(_ text: String) -> String {
        let transformed = text.applyingTransform(.toLatin, reverse: false) ?? text
        let asciiLike = transformed.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let squashedSpaces = asciiLike.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return squashedSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runChatCompletion(
        systemPrompt: String,
        userText: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let apiKey = UserDefaults.standard.string(forKey: "openai_api_key")
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ""
        guard !apiKey.isEmpty else {
            completion(.failure(WhisperError.noAPIKey))
            return
        }

        guard let url = URL(string: completionEndpoint) else {
            completion(.failure(WhisperError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": textModel,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(WhisperError.noData))
                return
            }

            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let choices = json["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let message = firstChoice["message"] as? [String: Any],
                    let content = message["content"] as? String
                else {
                    if let errorJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? [String: Any],
                       let message = errorMessage["message"] as? String {
                        completion(.failure(WhisperError.apiError(message)))
                    } else {
                        completion(.failure(WhisperError.parseError))
                    }
                    return
                }

                completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func containsDevanagari(_ text: String) -> Bool {
        return text.range(of: "[\\u0900-\\u097F]", options: .regularExpression) != nil
    }
    
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "openai_api_key")
    }
}

enum WhisperError: LocalizedError {
    case noAPIKey
    case invalidURL
    case noData
    case parseError
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured"
        case .invalidURL:
            return "Invalid API URL"
        case .noData:
            return "No data received from API"
        case .parseError:
            return "Failed to parse response"
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
}
